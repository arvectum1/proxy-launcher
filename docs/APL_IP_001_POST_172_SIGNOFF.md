# APL-IP-001 — post-#172 human/legal sign-off record

Status: **CONDITIONAL — POST-#172 ENGINEERING RECONCILED / AUTHORIZED HUMAN-LEGAL SIGN-OFF PENDING**

This is the canonical decision record for the current post-#172 APL-IP-001 candidate. The earlier `docs/APL_IP_001_POST_REFACTOR_SIGNOFF.md` remains historical evidence for the superseded post-APL-IP-004 candidate and must not be used to authorize a tag for the current installer state.

This record does not authorize a clean-IP tag until the authorized fields below are completed and the final decision is explicitly `APPROVED`.

## Candidate identity

- Canonical repository: `arvectum1/proxy-launcher`
- Product version: `0.2.3`
- Immutable APL-IP-003/source-review anchor commit: `8ad54018e6d6251c906a06d09fd464c8931c14b2`
- Immutable APL-IP-003/source-review anchor tree: `eac5db739e7bd3fda595b09b2ec869ad06a87ba3`
- Historical post-APL-IP-004 candidate: `ef9846e151a2e4e7046169e0787603969018cc97`
- PR #172 merge commit: `e2be3445e23eb6e8f0709f37fec0ecba50447dc7`
- Selected post-#172 candidate merge commit: `adc917e905acca1f8e97d560a3363b07adc279fb`
- Selected candidate tree: `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`
- Candidate-equivalent validated PR head: `56cfecf27c384591caae32bab53d343d9e6b9085`
- Candidate-equivalent PR test-merge: `73f85f86844f9c8c8a216691b8f9c42d92ca40f7`
- Source-provenance manifest SHA-256: `c73254146f58e0d292e80c0266e4f5a75e1f8310cf9232a16ea8b4367a7c89dd`
- Build SBOM SHA-256: `fccd5d2d94a4c2f8ebbc9fdde709db5b0fd1ae13f962f9046d706086a345ac4a`
- Post-refactor source-review evidence: `docs/evidence/APL_IP_001_POST_REFACTOR_REVIEW_2026-08-22.md`
- Historical post-APL-IP-004 evidence: `docs/evidence/APL_IP_001_POST_IP_004_CANDIDATE_RECONCILIATION_2026-08-22.md`
- Current post-#172 evidence: `docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md`

The validated PR head, PR test-merge and selected final merge have the identical tree `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`. Candidate-content evidence is therefore exact even though Git topology differs.

## Promoted artifact scope for final sign-off

The final clean-IP/commercial-distribution decision is scoped only to artifacts explicitly selected by the authorized reviewer below. Engineering readiness does not select or legally approve an artifact by itself.

- [ ] Windows portable
- [ ] Windows installer
- [ ] Linux Debian `.deb`
- [ ] macOS `.app` / DMG
- [ ] Linux AppImage — **must remain unchecked unless separately cleared for the pinned type-2 runtime and its statically linked third-party obligations**

Until final approval, no unchecked artifact may be represented as covered by this sign-off.

## Automated / engineering evidence

- [x] APL-IP-003 engineering refactor complete; Slices 1–23 merged.
- [x] Historical post-APL-IP-004 candidate/evidence preserved rather than rewritten.
- [x] PR #172 installer drift explicitly identified and bounded.
- [x] PR #172 final head and merge commit proven tree-equivalent at `68d151a9620190f9612f999109990ed820a82070`.
- [x] Exact post-#172 candidate selected.
- [x] Candidate-equivalent PR head, PR test-merge and final selected merge proven tree-identical at `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`.
- [x] Candidate provenance regenerated/rebound: 383 governed records, 45 product-source records, automated provenance-marker findings `0`.
- [x] Candidate build SBOM regenerated/rebound; exact seven locked build dependencies preserved.
- [x] No product-source file in the 45-file significant-source set changed across the post-APL-IP-004 -> post-#172 candidate boundary.
- [x] Bounded public-similarity/source review is carried forward only for that unchanged product-source set, not falsely described as rerun.
- [x] Windows portable candidate-equivalent workflow passes with the promoted-license gate.
- [x] Windows installer candidate-equivalent workflow passes after #172, including the dedicated #171 regression, fresh/upgrade/repair/uninstall E2E and Gate R6.
- [x] Exact post-#172 installer Setup and retained #171/Gate R6 evidence hashes are recorded in the reconciliation evidence.
- [x] Debian and macOS APL-IP-004 engineering controls remain unchanged; historical artifact bytes are not retroactively relabeled.
- [x] Historical Git provenance remains preserved through repository-owner migration.
- [x] AppImage remains explicitly excluded from promoted commercial scope pending separate L-2 clearance.

Automated evidence is supporting evidence only and does not establish legal authorship, company title or legal/commercial approval by itself.

## Human factual provenance

The prior human-fact record remains a historical factual source, but authorized confirmation is required that its facts remain accurate for selected candidate `adc917e905acca1f8e97d560a3363b07adc279fb`, including the post-#172 installer/release changes:

- [ ] Confirmed without correction
- [ ] Corrected/supplemented in evidence reference: ______________________________

Reviewer: ______________________________
Date: __________________________________

## Author -> ООО «Арвектум» chain of title

An executed rights basis must be verified rather than inferred from Git authorship.

- [ ] Executed written author -> ООО rights instrument verified for the selected post-#172 candidate
- [ ] Alternative valid existing rights basis verified for the selected post-#172 candidate

Stable non-secret evidence reference: ___________________________________________
Execution/effective date: ______________________________________________________
Scope/candidate covered: _______________________________________________________
Verified by: __________________________________________________________________

A draft or executed instrument bound only to `8ad54018...` or `ef9846e...` is not sufficient for R-1 closure unless a valid addendum/superseding basis expressly covers candidate `adc917e...` and tree `b36e7dc...`.

Candidate-binding draft addendum: `docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_POST_172_CANDIDATE_ADDENDUM_2026-08-25.md`.

If a signed agreement is used, the public repository should record a stable internal reference rather than publishing confidential originals/personal data.

## Rospatent registration status

The repository itself does not establish whether the program is registered. Authorized factual confirmation is required.

Choose exactly one:

- [ ] Program is not registered in Rospatent as of review date
- [ ] Program is registered; registration/certificate reference: __________________

If registered and the exclusive right is transferred, required transfer-registration reference/status:

________________________________________________________________________________

Verified by: ______________________________
Date: _____________________________________

## Corporate transaction / interested-person basis

Where the individual author is also a director, participant, controlling person or otherwise interested in the author -> ООО transaction, record the company's actual corporate-law basis rather than assuming an exception.

Choose/document as applicable:

- [ ] No interested-person corporate approval issue applies; basis: ______________
- [ ] Applicable statutory/charter exception verified; basis: ____________________
- [ ] Required corporate consent/approval obtained; reference: ___________________

Verified by: ______________________________
Date: _____________________________________

## Third-party distribution license reconciliation

Finding L-1 remains **ENGINEERING-REMEDIATED** for newly built promoted Windows portable, Windows installer, Debian `.deb`, and macOS `.app`/DMG lanes. Post-#172 candidate-equivalent Windows evidence revalidates the changed installer implementation; Debian/macOS implementation did not change across this boundary.

- [x] Complete third-party license/notice bundle generation and fail-closed verification implemented
- [x] Windows portable candidate-equivalent promoted-license gate passes
- [x] Windows installer candidate-equivalent #171 lifecycle/Gate R6 acceptance passes
- [x] Debian bundle implementation unchanged from accepted APL-IP-004 state
- [x] macOS bundle implementation unchanged from accepted APL-IP-004 state
- [x] No bundled/frozen third-party component is represented as Arvectum-authored source

Current compliance evidence: `docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md`  
Engineering control: `docs/APL_IP_004_THIRD_PARTY_LICENSE_BUNDLE_PROMOTED_ARTIFACT_COMPLIANCE.md`

### AppImage

Current decision: **EXCLUDED / HOLD**.

The pinned type-2 runtime includes statically linked third-party components, including the libfuse/LGPL path. AppImage may be added to promoted scope only after a separate downstream compliance review/bundle is recorded here:

AppImage clearance reference: __________________________________________________

## Open findings

| ID | Finding | Current status | Closure evidence |
|---|---|---|---|
| R-1 | Executed author -> ООО rights basis covering `adc917e...` | PENDING / HUMAN | __________________ |
| R-2 | Rospatent registration/transfer factual status | PENDING / HUMAN | __________________ |
| R-3 | Corporate/interested-transaction basis where applicable | PENDING / HUMAN | __________________ |
| L-1 | Complete third-party license/notice bundle for promoted non-AppImage artifacts | ENGINEERING-REMEDIATED | `docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md` |
| L-2 | AppImage downstream compliance | EXCLUDED / HOLD | separate clearance required |

## Final decision

Select exactly one only after all human/legal blockers for the selected promoted artifact scope are resolved:

- [ ] **APPROVED** — candidate/title/provenance and selected promoted-artifact distribution obligations reviewed; no unresolved blocker remains.
- [ ] **CONDITIONAL** — remediation or authorized factual/legal execution remains mandatory before tagging/release.
- [ ] **HOLD** — unresolved provenance/license/ownership issue blocks the selected scope.

Current machine-assisted review verdict before authorized signature: **CONDITIONAL**.

Reason for current `CONDITIONAL`: R-1, R-2, R-3, post-#172 human factual confirmation and authorized final decision remain pending. L-1 is not an engineering blocker for the four non-AppImage desktop lanes listed above.

Authorized reviewer / authority: _______________________________________________
Review date: __________________________________________________________________
Decision/signature reference: __________________________________________________

## Clean-IP tag authorization

A clean-IP tag may be created only when:

1. this record explicitly selects `APPROVED`;
2. the authorized reviewer/date/signature reference fields are completed;
3. every finding blocking the selected promoted-artifact scope is closed;
4. the tag points to the exact reviewed candidate/release commit covered by the evidence;
5. no product source, build dependency, packaging/compliance implementation or selected promoted-artifact contents have changed after the selected candidate without a new exact reconciliation.

Post-candidate governance/documentation/test-only records may describe the decision without silently moving the selected candidate. Any material product/package drift requires a new reconciliation.

Until the conditions above are met: **NO CLEAN-IP TAG AUTHORIZED**.