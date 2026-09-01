from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools" / "windows_app_control_candidate_runner.ps1"


class WindowsAppControlCandidateRunnerTests(unittest.TestCase):
    def test_preflight_and_recover_delegate_without_finalization(self):
        text = RUNNER.read_text(encoding="utf-8")
        self.assertIn("if ($Mode -eq 'Recover')", text)
        self.assertIn("& $StandDriver -Mode Recover", text)
        self.assertIn("if ($Mode -eq 'Preflight')", text)
        self.assertIn("& $StandDriver -Mode Preflight", text)
        execute_pos = text.index("& $StandDriver -Mode Execute")
        promotion_pos = text.index("& $PromotionScript")
        self.assertLess(execute_pos, promotion_pos)

    def test_finalization_requires_real_pass_evidence_and_same_policy_promotion(self):
        text = RUNNER.read_text(encoding="utf-8")
        for expected in (
            "arvectum.proxy.apl-win-014-candidate-result.v1",
            "arvectum.proxy.windows-app-control-enterprise-trust-pack.v2",
            "enforced_lifecycle_ready",
            "provisional_policy_promoted_unchanged",
            "code_integrity_3077_blocks",
            "FINAL V2 TRUST PROMOTION: PASS / SAME CIP",
            "FINAL READINESS BARRIER: PASS",
        ):
            self.assertIn(expected, text)

    def test_finalization_never_manages_or_weakens_app_control_or_defender(self):
        lowered = RUNNER.read_text(encoding="utf-8").lower()
        for forbidden in (
            "--update-policy",
            "--remove-policy",
            "set-ruleoption",
            "set-mppreference",
            "verifiedandreputablepolicystate",
            "disable-windowsoptionalfeature",
        ):
            self.assertNotIn(forbidden, lowered)
        self.assertIn("app_control_policy_changed_by_finalization = $false", lowered)


if __name__ == "__main__":
    unittest.main()
