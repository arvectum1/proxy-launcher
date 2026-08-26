"""Canonical portable-executable lifecycle for Arvectum Proxy Launcher.

Owns the Windows portable stable-copy lifecycle: hash-verified replacement,
install-owner marking, safe handoff and canonical-install recognition.

The forward Windows enterprise build is a PyInstaller ``onedir`` runtime.  A
portable handoff therefore owns the *whole* frozen runtime tree, not just the
launcher EXE.  Historical ``onefile`` builds remain readable for recovery and
legacy classification, but new production builds must not depend on their
runtime extraction behavior.
"""

from __future__ import annotations

import hashlib
import io
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


def _is_frozen_onedir() -> bool:
    """Return True only for a frozen one-folder runtime.

    PyInstaller onefile sets ``sys._MEIPASS`` to a temporary extraction
    directory.  Onedir sets it to the static bundle location.  The distinction
    is intentionally runtime-derived so sealed historical onefile builds keep
    their old single-EXE self-heal behavior while new onedir builds copy the
    complete static tree.
    """
    core = _core()
    if not getattr(sys, "frozen", False):
        return False
    bundle = getattr(sys, "_MEIPASS", "")
    if not bundle:
        return False
    return not core.is_temporary_path(bundle)


def _runtime_tree_records(root: str) -> list[tuple[str, str]]:
    """Return deterministic ``(relative path, sha256)`` runtime records."""
    core = _core()
    marker_name = core._INSTALL_OWNER_MARKER
    records: list[tuple[str, str]] = []
    for current, dirs, files in os.walk(root):
        dirs.sort(key=str.casefold)
        files.sort(key=str.casefold)
        for name in files:
            full = os.path.join(current, name)
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            if relative == marker_name:
                continue
            records.append((relative, core._sha256_file(full)))
    records.sort(key=lambda item: item[0].casefold())
    return records


def _runtime_tree_sha256(root: str) -> str:
    digest = hashlib.sha256()
    for relative, file_hash in _runtime_tree_records(root):
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(file_hash.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def _copy_runtime_tree_verified(source_root: str, target_root: str) -> None:
    """Replace *target_root* with a byte-verified copy of *source_root*.

    The new tree is assembled in a sibling directory, verified by a
    deterministic path+hash digest, then swapped into place.  If the previous
    canonical tree cannot be moved (for example because an old process still
    owns it), the operation fails closed and leaves the source portable process
    usable instead of partially updating the canonical runtime.
    """
    core = _core()
    source_root = os.path.realpath(source_root)
    target_root = os.path.realpath(target_root)
    parent = os.path.dirname(target_root)
    os.makedirs(parent, exist_ok=True)

    token = "%s.%s" % (os.getpid(), hashlib.sha256(source_root.encode()).hexdigest()[:10])
    staged = target_root + ".runtime-new-" + token
    previous = target_root + ".runtime-old-" + token

    for path in (staged, previous):
        if os.path.exists(path):
            shutil.rmtree(path, ignore_errors=True)

    try:
        shutil.copytree(source_root, staged, copy_function=shutil.copy2)
        source_hash = core._runtime_tree_sha256(source_root)
        staged_hash = core._runtime_tree_sha256(staged)
        if source_hash != staged_hash:
            raise IOError("stable runtime tree copy hash mismatch")

        moved_previous = False
        if os.path.exists(target_root):
            os.replace(target_root, previous)
            moved_previous = True
        try:
            os.replace(staged, target_root)
        except Exception:
            if moved_previous and not os.path.exists(target_root):
                os.replace(previous, target_root)
            raise
        if moved_previous:
            shutil.rmtree(previous, ignore_errors=True)
    finally:
        if os.path.exists(staged):
            shutil.rmtree(staged, ignore_errors=True)
        if os.path.exists(previous) and os.path.exists(target_root):
            shutil.rmtree(previous, ignore_errors=True)


def _is_historical_documents_copy(path: str) -> bool:
    core = _core()
    return core._same_path(path, core.stable_app_exe())


def _write_install_owner_marker(target_dir: str) -> None:
    core = _core()
    with io.open(
        os.path.join(target_dir, core._INSTALL_OWNER_MARKER),
        "w",
        encoding="ascii",
    ) as marker:
        marker.write(core._INSTALL_OWNER_VALUE)


def ensure_stable_app_copy() -> str | None:
    """Materialize the frozen Windows runtime at the canonical Documents path.

    New PyInstaller onedir builds copy and verify the complete static runtime
    directory.  Historical onefile builds retain the former single-EXE copy so
    recovery of sealed releases does not accidentally copy arbitrary Desktop or
    Downloads siblings into the managed installation.
    """
    core = _core()
    if not (core.is_windows() and getattr(sys, "frozen", False)):
        return None
    core._LAST_SELF_HEAL_ERROR = ""
    source = os.path.realpath(sys.executable)
    target = os.path.realpath(core.stable_app_exe())
    target_dir = os.path.dirname(target)
    if core._same_path(source, target):
        return target

    try:
        if core._is_frozen_onedir():
            source_dir = os.path.dirname(source)
            if os.path.isdir(target_dir) and os.path.isfile(target):
                try:
                    if core._runtime_tree_sha256(source_dir) == core._runtime_tree_sha256(target_dir):
                        core._write_install_owner_marker(target_dir)
                        return target
                except OSError:
                    pass
            core._copy_runtime_tree_verified(source_dir, target_dir)
            if not os.path.isfile(target):
                raise IOError("canonical onedir runtime has no launcher executable")
            core._write_install_owner_marker(target_dir)
            core._log(
                "portable onedir runtime copied to canonical Documents location: %s"
                % target_dir
            )
            return target

        # Historical PyInstaller onefile compatibility.  Never broaden this
        # branch to copy the containing directory: that directory can be an
        # arbitrary user Downloads/Desktop location.
        os.makedirs(target_dir, exist_ok=True)
        if os.path.isfile(target) and core._sha256_file(source) == core._sha256_file(target):
            core._write_install_owner_marker(target_dir)
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
        core._write_install_owner_marker(target_dir)
        core._log("legacy portable launcher copied to canonical Documents location: %s" % target)
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
    return core.ensure_stable_app_copy()


def handoff_to_stable_copy(arguments: Iterable[str] | None = None) -> bool:
    """Continue a portable launch only from the verified canonical runtime."""
    core = _core()
    if not (core.is_windows() and getattr(sys, "frozen", False)):
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
        core._log("portable launcher handed off to canonical Documents runtime")
        return True
    except Exception as error:
        core._log(
            "portable launcher handoff failed; keeping current GUI open: %r" % error
        )
        return False


def canonical_install_exe() -> str | None:
    """Return the canonical Documents path only when it matches this runtime."""
    core = _core()
    if not getattr(sys, "frozen", False):
        return None
    target = os.path.realpath(core.stable_app_exe())
    source = os.path.realpath(sys.executable)
    if core._same_path(source, target):
        return None
    try:
        if not os.path.isfile(target):
            return None
        if core._is_frozen_onedir():
            source_dir = os.path.dirname(source)
            target_dir = os.path.dirname(target)
            if core._runtime_tree_sha256(source_dir) == core._runtime_tree_sha256(target_dir):
                return target
            return None
        if core._sha256_file(source) == core._sha256_file(target):
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
    core._is_frozen_onedir = _is_frozen_onedir
    core._runtime_tree_records = _runtime_tree_records
    core._runtime_tree_sha256 = _runtime_tree_sha256
    core._copy_runtime_tree_verified = _copy_runtime_tree_verified
    core._is_historical_documents_copy = _is_historical_documents_copy
    core._write_install_owner_marker = _write_install_owner_marker
    core.ensure_stable_app_copy = ensure_stable_app_copy
    core.self_heal_error = self_heal_error
    core.managed_executable = managed_executable
    core.handoff_to_stable_copy = handoff_to_stable_copy
    core.canonical_install_exe = canonical_install_exe
    core.handoff_to_canonical_install = handoff_to_canonical_install
    return core
