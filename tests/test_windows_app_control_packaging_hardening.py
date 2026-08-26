from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")


class WindowsAppControlPackagingHardeningTests(unittest.TestCase):
    def test_windows_build_is_static_onedir_not_onefile(self):
        build = read("tools/clean_build_windows.ps1")
        self.assertIn("--onedir", build)
        self.assertNotIn("--onefile", build)
        self.assertIn("--contents-directory", build)
        self.assertIn("runtime", build)
        self.assertIn("RUNTIME_SHA256SUMS.txt", build)

    def test_portable_contract_hash_binds_entire_runtime_tree(self):
        build = read("tools/clean_build_windows.ps1")
        self.assertIn("runtime\\Arvectum Proxy Launcher.exe", build)
        self.assertIn("Get-ChildItem -LiteralPath $BuiltRuntime -File -Recurse", build)
        self.assertIn("runtime_file_count", build)
        self.assertIn("runtime_tree_sha256", build)

    def test_windows_ci_copies_whole_runtime_tree(self):
        workflow = read(".github/workflows/windows-p0.yml")
        self.assertIn("dist/Arvectum Proxy Launcher", workflow)
        self.assertIn("Copy-Item -LiteralPath $builtRuntime", workflow)
        self.assertIn("-Recurse", workflow)
        self.assertIn("Arvectum Proxy Launcher.exe", workflow)

    def test_installer_payload_is_full_static_runtime_tree(self):
        build = read("tools/build_windows_installer.ps1")
        self.assertIn("dist\\Arvectum Proxy Launcher", build)
        self.assertIn("installer-payload\\runtime", build)
        self.assertIn("runtime_manifest", build)
        self.assertIn("runtime_file_count", build)

    def test_trust_pack_sanitizes_supplemental_audit_option(self):
        pack = read("tools/windows_app_control_enterprise_trust_pack.ps1")
        self.assertIn("Set-RuleOption", pack)
        self.assertIn("-Option 3", pack)
        self.assertIn("-Delete", pack)
        self.assertIn("Enabled:Audit Mode", pack)
        self.assertIn("StaticRuntimeHash", pack)

    def test_inno_loader_and_temp_helper_execution_are_not_enterprise_accepted(self):
        iss = read("installer/ArvectumProxyLauncher.iss")
        self.assertIn("UseSetupLdr=no", iss)
        self.assertNotIn("ExtractTemporaryFile('upgrade_helper.ps1')", iss)
        self.assertNotIn("RunEmbeddedHelper", iss)
        self.assertNotIn("WindowsPowerShell", iss)

    def test_app_control_docs_record_real_stand_rejection_of_onefile(self):
        doc = read("docs/WINDOWS_APP_CONTROL_COMPATIBILITY.md")
        for token in (
            "ARVECTUM-DEMO",
            "_MEI",
            "Error 4551",
            "ConstrainedLanguage",
            "onedir",
            "acceptance remains paused",
        ):
            self.assertIn(token, doc)


if __name__ == "__main__":
    unittest.main()
