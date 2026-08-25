from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
UPGRADE = ROOT / "tools" / "windows_app_control_upgrade_acceptance.ps1"
FINAL = ROOT / "tools" / "windows_app_control_local_gate_complete.ps1"


class WindowsAppControlFinalLocalGateContractTests(unittest.TestCase):
    def test_upgrade_gate_requires_distinct_baseline_and_exact_hashes(self):
        text = UPGRADE.read_text(encoding="utf-8")
        for expected in (
            "BaselineSetupSha256",
            "BaselineApplicationSha256",
            "BaselineVersion",
            "BaselineSupplementalPolicyId",
            "BaselineManifestPath",
            "BaselineTrustPackDirectory",
            "same-version repair is not accepted as upgrade evidence",
            "real_cross_version_upgrade",
            "post_upgrade_exact_bytes",
            "state_preserved",
        ):
            self.assertIn(expected, text)

    def test_upgrade_gate_requires_active_enforced_app_control(self):
        text = UPGRADE.read_text(encoding="utf-8")
        for expected in (
            "CiTool",
            "-lp -json",
            "is_enforced",
            "is_on_disk",
            "Base App Control policy is not enforced/on-disk",
            "Baseline supplemental policy is not active/on-disk",
            "Current supplemental policy is not active/on-disk",
        ):
            self.assertIn(expected, text)

    def test_upgrade_gate_does_not_deploy_or_weaken_policy(self):
        text = UPGRADE.read_text(encoding="utf-8").lower()
        for forbidden in ("& $citool --update-policy", "& $citool --remove-policy", "verifiedandreputablepolicystate", "set-ruleoption"):
            self.assertNotIn(forbidden, text)

    def test_upgrade_gate_checks_code_integrity_blocks_and_post_state(self):
        text = UPGRADE.read_text(encoding="utf-8")
        for expected in (
            "Microsoft-Windows-CodeIntegrity/Operational",
            "3077",
            "no_upgrade_enforcement_blocks",
            "app_control_remained_enforced",
            "post_upgrade_uninstall",
        ):
            self.assertIn(expected, text)

    def test_upgrade_gate_uses_real_recovered_0_2_2_as_canonical_baseline(self):
        text = UPGRADE.read_text(encoding="utf-8")
        for expected in (
            "LegacyClientZip",
            "0ea08d9c815da36d0175f62db153de78f89731fc",
            "574d3dc5f90a116555e3a72ff3288c31c19d3dc7",
            "baseline_exact_historical_bytes",
            "baseline_gui_execution_under_enforcement",
        ):
            self.assertIn(expected, text)

    def test_final_gate_cannot_pass_without_upgrade_and_current_release_subgates(self):
        text = FINAL.read_text(encoding="utf-8")
        for expected in (
            "windows_app_control_upgrade_acceptance.ps1",
            "windows_app_control_local_gate.ps1",
            "upgrade_gate = 'NOT_RUN'",
            "current_release_gate = 'NOT_RUN'",
            "$final.upgrade_gate = 'PASS'",
            "$final.current_release_gate = 'PASS'",
            "if ($final.result -ne 'PASS')",
            "Historical 0.2.2 P0.4 -> exact 0.2.3 cross-version upgrade: PASS",
        ):
            self.assertIn(expected, text)

    def test_final_gate_is_host_only_and_does_not_manage_app_control_policy(self):
        text = FINAL.read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertIn("IsolatedAcceptanceEnvironment", text)
        self.assertIn("dedicated/isolated Windows 11 acceptance host", text)
        self.assertIn("abandoned Windows VM path is out of scope", text)
        self.assertIn("LegacyClientZip", text)
        for forbidden in ("--update-policy", "--remove-policy"):
            self.assertNotIn(forbidden, lowered)
        self.assertNotIn("VerifiedAndReputablePolicyState", text)


if __name__ == "__main__":
    unittest.main()
