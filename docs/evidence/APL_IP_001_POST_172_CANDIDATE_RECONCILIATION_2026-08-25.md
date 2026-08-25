# APL-IP-001 — post-#172 exact candidate / evidence reconciliation

Status: **PASS FOR ENGINEERING EVIDENCE BINDING / CONDITIONAL OVERALL**  
Date: 2026-08-25

This record closes the hosted/Web reconciliation required after installer defect #171 and PR #172 changed the Windows installer implementation after the earlier post-APL-IP-004 candidate. It does not grant legal approval, does not execute an author -> ООО «Арвектум» rights transfer, and does not authorize a clean-IP tag.

## 1. Historical anchors preserved

The immutable APL-IP-003/post-refactor source-review anchor remains:

- commit: `8ad54018e6d6251c906a06d09fd464c8931c14b2`;
- tree: `eac5db739e7bd3fda595b09b2ec869ad06a87ba3`.

The previous post-APL-IP-004 candidate remains truthful historical evidence:

- merge commit: `ef9846e151a2e4e7046169e0787603969018cc97`;
- tree: `98a09d821470a597715696e5ff3c7f376e5893a8`;
- historical reconciliation: `docs/evidence/APL_IP_001_POST_IP_004_CANDIDATE_RECONCILIATION_2026-08-22.md`.

That historical record explicitly required a new exact reconciliation if product source, build dependencies, packaging/compliance implementation or promoted-artifact contents changed after the selected candidate. PR #172 crossed that boundary by changing Windows installer implementation and its acceptance path.

## 2. #172 drift trigger

PR #172 is preserved in migrated repository history by merge commit:

- merge commit: `e2be3445e23eb6e8f0709f37fec0ecba50447dc7`;
- final PR head: `a099794b1b2dd3fbfe2ce8ab1c33a1ca12aabbd2`;
- merge tree and final-head tree: **identical** `68d151a9620190f9612f999109990ed820a82070`.

The material #172 delta is bounded to Windows installer/release implementation and its tests/evidence:

- `installer/ArvectumProxyLauncher.iss` runs the maintenance preflight before install-phase ownership is committed;
- `installer/upgrade_helper.ps1` waits synchronously for previous-version rollback and fails closed on rollback failure;
- `.github/workflows/windows-installer.yml` executes the dedicated #171 regression harness and retains its evidence;
- `qa/windows_installer_171_e2e.ps1` proves active-portable -> installer rollback and partial-install prevention;
- related tests were updated to protect those contracts.

No product-source file from the 45-file significant APL-IP-001 source-review set changed in this #172 delta, and `requirements-build.lock.txt` did not change.

## 3. Selected post-#172 candidate

A later protected-main acceptance PR provides a stronger exact validation point than the historical #172 PR itself because it contains the complete post-#172 implementation and re-exercised all relevant candidate workflows after repository-owner migration.

Selected candidate:

- canonical repository: `arvectum1/proxy-launcher`;
- product version: `0.2.3`;
- selected candidate merge commit: `adc917e905acca1f8e97d560a3363b07adc279fb`;
- selected candidate tree: `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`;
- candidate-equivalent validated PR head: `56cfecf27c384591caae32bab53d343d9e6b9085`;
- candidate-equivalent PR test-merge: `73f85f86844f9c8c8a216691b8f9c42d92ca40f7`;
- validated PR-head tree, test-merge tree and selected final-merge tree: **identical** `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`.

Therefore the exact file tree accepted by the relevant PR workflows is byte-for-byte the same tree selected as the canonical post-#172 APL-IP-001 engineering candidate. Git merge topology differs; candidate contents do not.

## 4. Delta classification and significant-source carry-forward

From historical candidate `ef9846e...` through PR #172 and then to selected candidate `adc917e...`:

- the 45-file significant product-source set reviewed at the APL-IP-003 anchor remains unchanged;
- the build dependency lock remains unchanged;
- #172 changes Windows installer/release implementation and tests, which is why this reconciliation is mandatory;
- subsequent owner-migration work before `adc917e...` changes repository/mirror/governance documentation and governance tests, not product source or installer implementation;
- Linux Debian packaging, macOS packaging and the APL-IP-004 third-party-license bundle implementation are unchanged after their prior accepted state.

Consequences:

1. the bounded public-similarity/source review remains valid only for the unchanged 45-file product-source set; it is carried forward rather than falsely described as rerun;
2. post-#172 provenance and SBOM are freshly rebound to the selected candidate-equivalent tree;
3. Windows portable/installer acceptance is freshly rebound to that same candidate-equivalent tree;
4. prior Debian/macOS APL-IP-004 evidence remains valid as engineering-control evidence for unchanged implementation, but historical artifact bytes are not relabeled as newly built candidate artifacts;
5. AppImage remains excluded under L-2.

## 5. Exact source-provenance evidence

Candidate-equivalent APL-IP-001 provenance workflow:

- workflow run: `32770656169` — **SUCCESS**;
- validated PR head: `56cfecf27c384591caae32bab53d343d9e6b9085`;
- candidate-equivalent tree: `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`;
- artifact ID: `9536056523`;
- artifact name: `apl-ip-001-source-provenance`;
- artifact ZIP digest: `sha256:16998568701f0f8c5d2199ce86cec0d9251cd2fb6a96d6999a7792ecd70e203e`;
- `source-manifest.json` SHA-256: `c73254146f58e0d292e80c0266e4f5a75e1f8310cf9232a16ea8b4367a7c89dd`;
- schema version: `2`;
- governed records: **383**;
- product-source records: **45**;
- automated provenance-marker findings: **0**;
- `human_review_required=true`;
- `legal_signoff_required=true`.

Manifest categories:

- documentation: 137;
- tests: 98;
- build/release: 63;
- product source: 45;
- CI: 29;
- governance/config: 11.

The record-count increase relative to the historical candidate is explained by governance/test/release evidence growth and is not a product-source expansion.

## 6. Exact build-SBOM evidence

Candidate-equivalent SBOM workflow:

- workflow run: `32770656167` — **SUCCESS**;
- PR test-merge SHA used by the PR-event artifact name: `73f85f86844f9c8c8a216691b8f9c42d92ca40f7`;
- PR test-merge tree: `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`;
- artifact ID: `9536062800`;
- artifact ZIP digest: `sha256:927730b268d400bfed7e589407abd8aed8c9d281285516e8235ede9fa8ed7a23`;
- CycloneDX document SHA-256: `fccd5d2d94a4c2f8ebbc9fdde709db5b0fd1ae13f962f9046d706086a345ac4a`;
- CycloneDX spec: `1.6`.

The component set remains exactly the seven entries pinned by `requirements-build.lock.txt`:

- `altgraph 0.17.5`;
- `packaging 26.3`;
- `pefile 2024.8.26`;
- `pyinstaller 6.22.0`;
- `pyinstaller-hooks-contrib 2026.6`;
- `pywin32-ctypes 0.2.3`;
- `setuptools 84.0.0`.

The CycloneDX document SHA remaining identical to the earlier reconciliation is expected because the frozen build lock did not change. The fresh successful workflow binds that same dependency set to the selected candidate-equivalent tree.

## 7. Exact post-#172 Windows evidence

### Windows portable

Candidate-equivalent Windows P0 workflow:

- workflow run: `32770656242` — **SUCCESS**;
- artifact ID: `9536095997`;
- artifact name: `Arvectum-Proxy-Launcher-0.2.3-windows-x64-portable`;
- artifact ZIP digest: `sha256:9bf1474a467c00b84c2ffb17360c20d48d67416bfdb42c98d38cff209a5f9b28`.

The run includes the APL-IP-004 promoted portable license gate on the exact candidate-equivalent tree.

### Windows installer / #171 regression / Gate R6

Candidate-equivalent installer workflow:

- workflow run: `32770656217` — **SUCCESS**;
- job ID: `97570021627` — **SUCCESS**;
- installer artifact ID: `9536152180`;
- artifact name: `Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe`;
- artifact ZIP digest: `sha256:95694f4d66ce00ef6ea88b58dc42aef150d471de8ae0fadf158ab5a43667a469`;
- inner Setup SHA-256: `bada7a965913ccabccb13900a4aa838b5152fdc197f7868afcb53207f9ecdc54`.

The workflow completed successfully through:

- controlled Inno Setup `6.7.1` acquisition;
- Windows productization syntax/sovereignty checks;
- portable baseline build and final EXE metadata verification;
- synthetic predecessor lifecycle fixture;
- current canonical installer compile and Setup metadata verification;
- dedicated #171 portable-transition/preflight regression;
- fresh / upgrade / repair / uninstall E2E;
- Windows RC packaging and Gate R6 acceptance.

Exact retained acceptance payloads inside the artifact:

- `windows-installer-171-e2e.json` SHA-256 `7d6ded41a4e15af63f634b6f4497a0409892711f80d26eafe4625b5c403a1f6d` — result **PASS**;
  - `active_portable_to_installer`: **PASS**;
  - `preflight_partial_install_prevention`: **PASS**;
  - configuration preservation: `true`;
- `windows-rc-e2e.json` SHA-256 `793b3a7fbbac69c51d2f18528cc76d458fdb106037777fc548a86f65e0e7515e` — fresh install, fresh uninstall, upgrade, repair and uninstall all **PASS**; predecessor version `0.2.2`; configuration and foreign startup preservation `true`;
- `windows-rc-acceptance.json` SHA-256 `17caf32609135361bd44b3e0030e88579d099562c1a34a1c1e514b4c4f6694dd` — Gate R6 result **PASS**;
- `windows-rc-SHA256SUMS.txt` SHA-256 `ad56990a6714e5ef5471747f59284d97238ad05e72a2d0fb629f9013649edbb7`.

This is the required fresh evidence binding for the installer implementation changed by #172. The earlier post-APL-IP-004 Windows installer artifact is retained only as historical evidence.

## 8. Debian / macOS / AppImage disposition

### Debian `.deb`

No Debian package implementation, build lock or APL-IP-004 bundle implementation changed between the historical post-APL-IP-004 candidate and the selected post-#172 candidate. The prior successful Ubuntu 22.04/24.04 APL-IP-004 evidence therefore remains valid as engineering-control evidence. A future promoted release artifact must still be bound to its own exact release build/evidence; historical binary bytes are not relabeled.

### macOS `.app` / DMG

No macOS packaging implementation, build lock or APL-IP-004 bundle implementation changed across the same boundary. The prior Apple Silicon/Intel APL-IP-004 evidence remains valid as engineering-control evidence under the same non-retroactive rule.

### AppImage

AppImage remains **EXCLUDED / HOLD**. Nothing in #172 or this reconciliation closes the pinned type-2 runtime/transitive-license Finding L-2.

## 9. Current-main drift after the selected candidate

At reconciliation time the canonical `main` head before this evidence change was `93ff56b358ce9dcaa09e826f7e82f4e1f4412982`.

Comparison `adc917e... -> 93ff56b...` is linear and changes only:

- `docs/evidence/GITHUB_MAIN_PROTECTION_ACCEPTANCE_2026-08-24.md`.

That post-candidate delta is governance evidence only. It does not change product source, build dependencies, installer/package/compliance implementation or promoted-artifact contents and therefore does not invalidate the selected engineering candidate under the existing APL-IP-001 rebinding rule.

This reconciliation document, its contract tests and roadmap/backlog updates are likewise post-candidate governance/test material. They document the selected candidate; they do not silently move the candidate to a later tree.

## 10. Findings after post-#172 reconciliation

| ID | Finding | Status |
|---|---|---|
| R-1 | Executed author -> ООО «Арвектум» rights basis covering the selected post-#172 candidate | **PENDING / HUMAN** |
| R-2 | Actual Rospatent registration/transfer factual status | **PENDING / HUMAN** |
| R-3 | Corporate/interested-transaction basis where applicable | **PENDING / HUMAN** |
| L-1 | Complete third-party license/notice bundle for promoted non-AppImage desktop lanes | **ENGINEERING-REMEDIATED**; no legal approval implied |
| L-2 | AppImage downstream/type-2-runtime compliance | **EXCLUDED / HOLD** |

Authorized human factual-provenance carry-forward is also still required for candidate `adc917e905acca1f8e97d560a3363b07adc279fb`.

## 11. Decision boundary

Repository/Web result: **PASS FOR POST-#172 ENGINEERING EVIDENCE BINDING / CONDITIONAL OVERALL**.

The hosted engineering reconciliation is complete. Remaining APL-IP-001 blockers are the authorized human/legal layer: R-1, R-2, R-3, factual-provenance confirmation and explicit final sign-off.

A clean-IP tag remains prohibited until the canonical post-#172 sign-off explicitly records `APPROVED`. If product source, build dependencies, packaging/compliance implementation or selected promoted-artifact contents change after candidate `adc917e...`, a new exact candidate/evidence reconciliation is required before tagging.