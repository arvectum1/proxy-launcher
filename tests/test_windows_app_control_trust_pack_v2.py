from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT / "tools" / "windows_app_control_enterprise_trust_pack_v2.ps1"
READINESS = ROOT / "tools" / "windows_app_control_enforced_readiness.ps1"


class WindowsAppControlTrustPackV2Tests(unittest.TestCase):
    def test_v2_requires_real_enforced_lifecycle_and_recovery_evidence(self):
        text = V2.read_text(encoding="utf-8")
        for expected in (
            "EnforcedLifecycleEvidencePath",
            "RecoveryRehearsalEvidencePath",
            "arvectum.proxy.windows-app-control-enforced-lifecycle.v1",
            "arvectum.proxy.apl-win-014-native-recovery-rehearsal.v1",
            "environment -ne 'Enforced'",
            "Enforced/ConstrainedLanguage",
            "base_remained_enforced",
            "supplemental_remained_active",
            "code_integrity_3077_blocks",
            "restores_exact_current_release",
            "restores_pac_connectivity",
            "changes_base_to_audit",
            "enterprise_bundle_manifest_sha256",
        ):
            self.assertIn(expected, text)

    def test_v2_requires_static_runtime_setupldr_disabled_and_reference_uninstaller(self):
        text = V2.read_text(encoding="utf-8")
        for expected in (
            "static_runtime",
            "pyinstaller_onefile",
            "setup_loader -ne 'disabled'",
            "setup_runs_from_temp",
            "rescue-runtime\\static-runtime.json",
            "legacy top-level onefile executable survives",
            "exactly one generated Inno uninstaller",
            "UseSetupLdr=no sibling BIN is missing",
        ):
            self.assertIn(expected, text)

    def test_v2_hash_policy_sanitizes_audit_option_and_never_deploys(self):
        text = V2.read_text(encoding="utf-8")
        lowered = text.lower()
        for expected in (
            "New-CIPolicy",
            "-Level Hash",
            "Set-CIPolicyIdInfo",
            "-SupplementsBasePolicyID",
            "Set-RuleOption -FilePath $xml -Option 3 -Delete",
            "Enabled:Audit Mode",
            "ConvertFrom-CIPolicy",
            "arvectum.proxy.windows-app-control-enterprise-trust-pack.v2",
            "mode = 'StaticRuntimeLifecycleHash'",
            "enforced_lifecycle_ready = $true",
        ):
            self.assertIn(expected, text)
        for forbidden in (
            "& $citool --update-policy",
            "--remove-policy",
            "set-mppreference",
            "verifiedandreputablepolicystate",
        ):
            self.assertNotIn(forbidden, lowered)

    def test_readiness_contract_matches_v2_manifest(self):
        generator = V2.read_text(encoding="utf-8")
        readiness = READINESS.read_text(encoding="utf-8")
        shared = (
            "arvectum.proxy.windows-app-control-enterprise-trust-pack.v2",
            "static-runtime",
            "runtime_complete",
            "installer_lifecycle_complete",
            "enforced_lifecycle_ready",
            "recovery_rehearsal",
            "restores_exact_current_release",
            "restores_pac_connectivity",
            "changes_base_to_audit",
        )
        for expected in shared:
            self.assertIn(expected, generator)
            self.assertIn(expected, readiness)


if __name__ == "__main__":
    unittest.main()
