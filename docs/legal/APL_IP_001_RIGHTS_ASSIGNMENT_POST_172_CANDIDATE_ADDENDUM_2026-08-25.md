# APL-IP-001 — post-#172 candidate-binding addendum to rights instrument

> Status: **EXECUTION-READY CANDIDATE-BINDING ADDENDUM / NOT SIGNED / NOT LEGAL APPROVAL**
>
> This controlled draft supplements `docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_POST_REFACTOR_2026-08-22.md` only for exact technical identification of the later post-#172 candidate. It does not transfer any right unless validly executed together with, or incorporated into, an effective rights instrument. It is not a legal opinion.

## 1. Purpose

The earlier execution draft identifies the historical post-APL-IP-004 candidate `ef9846e151a2e4e7046169e0787603969018cc97`. Windows installer implementation subsequently changed in PR #172, so an R-1 rights basis used for final APL-IP-001 sign-off must expressly cover the later selected candidate rather than relying on the superseded candidate identity alone.

This addendum preserves the earlier source-review/human-fact chain while rebinding the technical object to the exact post-#172 candidate selected by:

`docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md`.

## 2. Exact supplemented object identity

For purposes of the underlying rights instrument, the reviewed/supplemented technical object is identified as follows:

- canonical repository: `arvectum1/proxy-launcher`;
- product: **Arvectum Proxy Launcher**;
- product version: `0.2.3`;
- immutable APL-IP-003/source-review anchor commit: `8ad54018e6d6251c906a06d09fd464c8931c14b2`;
- immutable source-review anchor tree: `eac5db739e7bd3fda595b09b2ec869ad06a87ba3`;
- historical post-APL-IP-004 candidate: `ef9846e151a2e4e7046169e0787603969018cc97`;
- installer-drift merge PR #172: `e2be3445e23eb6e8f0709f37fec0ecba50447dc7`;
- selected post-#172 candidate merge commit: `adc917e905acca1f8e97d560a3363b07adc279fb`;
- selected candidate tree: `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`;
- candidate-equivalent validated PR head: `56cfecf27c384591caae32bab53d343d9e6b9085`;
- candidate-equivalent PR test-merge: `73f85f86844f9c8c8a216691b8f9c42d92ca40f7`;
- exact candidate source-provenance manifest SHA-256: `c73254146f58e0d292e80c0266e4f5a75e1f8310cf9232a16ea8b4367a7c89dd`;
- exact candidate build SBOM SHA-256: `fccd5d2d94a4c2f8ebbc9fdde709db5b0fd1ae13f962f9046d706086a345ac4a`;
- post-refactor source-review record: `docs/evidence/APL_IP_001_POST_REFACTOR_REVIEW_2026-08-22.md`;
- post-#172 exact reconciliation record: `docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md`;
- canonical post-#172 sign-off record: `docs/APL_IP_001_POST_172_SIGNOFF.md`.

The validated PR head, test-merge and selected final merge have the identical tree `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`.

## 3. Scope relationship to the earlier draft

The parties intend the object description in section 2 of this addendum to supplement/supersede the earlier draft's candidate-identity fields for the post-#172 state while leaving its substantive exclusions and third-party-rights boundary intact.

In particular:

1. the 45-file significant product-source set covered by the prior source review did not change across the post-APL-IP-004 -> post-#172 candidate boundary;
2. PR #172 changed Windows installer/release implementation and related test/evidence material, which is included in the later candidate to the extent the applicable exclusive rights belong to the author/rightsholder;
3. third-party libraries, runtimes, build tools, license/copyright texts and other third-party objects remain excluded from any purported transfer except to the extent rights are actually owned by the transferring party;
4. APL-IP-004 third-party distribution compliance and AppImage L-2 remain separate from chain-of-title transfer;
5. this technical rebinding does not itself establish authorship, ownership, corporate approval or Rospatent status.

## 4. Execution record

Underlying rights instrument reference/date: ____________________________________

This addendum is:

- [ ] executed together with the underlying rights instrument;
- [ ] executed as a later amendment/addendum to an already effective instrument;
- [ ] not used because a separate superseding rights basis covering the selected candidate was executed.

Alternative/superseding evidence reference, if applicable: ______________________

Author / Rightsholder: _________________________________________________________
Signature: ____________________________________  Date: _________________________

For ООО «Арвектум»: ____________________________________________________________
Authority/basis: _______________________________________________________________
Signature: ____________________________________  Date: _________________________

Corporate approval/exception reference where applicable: _______________________

Rospatent transfer-registration reference where legally required: _______________

## 5. Evidence-handling rule

Do not publish confidential signed originals or unnecessary personal data in the public repository. The canonical sign-off may instead record a stable internal legal-archive reference, execution/effective date, covered candidate/tree and verifier.

Until an effective rights basis covering candidate `adc917e905acca1f8e97d560a3363b07adc279fb` is verified, APL-IP-001 Finding R-1 remains **PENDING / HUMAN**.