from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = "ef9846e151a2e4e7046169e0787603969018cc97"
TREE = "98a09d821470a597715696e5ff3c7f376e5893a8"
PROVENANCE_SHA256 = "baf27272def4c03c7f44852ff11aa1c2fdb32710f92ac0e322f94b557158a87b"
SOURCE_REVIEW_ANCHOR = "8ad54018e6d6251c906a06d09fd464c8931c14b2"


class PostIp004ReconciliationContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_canonical_signoff_binds_post_ip004_candidate(self):
        text = self.read("docs/APL_IP_001_POST_REFACTOR_SIGNOFF.md")
        self.assertIn(CANDIDATE, text)
        self.assertIn(TREE, text)
        self.assertIn(PROVENANCE_SHA256, text)
        self.assertIn("L-1 | Complete third-party license/notice bundle for promoted artifacts | ENGINEERING-REMEDIATED", text)
        self.assertIn("L-2 | AppImage downstream compliance | EXCLUDED / HOLD", text)
        self.assertIn("NO CLEAN-IP TAG AUTHORIZED", text)

    def test_reconciliation_preserves_source_review_anchor_and_human_gates(self):
        text = self.read("docs/evidence/APL_IP_001_POST_IP_004_CANDIDATE_RECONCILIATION_2026-08-22.md")
        self.assertIn(SOURCE_REVIEW_ANCHOR, text)
        self.assertIn(CANDIDATE, text)
        self.assertIn("product-source records: **45**", text)
        self.assertIn("automated provenance-marker findings: **0**", text)
        self.assertIn("R-1", text)
        self.assertIn("R-2", text)
        self.assertIn("R-3", text)
        self.assertIn("AppImage remains **EXCLUDED / HOLD**", text)

    def test_rights_execution_draft_is_not_bound_only_to_old_anchor(self):
        text = self.read("docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_POST_REFACTOR_2026-08-22.md")
        self.assertIn(CANDIDATE, text)
        self.assertIn(TREE, text)
        self.assertIn(PROVENANCE_SHA256, text)
        self.assertIn(SOURCE_REVIEW_ANCHOR, text)
        self.assertIn("NOT SIGNED / NOT LEGAL APPROVAL", text)

    def test_roadmap_marks_web_reconciliation_done_but_not_legal_approval(self):
        text = self.read("docs/ROADMAP.md")
        # Markdown emphasis is presentation-only. Keep the governance contract
        # strict while allowing the roadmap to bold the environment marker.
        normalized = text.replace("**", "")
        self.assertIn("[Web] DONE — post-APL-IP-004 review reconciliation", normalized)
        self.assertIn("CONDITIONAL / POST-APL-IP-004 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING", normalized)
        self.assertIn(CANDIDATE, normalized)
        self.assertIn("[Web after explicit APPROVED] — create governed clean-IP baseline/tag", normalized)


if __name__ == "__main__":
    unittest.main()
