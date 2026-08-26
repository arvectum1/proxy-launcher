from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
READINESS = ROOT / "tools" / "windows_app_control_enforced_readiness.ps1"
STATIC_BUILD = ROOT / "tools" / "build_windows_appcontrol_static_runtime.ps1"
FINAL = ROOT / "tools" / "windows_app_control_local_gate_complete.ps1"


class WindowsAppControlPostIncidentHardeningTests(unittest.TestCase):
    def test_static_runtime_builder_uses_onedir_not_onefile(self):
        text = STATIC_BUILD.read_text(encoding="utf-8")
        self.assertIn("--onedir", text)
        self.assertNotIn("--onefile", text)
        self.assertIn("pyinstaller_onefile = $false", text)
        self.assertIn("packaging_layout = 'static-runtime'", text)
        self.assertIn("runtime_complete = $true", text)

    def test_static_runtime_builder_never_claims_full_lifecycle_readiness(self):
        text = STATIC_BUILD.read_text(encoding="utf-8")
        self.assertIn("installer_lifecycle_complete = $false", text)
        self.assertIn("enforced_lifecycle_ready = $false", text)
        self.assertIn("Installer lifecycle readiness: NOT YET PROVEN", text)

    def test_static_runtime_builder_does_not_manage_app_control(self):
        lowered = STATIC_BUILD.read_text(encoding="utf-8").lower()
        for forbidden in (
            "--update-policy",
            "--remove-policy",
            "set-ruleoption",
            "set-mppreference",
            "verifiedandreputablepolicystate",
        ):
            self.assertNotIn(forbidden, lowered)

    def test_readiness_requires_recovery_rehearsal_before_mutation(self):
        readiness = READINESS.read_text(encoding="utf-8")
        final = FINAL.read_text(encoding="utf-8")
        for expected in (
            "recovery_rehearsal",
            "Enforced/ConstrainedLanguage",
            "restores_exact_current_release",
            "restores_pac_connectivity",
            "changes_base_to_audit",
        ):
            self.assertIn(expected, readiness)
        self.assertLess(final.index("& $readiness"), final.index("& $canonical"))

    def test_legacy_referencefullhash_is_explicitly_retired_for_destructive_gate(self):
        text = READINESS.read_text(encoding="utf-8")
        self.assertIn("legacy trust-pack schema v1 is insufficient", text)
        self.assertIn("ReferenceFullHash alone is insufficient", text)
        self.assertIn("PyInstaller onefile is prohibited", text)
        self.assertIn("ARVECTUM-DEMO incident / issue #10", text)


if __name__ == "__main__":
    unittest.main()
