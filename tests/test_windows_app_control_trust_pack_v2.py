from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROVISIONAL = ROOT / "tools" / "windows_app_control_provisional_trust_pack.ps1"
EXTRACTOR = ROOT / "tools" / "extract_pyinstaller_onefile_runtime.py"
V2 = ROOT / "tools" / "windows_app_control_enterprise_trust_pack_v2.ps1"
READINESS = ROOT / "tools" / "windows_app_control_enforced_readiness.ps1"


class WindowsAppControlTrustPackV2Tests(unittest.TestCase):
    def test_provisional_pack_breaks_circular_dependency_without_claiming_acceptance(self):
        text = PROVISIONAL.read_text(encoding="utf-8")
        for expected in (
            "arvectum.proxy.windows-app-control-provisional-trust-pack.v1",
            "purpose = 'rehearsal-only'",
            "final_acceptance_evidence = $false",
            "enforced_lifecycle_ready = $false",
            "New-CIPolicy",
            "-Level Hash",
            "Set-CIPolicyIdInfo",
            "-SupplementsBasePolicyID",
            "Set-RuleOption -FilePath $xml -Option 3 -Delete",
            "ConvertFrom-CIPolicy",
            "reference_uninstaller_sha256",
            "uninstaller_deterministic",
            "normal_uninstaller_determinism = 'PASS'",
        ):
            self.assertIn(expected, text)
        lowered = text.lower()
        for forbidden in (
            "& $citool --update-policy",
            "--remove-policy",
            "set-mppreference",
            "verifiedandreputablepolicystate",
        ):
            self.assertNotIn(forbidden, lowered)

    def test_historical_022_onefile_native_runtime_is_admitted_without_execution(self):
        provisional = PROVISIONAL.read_text(encoding="utf-8")
        extractor = EXTRACTOR.read_text(encoding="utf-8")
        for expected in (
            "HistoricalPackageDirectory",
            "HistoricalRuntimeDirectory",
            "7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0",
            "arvectum.proxy.pyinstaller-onefile-runtime-inventory.v1",
            "historical_onefile_runtime_inventory_sha256",
            "historical_onefile_runtime_executable_count",
            "historical_onefile_runtime_executables",
            "historical_onefile_input_executed_during_trust_build = $false",
            "immutable 0.2.2 onefile native CArchive members are admitted without executing the input",
        ):
            self.assertIn(expected, provisional)
        for expected in (
            "CArchiveReader",
            '"executed_input": False',
            "archive.extract(name)",
            "safe_member_path",
            "executable_member_count",
        ):
            self.assertIn(expected, extractor)
        self.assertNotIn("subprocess", extractor)
        self.assertNotIn("Popen", extractor)

    def test_v2_requires_real_enforced_lifecycle_and_recovery_bound_to_provisional_bytes(self):
        text = V2.read_text(encoding="utf-8")
        for expected in (
            "ProvisionalTrustPackDirectory",
            "EnforcedLifecycleEvidencePath",
            "RecoveryRehearsalEvidencePath",
            "arvectum.proxy.windows-app-control-provisional-trust-pack.v1",
            "arvectum.proxy.windows-app-control-enforced-lifecycle.v1",
            "arvectum.proxy.apl-win-014-native-recovery-rehearsal.v1",
            "environment -ne 'Enforced'",
            "Enforced/ConstrainedLanguage",
            "provisional_trust_pack_manifest_sha256",
            "provisional_cip_sha256",
            "supplemental_policy_id",
            "runtime_entry_sha256",
            "uninstaller_sha256",
            "base_remained_enforced",
            "supplemental_remained_active",
            "code_integrity_3077_blocks",
            "restores_exact_current_release",
            "restores_pac_connectivity",
            "changes_base_to_audit",
            "enterprise_bundle_manifest_sha256",
        ):
            self.assertIn(expected, text)

    def test_v2_promotes_exact_rehearsal_tested_policy_instead_of_rebuilding_it(self):
        text = V2.read_text(encoding="utf-8")
        lowered = text.lower()
        for expected in (
            "Copy-Item -LiteralPath $provisionalXml",
            "Copy-Item -LiteralPath $provisionalCip",
            "the exact rehearsal-tested provisional XML/CIP is copied unchanged",
            "arvectum.proxy.windows-app-control-enterprise-trust-pack.v2",
            "mode = 'StaticRuntimeLifecycleHash'",
            "enforced_lifecycle_ready = $true",
            "installer_lifecycle_complete = $true",
        ):
            self.assertIn(expected, text)
        for forbidden in (
            "new-cipolicy",
            "set-cipolicyidinfo",
            "convertfrom-cipolicy",
            "--update-policy",
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
