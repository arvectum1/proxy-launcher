import hashlib
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest import mock

import portable_lifecycle


class StaticRuntimePortableLifecycleTests(unittest.TestCase):
    def _core(self, stable_target: Path):
        core = types.SimpleNamespace()
        core._INSTALL_OWNER_MARKER = ".arvectum-install-owner"
        core._INSTALL_OWNER_VALUE = "ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER"
        core._LAST_SELF_HEAL_ERROR = ""
        core.is_windows = lambda: True
        core.stable_app_exe = lambda: str(stable_target)
        core._same_path = lambda a, b: os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))
        core._log = lambda message: None
        portable_lifecycle.configure(core)
        portable_lifecycle.install_into_core(core)
        return core

    def _write_static_runtime(self, directory: Path):
        directory.mkdir(parents=True, exist_ok=True)
        exe = directory / "Arvectum Proxy Launcher.exe"
        exe.write_bytes(b"static-runtime-entry")
        digest = hashlib.sha256(exe.read_bytes()).hexdigest()
        (directory / "static-runtime.json").write_text(
            json.dumps(
                {
                    "schema": "arvectum.proxy.windows-app-control-static-runtime.v1",
                    "result": "PASS",
                    "packaging_layout": "static-runtime",
                    "pyinstaller_onefile": False,
                    "entry_executable": exe.name,
                    "entry_sha256": digest,
                }
            ),
            encoding="utf-8",
        )
        return exe

    def test_rescue_onedir_runs_in_place_but_never_becomes_autostart_target(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            exe = self._write_static_runtime(root / "bundle" / "rescue-runtime")
            stable = root / "Documents" / "ArvectumProxyLauncher" / "Arvectum Proxy Launcher.exe"
            core = self._core(stable)
            with mock.patch.object(portable_lifecycle.sys, "frozen", True, create=True), mock.patch.object(
                portable_lifecycle.sys, "executable", str(exe)
            ):
                self.assertEqual(core.ensure_stable_app_copy(), str(exe.resolve()))
                self.assertFalse(core.handoff_to_stable_copy(["--start"]))
                self.assertIsNone(core.managed_executable())
                self.assertFalse(stable.exists())

    def test_installed_onedir_is_managed_in_place_with_owner_marker(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            install_root = root / "Documents" / "ArvectumProxyLauncher"
            exe = self._write_static_runtime(install_root / "runtime" / "appcontrol-0.2.3")
            (install_root / ".arvectum-install-owner").write_text(
                "ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER", encoding="ascii"
            )
            historical = install_root / "Arvectum Proxy Launcher.exe"
            core = self._core(historical)
            with mock.patch.object(portable_lifecycle.sys, "frozen", True, create=True), mock.patch.object(
                portable_lifecycle.sys, "executable", str(exe)
            ):
                self.assertEqual(core.ensure_stable_app_copy(), str(exe.resolve()))
                self.assertEqual(core.managed_executable(), str(exe.resolve()))
                self.assertEqual(core.canonical_install_exe(), str(exe.resolve()))
                self.assertFalse(core.handoff_to_stable_copy())
                self.assertFalse(historical.exists())

    def test_tampered_static_marker_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            exe = self._write_static_runtime(root / "runtime")
            manifest_path = exe.parent / "static-runtime.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["entry_sha256"] = "0" * 64
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            self._core(root / "stable" / "Arvectum Proxy Launcher.exe")
            with mock.patch.object(portable_lifecycle.sys, "frozen", True, create=True), mock.patch.object(
                portable_lifecycle.sys, "executable", str(exe)
            ):
                self.assertIsNone(portable_lifecycle._static_runtime_manifest())


if __name__ == "__main__":
    unittest.main()
