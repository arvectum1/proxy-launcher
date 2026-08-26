"""Canonical portable-executable lifecycle for Arvectum Proxy Launcher.

Owns the Windows portable stable-copy lifecycle: hash-verified replacement, install-owner marking, safe handoff and canonical-install recognition. Runtime collaborators resolve through the canonical composition module.

App-Control static-runtime packages are deliberately different from historical
PyInstaller onefile portable packages: an onedir executable must never be copied
away from its sibling DLL/PYD runtime. A validated ``static-runtime.json`` marker
therefore makes that frozen runtime in-place and disables onefile self-handoff.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
from types import ModuleType
from typing import Iterable


_CORE: ModuleType | None = None


def configure(core: ModuleType) -> None:
    """Bind the canonical composition module used for runtime collaborators."""
    global _CORE
    _CORE = core


def _core() -> ModuleType:
    if _CORE is None:
        raise RuntimeError("portable lifecycle is not configured")
    return _CORE


def _sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _static_runtime_manifest() -> dict | None:
    """Return a validated onedir marker for the currently running frozen EXE."""
    if not getattr(sys, "frozen", False):
        return None
    source = os.path.realpath(sys.executable)
    marker = os.path.join(os.path.dirname(source), "static-runtime.json")
    if not os.path.isfile(marker):
        return None
    try:
        with io.open(marker, "r", encoding="utf-8-sig") as stream:
            manifest = json.load(stream)
        if manifest.get("schema") != "arvectum.proxy.windows-app-control-static-runtime.v1":
            return None
        if manifest.get("result") != "PASS":
            return None
        if manifest.get("packaging_layout") != "static-runtime":
            return None
        if manifest.get("pyinstaller_onefile") is not False:
            return None
        if manifest.get("entry_executable") != os.path.basename(source):
            return None
        expected = str(manifest.get("entry_sha256") or "").lower()
        if len(expected) != 64 or _sha256_file(source).lower() != expected:
            return None
        return manifest
    except Exception:
        return None


def _static_runtime_install_root() -> str | None:
    """Return the owned installation root for an installed static runtime.

    Rescue-runtime copies intentionally have the same static marker but no
    install-owner marker. They remain runnable for recovery yet can never become
    a persistent autostart target by accident.
    """
    core = _core()
    if _static_runtime_manifest() is None:
        return None
    source_dir = os.path.dirname(os.path.realpath(sys.executable))
    runtime_parent = os.path.dirname(source_dir)
    if os.path.basename(runtime_parent).lower() != "runtime":
        return None
    install_root = os.path.dirname(runtime_parent)
    marker = os.path.join(install_root, core._INSTALL_OWNER_MARKER)
    try:
        with io.open(marker, "r", encoding="ascii") as stream:
            value = stream.read().strip()
    except OSError:
        return None
    if value != core._INSTALL_OWNER_VALUE:
        return None
    return install_root


def _is_historical_documents_copy(path: str) -> bool:
    core = _core()
    return core._same_path(path, core.stable_app_exe())


def ensure_stable_app_copy() -> str | None:
    """Return/copy a Windows frozen launcher to its governed execution location.

    Historical onefile portable builds keep the hash-verified Documents self-copy
    behavior. App-Control static-runtime (onedir) builds MUST stay beside their
    runtime DLL/PYD files and are therefore returned in place without copying.
    """
    core = _core()
    if not (core.is_windows() and getattr(sys, "frozen", False)):
        return None
    core._LAST_SELF_HEAL_ERROR = ""
    source = os.path.realpath(sys.executable)

    if _static_runtime_manifest() is not None:
        core._log("static runtime detected; onefile stable-copy self-heal is disabled")
        return source

    target = os.path.realpath(core.stable_app_exe())
    if core._same_path(source, target):
        return target
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if (
            os.path.isfile(target)
            and core._sha256_file(source) == core._sha256_file(target)
        ):
            return target
        temporary = target + ".%s.tmp" % os.getpid()
        try:
            shutil.copy2(source, temporary)
            if core._sha256_file(source) != core._sha256_file(temporary):
                raise IOError("stable executable copy hash mismatch")
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                try:
                    os.remove(temporary)
                except OSError:
                    pass
        with io.open(
            os.path.join(os.path.dirname(target), core._INSTALL_OWNER_MARKER),
            "w",
            encoding="ascii",
        ) as marker:
            marker.write(core._INSTALL_OWNER_VALUE)
        core._log("portable launcher copied to canonical Documents location: %s" % target)
        return target
    except Exception as error:
        core._LAST_SELF_HEAL_ERROR = (
            "Не удалось обновить постоянную копию Launcher в Documents: %s" % error
        )
        core._log("portable launcher self-heal failed: %r" % error)
        return None


def self_heal_error() -> str:
    return _core()._LAST_SELF_HEAL_ERROR


def managed_executable() -> str | None:
    """Return the only executable path allowed in Windows Run entries."""
    core = _core()
    if not getattr(sys, "frozen", False):
        return None
    if _static_runtime_manifest() is not None:
        if _static_runtime_install_root() is None:
            return None
        return os.path.realpath(sys.executable)
    return core.ensure_stable_app_copy()


def handoff_to_stable_copy(arguments: Iterable[str] | None = None) -> bool:
    """Continue a portable launch only from the matching governed location."""
    core = _core()
    if not (core.is_windows() and getattr(sys, "frozen", False)):
        return False
    if _static_runtime_manifest() is not None:
        # onedir must execute in place with its sibling runtime; never copy/handoff
        # only the EXE to the historical top-level Documents location.
        return False
    source = os.path.realpath(sys.executable)
    target = core.ensure_stable_app_copy()
    if not target or core._same_path(source, target):
        return False
    try:
        subprocess.Popen(
            [target] + list(arguments or []),
            cwd=os.path.dirname(target),
            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
        )
        core._log("portable launcher handed off to canonical Documents copy")
        return True
    except Exception as error:
        core._log(
            "portable launcher handoff failed; keeping current GUI open: %r" % error
        )
        return False


def canonical_install_exe() -> str | None:
    """Return the current executable only when it is a governed installed runtime."""
    core = _core()
    if not getattr(sys, "frozen", False):
        return None
    source = os.path.realpath(sys.executable)
    if _static_runtime_manifest() is not None:
        return source if _static_runtime_install_root() is not None else None

    target = os.path.realpath(core.stable_app_exe())
    if core._same_path(source, target):
        return None
    try:
        if (
            os.path.isfile(target)
            and core._sha256_file(source) == core._sha256_file(target)
        ):
            return target
    except Exception:
        pass
    return None


def handoff_to_canonical_install() -> bool:
    """Compatibility wrapper for the single canonical handoff mechanism."""
    return _core().handoff_to_stable_copy()


def install_into_core(core: ModuleType) -> ModuleType:
    """Expose canonical portable-lifecycle seams through the core module object."""
    core._sha256_file = _sha256_file
    core._static_runtime_manifest = _static_runtime_manifest
    core._static_runtime_install_root = _static_runtime_install_root
    core._is_historical_documents_copy = _is_historical_documents_copy
    core.ensure_stable_app_copy = ensure_stable_app_copy
    core.self_heal_error = self_heal_error
    core.managed_executable = managed_executable
    core.handoff_to_stable_copy = handoff_to_stable_copy
    core.canonical_install_exe = canonical_install_exe
    core.handoff_to_canonical_install = handoff_to_canonical_install
    return core
