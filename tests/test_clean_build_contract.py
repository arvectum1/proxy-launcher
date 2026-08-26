import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class CleanBuildContractTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def test_build_python_version_pinned(self):
        self.assertTrue((ROOT / "BUILD_PYTHON_VERSION").is_file())
        version = self.read("BUILD_PYTHON_VERSION").strip()
        self.assertEqual(version, "3.12.10")

    def test_requirements_build_lock_pinned(self):
        self.assertTrue((ROOT / "requirements-build.lock.txt").is_file())
        lock_text = self.read("requirements-build.lock.txt")
        self.assertIn("pyinstaller==6.22.0", lock_text)
        self.assertNotIn(">=", lock_text)
        self.assertNotIn("~=", lock_text)
        self.assertNotIn("*", lock_text)

    def test_clean_build_windows_script_contract(self):
        self.assertTrue((ROOT / "tools" / "clean_build_windows.ps1").is_file())
        script = self.read("tools/clean_build_windows.ps1")
        for token in (".build-venv", "build", "dist", "out", "artifact"):
            self.assertIn(token, script)
        self.assertIn("-m venv", script)
        self.assertIn("sys.prefix != sys.base_prefix", script)
        self.assertIn("pip==26.1.2", script)
        self.assertNotIn("pip==25.3", script)
        self.assertIn("requirements-build.lock.txt", script)
        self.assertIn("requirements-build.windows-x64.hashes.txt", script)
        self.assertIn("--no-index", script)
        self.assertIn("--require-hashes", script)
        self.assertIn("pip check", script)
        self.assertIn("py_compile", script)
        self.assertIn("unittest discover", script)
        self.assertIn("PyInstaller", script)
        self.assertIn("--onedir", script)
        self.assertNotIn("--onefile", script)
        self.assertIn("--contents-directory '.'", script)
        self.assertIn("dist\\Arvectum Proxy Launcher", script)
        self.assertIn("RUNTIME_SHA256SUMS.txt", script)
        self.assertIn("runtime_tree_sha256", script)
        self.assertIn("runtime_file_count", script)
        self.assertIn("SHA256SUMS.txt", script)
        self.assertIn("Compress-Archive", script)
        self.assertIn("Expand-Archive", script)
        self.assertIn("build-result.json", script)

    def test_build_exe_bat_is_wrapper(self):
        bat = self.read("build_exe.bat")
        self.assertIn("tools\\clean_build_windows.ps1", bat)
        self.assertNotIn("PyInstaller", bat)
        self.assertNotIn("pip install", bat)
        self.assertNotIn("unittest", bat)

    def test_windows_workflow_uses_clean_build_script(self):
        workflow = self.read(".github/workflows/windows-p0.yml")
        self.assertIn("python-version: '3.12.10'", workflow)
        self.assertIn("./tools/clean_build_windows.ps1", workflow)
        self.assertNotIn("PyInstaller --noconfirm", workflow)
        self.assertNotIn("pip install --upgrade pip==", workflow)

    def test_package_does_not_contain_runtime_state_or_secrets(self):
        script = self.read("tools/clean_build_windows.ps1")
        self.assertIn("$ExpectedFiles = @('README.txt', 'diagnose_app_control.ps1', 'run_p01_native_qa_v2.ps1', 'SHA256SUMS.txt', 'RUNTIME_SHA256SUMS.txt')", script)
        expected_section = script.split("$ExpectedFiles", 1)[1].split("foreach", 1)[0]
        self.assertNotIn("proxy_settings.json", expected_section)
        self.assertNotIn("no_proxy.txt", expected_section)
        self.assertIn("runtime", script)


if __name__ == "__main__":
    unittest.main()
