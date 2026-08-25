from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_REVIEW_ANCHOR = "8ad54018e6d6251c906a06d09fd464c8931c14b2"
HISTORICAL_CANDIDATE = "ef9846e151a2e4e7046169e0787603969018cc97"
PR_172_MERGE = "e2be3445e23eb6e8f0709f37fec0ecba50447dc7"
PR_172_HEAD = "a099794b1b2dd3fbfe2ce8ab1c33a1ca12aabbd2"
CANDIDATE = "adc917e905acca1f8e97d560a3363b07adc279fb"
TREE = "b36e7dc17830622c510fc7c8b643cfd36bb7fe3f"
VALIDATED_HEAD = "56cfecf27c384591caae32bab53d343d9e6b9085"
TEST_MERGE = "73f85f86844f9c8c8a216691b8f9c42d92ca40f7"
PROVENANCE_SHA256 = "c73254146f58e0d292e80c0266e4f5a75e1f8310cf9232a16ea8b4367a7c89dd"
SBOM_SHA256 = "fccd5d2d94a4c2f8ebbc9fdde709db5b0fd1ae13f962f9046d706086a345ac4a"
SETUP_SHA256 = "bada7a965913ccabccb13900a4aa838b5152fdc197f7868afcb53207f9ecdc54"
EVIDENCE = "docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md"
SIGNOFF = "docs/APL_IP_001_POST_172_SIGNOFF.md"
ADDENDUM = "docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_POST_172_CANDIDATE_ADDENDUM_2026-08-25.md"


class Post172ReconciliationContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_exact_candidate_and_historical_chain_are_preserved(self):
        text = self.read(EVIDENCE)
        for value in (
            SOURCE_REVIEW_ANCHOR,
            HISTORICAL_CANDIDATE,
            PR_172_MERGE,
            PR_172_HEAD,
            CANDIDATE,
            TREE,
            VALIDATED_HEAD,
            TEST_MERGE,
        ):
            self.assertIn(value, text)
        self.assertIn("product-source records: **45**", text)
        self.assertIn("automated provenance-marker findings: **0**", text)
        self.assertIn("PASS FOR POST-#172 ENGINEERING EVIDENCE BINDING / CONDITIONAL OVERALL", text)

    def test_candidate_bound_provenance_sbom_and_windows_acceptance_are_recorded(self):
        text = self.read(EVIDENCE)
        self.assertIn("32770656169", text)
        self.assertIn("9536056523", text)
        self.assertIn(PROVENANCE_SHA256, text)
        self.assertIn("32770656167", text)
        self.assertIn("9536062800", text)
        self.assertIn(SBOM_SHA256, text)
        self.assertIn("32770656242", text)
        self.assertIn("9536095997", text)
        self.assertIn("32770656217", text)
        self.assertIn("9536152180", text)
        self.assertIn(SETUP_SHA256, text)
        self.assertIn("active_portable_to_installer`: **PASS**", text)
        self.assertIn("preflight_partial_install_prevention`: **PASS**", text)
        self.assertIn("Gate R6 result **PASS**", text)

    def test_canonical_post_172_signoff_keeps_human_legal_gates_fail_closed(self):
        text = self.read(SIGNOFF)
        for value in (CANDIDATE, TREE, VALIDATED_HEAD, TEST_MERGE, PROVENANCE_SHA256, SBOM_SHA256, EVIDENCE):
            self.assertIn(value, text)
        self.assertIn("R-1", text)
        self.assertIn("R-2", text)
        self.assertIn("R-3", text)
        self.assertIn("ENGINEERING-REMEDIATED", text)
        self.assertIn("EXCLUDED / HOLD", text)
        self.assertIn("NO CLEAN-IP TAG AUTHORIZED", text)
        self.assertIn("Current machine-assisted review verdict before authorized signature: **CONDITIONAL**", text)

    def test_rights_addendum_binds_later_candidate_without_claiming_execution(self):
        text = self.read(ADDENDUM)
        for value in (SOURCE_REVIEW_ANCHOR, HISTORICAL_CANDIDATE, PR_172_MERGE, CANDIDATE, TREE, PROVENANCE_SHA256, SBOM_SHA256):
            self.assertIn(value, text)
        self.assertIn("NOT SIGNED / NOT LEGAL APPROVAL", text)
        self.assertIn("R-1 remains **PENDING / HUMAN**", text)

    def test_appimage_hold_and_material_drift_rule_remain_explicit(self):
        evidence = self.read(EVIDENCE)
        signoff = self.read(SIGNOFF)
        self.assertIn("AppImage remains **EXCLUDED / HOLD**", evidence)
        self.assertIn("a new exact candidate/evidence reconciliation is required before tagging", evidence)
        self.assertIn("product source, build dependency, packaging/compliance implementation", signoff)


if __name__ == "__main__":
    unittest.main()
