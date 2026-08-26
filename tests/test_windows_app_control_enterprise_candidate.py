from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
INNO = ROOT / "installer" / "ArvectumProxyLauncher.AppControl.iss"
BUILD = ROOT / "tools" / "build_windows_appcontrol_installer.ps1"
RECOVERY_SOURCE = ROOT / "tools" / "windows_app_control_recovery.cs"
RECOVERY_BUILD = ROOT / "tools" / "build_windows_appcontrol_recovery.ps1"
STATIC_BUILD = ROOT / "tools" / "build_windows_appcontrol_static_runtime.ps1"


class WindowsAppControlEnterpriseCandidateTests(unittest.TestCase):
    def test_inno_candidate_disables_setup_loader_and_temp_product_execution(self):
        text = INNO.read_text(encoding="utf-8")
        self.assertIn("UseSetupLdr=no", text)
        self.assertIn("Static onedir runtime", text)
        self.assertIn("No product PowerShell helper", text)
        self.assertNotIn("upgrade_helper.ps1", text)
        self.assertNotIn("uninstall_helper.ps1", text)
        self.assertNotIn("powershell.exe", text.lower())
        self.assertNotIn('DestDir: "{tmp}"', text)
        self.assertNotIn("ExtractTemporaryFile", text)

    def test_inno_candidate_rolls_back_network_before_mutation_and_uninstall(self):
        text = INNO.read_text(encoding="utf-8")
        for expected in (
            "PrepareToInstall",
            "InitializeUninstall",
            "RunRollback",
            "--rollback",
            "Existing Launcher network rollback failed; lifecycle mutation is blocked",
            "RemoveOwnedRunValue",
            "LegacyTaskOwned",
            "Foreign/unknown Run value preserved",
        ):
            self.assertIn(expected, text)

    def test_enterprise_builder_is_not_a_silent_replacement_for_sealed_023(self):
        text = BUILD.read_text(encoding="utf-8")
        for expected in (
            "appcontrol-candidate",
            "promoted_release = $false",
            "UseSetupLdr: NO",
            "PyInstaller onefile: NO",
            "Native recovery: INCLUDED",
            "Enforced lifecycle readiness: NOT YET PROVEN",
        ):
            self.assertIn(expected, text)
        self.assertIn("rescue-runtime", text)
        self.assertIn("enterprise-bundle.json", text)

    def test_native_recovery_does_not_depend_on_powershell_or_change_policy(self):
        source = RECOVERY_SOURCE.read_text(encoding="utf-8")
        build = RECOVERY_BUILD.read_text(encoding="utf-8")
        combined = (source + build).lower()
        for forbidden in (
            "powershell.exe",
            "set-ruleoption",
            "--update-policy",
            "--remove-policy",
            "set-mppreference",
        ):
            self.assertNotIn(forbidden, combined)
        self.assertIn("requires_powershell_runtime = $false", build)
        self.assertIn("app_control_policy_mutation = $false", build)

    def test_native_recovery_is_exact_runtime_and_real_pac_bound(self):
        source = RECOVERY_SOURCE.read_text(encoding="utf-8")
        for expected in (
            "expected-runtime-sha256",
            "Static recovery runtime launcher SHA256 mismatch",
            "proxy_settings.json",
            "no_proxy.txt",
            "proxy_core.pid",
            "proxy_env_backup.json",
            "proxy_internet_backup.json",
            "http://127.0.0.1:8082/proxy.pac",
            "FindExactLauncherPid",
            "AutoConfigURL",
            "PAC HTTP: 200",
            "changes_app_control_policy",
        ):
            self.assertIn(expected, source)

    def test_static_runtime_remains_onedir_and_not_claimed_ready_too_early(self):
        text = STATIC_BUILD.read_text(encoding="utf-8")
        self.assertIn("--onedir", text)
        self.assertIn("pyinstaller_onefile = $false", text)
        self.assertIn("runtime_complete = $true", text)
        self.assertIn("installer_lifecycle_complete = $false", text)
        self.assertIn("enforced_lifecycle_ready = $false", text)


if __name__ == "__main__":
    unittest.main()
