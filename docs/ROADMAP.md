# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-08-24
Canonical GitHub repository: `arvectum1/proxy-launcher`
Canonical branch: `main`
Current product line: `0.2.3`

Status legend:

- **DONE** — implementation and required acceptance are complete.
- **CURRENT** — active next item for that track.
- **READY** — executable now once an operator chooses the track.
- **PARTIAL** — meaningful acceptance exists but the named final gate is not closed.
- **HUMAN/LEGAL PENDING** — requires an authorized factual/legal action.
- **ADMIN PENDING** — requires a repository/platform administrator setting that current automation cannot mutate.
- **STOP-GATE** — do not continue production implementation until a deliberate decision is made.
- **DEFERRED** — useful hardening/later work outside the current critical path.

## 0. Repository authority, GitHub protection and GitVerse mirror

### GitHub authority

- **DONE** — canonical repository is `arvectum1/proxy-launcher`; default/canonical branch is `main`.
- **DONE** — pre-migration project history is preserved; no source-history rewrite was introduced by the owner migration.

### GitHub -> GitVerse mirror

- **DONE / VERIFIED 2026-08-24** — post-owner-migration mirror contract was repaired and verified.
- The previous GitVerse presentation was stale: `master` was still the default branch at historical GitHub commit `0a4ff4e4087756c81b4ad4101a0c851aa663ea3f`.
- `mirror-to-gitverse.yml` now:
  1. seeds/updates GitVerse `main` first;
  2. changes GitVerse `default_branch` to `main` through the official GitVerse API;
  3. mirrors/prunes normal branches and tags while excluding GitHub-only `refs/pull/*`;
  4. fail-closes if GitVerse `main` differs from canonical GitHub `main` or if GitVerse default branch is not `main`;
  5. publishes commit status `gitverse-mirror=success` on the exact verified canonical GitHub `main` SHA.
- Verified mirror run: GitHub Actions run `32767806496`; all mirror steps PASS, including canonical branch reconciliation and status publication.
- Verified canonical SHA at that recovery point: `ad36d928777af3a583de32e3917bf6f6088e6144` with `gitverse-mirror=success`.

### GitHub `main` protection after migration

- **ADMIN PENDING / REAL REGRESSION CONFIRMED**.
- GitHub branch API currently reports `main.protected=false`, protection disabled, and no required status checks.
- This confirms the pre-migration branch-protection contract did not survive the repository/owner migration.
- Desired restored contract remains:
  - PR required; approvals required = 0;
  - required status check `build`;
  - strict/up-to-date required checks;
  - conversation resolution required;
  - force pushes disabled;
  - branch deletion disabled;
  - administrator/bypass policy must not silently defeat the gate during normal operation.
- Exact recovery/verification runbook: `docs/GITHUB_MAIN_PROTECTION_RECOVERY.md`.
- The currently available GitHub connector can verify branch-protection state but exposes no branch-protection/ruleset administration mutation; no separate GitHub-admin plugin or repository admin-token workflow is available. Therefore the Settings save is a repository-owner/admin boundary and must not be mislabeled as automated PASS.
- **After admin save:** re-read GitHub branch API and perform a negative merge test while `build` is queued. Only then mark protection **DONE**.

## 1. Proven Windows/core/release baseline

- **DONE** — customer-proven Windows `0.2.3` system-proxy baseline.
- **DONE** — APL-CORE-001..007 cross-platform backend contract/capability foundation.
- **DONE** — Gates R1-R7.
- **DONE** — P0.1 governed Windows CPython `3.12.10` x64 + exact hash-locked wheelhouse archive and retained offline copy.
- **DONE** — exact Inno Setup `6.7.1` controlled acquisition and canonical installer build.
- **DONE** — Russian-first production provenance/signing contour with CryptoPro/Rutoken detached evidence and fail-closed publication controls.
- **TRUST BOUNDARY** — detached Russian signature proves governed release provenance/integrity; embedded Microsoft Authenticode/SmartScreen/App Control trust is not claimed.
- **DEFERRED** — P0.2 independent endpoint-denied clean-machine rebuild; resilience hardening only, not a release blocker.

## 2. Physical Windows stand — ARVECTUM-DEMO

Current host: dedicated x86-64 laptop, Windows 11 Enterprise 25H2, 512 GB SSD. Intended permanent state: Windows 11 + Astra Linux SE 1.8 x86-64 dual boot.

### Portable and installer acceptance

- **DONE** — portable version works on the physical Windows 11 host.
- **DONE** — physical host exposed installer defect #171 (portable-active -> installer split-brain/partial install).
- **DONE** — PR #172 / commit `e2be3445e23eb6e8f0709f37fec0ecba50447dc7` added deterministic rollback wait, fail-closed pre-install maintenance preflight and regression coverage.
- **DONE** — physical follow-up passed: fixed install over active portable, uninstall, fresh reinstall and persistent proxy configuration preservation.

### APL-WIN-014 — App Control for Business

- **CURRENT / REAL HOST AVAILABLE**.
- Canonical runbook: `docs/APL_WIN_014_LOCAL_GATE.md`.
- Windows 11 Enterprise is eligible.
- Final PASS requires App Control for Business actually enforced plus both:
  - exact current `0.2.3` enforced acceptance;
  - a real cross-version upgrade from a distinct sealed previous build.
- Same-version repair is not upgrade evidence.
- Historical repository contains genuine `0.2.2` release commits (`18eeccd...`, `0ea08d9...`), but the exact trustworthy previous installer and governed hashes must be recovered/verified rather than manufactured.
- **[Web] READY in parallel** — recover/reconcile the retained sealed 0.2.2 package/evidence.
- **[Win] CURRENT** — prepare/deploy the lab App Control trust paths and run the final gate when baseline/current trust prerequisites are ready.

### APL-REL-014 — exact signed-set lifecycle

- **PARTIAL / READY**.
- Real installer transition/uninstall/fresh-install behavior is proven after #172.
- Exact governed signed-set lifecycle/upgrade/recovery evidence remains pending until the canonical local record identifies the exact signed artifacts and required recovery states.
- Complete/export/hash-verify this evidence before Linux repartitioning.

## 3. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering, diagnostics, `.deb`, AppImage engineering and Ubuntu CI acceptance.
- **DONE** — APL-IP-002-LNX conditional sovereignty audit.
- **READY / HOST AVAILABLE AFTER WINDOWS-ONLY GATES** — same physical laptop becomes the permanent Astra stand without deleting Windows.
- **[Win/Linux] NEXT TRANSITION** — shrink Windows `C:` from Windows, install Astra Linux SE 1.8 x86-64 into unallocated space using manual GPT/UEFI partitioning, preserve existing EFI/Windows/MSR/Recovery partitions and verify both OSes boot.
- **[Linux] APL-LNX-010 READY** — real Astra GUI/runtime/NetworkManager/PolicyKit/package/autostart/recovery/update/remove/diagnostics acceptance.
- **[Linux] Gate R8 PENDING** — closes only from real Astra-host PASS evidence.
- Preferred promoted Linux/Astra lane remains `.deb`.
- **HOLD** — AppImage is excluded from promoted commercial scope until L-2 downstream/type-2-runtime obligations are separately cleared.

## 4. macOS

- **DONE** — APL-MAC-001..008.
- **DONE** — APL-IP-002-MAC.
- **DONE** — Gate R9 real macOS acceptance.
- **DEFERRED** — Apple production identity signing/notarization and controlled macOS endpoint-denied build-input hardening under the Russia-first priority model.

## 5. IP / sovereignty / legal

- **DONE** — APL-IP-002-WIN/LNX/MAC/FINAL.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1-23.
- **DONE** — APL-IP-004 third-party full-license bundle engineering for newly built promoted Windows portable/installer, Debian `.deb` and macOS `.app`/DMG lanes.
- **[Web] DONE — post-APL-IP-004 review reconciliation** — candidate `ef9846e151a2e4e7046169e0787603969018cc97` was correctly reconciled against the APL-IP-004 state; this remains truthful historical evidence and did not grant legal approval.
- **CURRENT DRIFT** — installer implementation then changed in #171/#172, so `ef9846e...` must not be treated as the final clean-IP candidate for the current installer state.
- **[Web] CURRENT** — post-#172 exact candidate/evidence reconciliation: select a current candidate, prove carry-forward of significant-source review where valid, regenerate/rebind provenance/SBOM/package evidence and explicitly record #172 installer changes.
- **[Human] PARALLEL**:
  - R-1 author -> ООО «Арвектум» rights basis;
  - R-2 actual Rospatent registration/transfer status;
  - R-3 applicable corporate/interested-transaction basis/approval/exception;
  - factual provenance confirmation for the final selected candidate and explicit authorized decision.
- **[Web after explicit APPROVED]** — create governed clean-IP baseline/tag for the exact approved candidate only.
- **OPTIONAL / HOLD** — AppImage L-2 clearance only if AppImage later enters promoted commercial scope.

## 6. Per-application routing

- **DONE** — APL-ROUTE-001 platform-neutral rule model.
- **DONE** — APL-ROUTE-002 feasibility matrix.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 control-plane prototype.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.

### Windows production enforcement STOP-GATE

Choose deliberately before native production enforcement:

1. Microsoft Hardware Dev Center + accepted EV identity for optional WFP/kernel SKU;
2. separately reviewed already-signed third-party component;
3. supported user-mode architecture with equivalent semantics;
4. defer Windows per-app routing and keep the system-proxy/domain/IP line production-ready.

- **[Web/Decision] READY** — decision work can proceed now in parallel.
- Test-signing/developer modes are not accepted as a production workaround.

Future branches after the decision: Linux cgroup/socket+nftables/policy-routing prototype on Astra; macOS NetworkExtension entitlement/distribution proof; mobile Android/iOS capability architecture later.

## 7. Deferred sovereignty/recovery hardening

- **DEFERRED** — Windows P0.2 clean-machine endpoint-denied rebuild in a future naturally clean environment.
- **DEFERRED / MEDIUM** — controlled Linux build-input mirror + endpoint-denied rebuild.
- **DEFERRED / MEDIUM** — controlled macOS build-input mirror + endpoint-denied rebuild.
- **DEFERRED** — international Microsoft/GlobalSign and Apple signing/notarization paths; not blockers for the Russian-first baseline.

## 8. What can be done now

### [Web] ChatGPT/GitHub

1. **CURRENT — APL-IP-001 post-#172 exact candidate/evidence reconciliation.**
2. **READY — APL-WIN-014 previous sealed 0.2.2 baseline artifact/evidence recovery.**
3. **DONE — GitHub -> GitVerse mirror recovery/verification.**
4. **AFTER ADMIN ACTION — verify restored GitHub `main` protection by API + negative queued-`build` merge test.**
5. **READY / optional — APL-ROUTE-003 product/architecture decision work.**

### [Human/Admin]

1. **CURRENT — restore GitHub `main` branch protection/rules using `docs/GITHUB_MAIN_PROTECTION_RECOVERY.md`.**
2. **PARALLEL — R-1/R-2/R-3 and final IP/legal factual sign-off preparation.**

### [Win] ARVECTUM-DEMO

1. **CURRENT — APL-WIN-014** once distinct sealed baseline/current trust prerequisites are ready.
2. **READY — finish APL-REL-014 exact signed-set lifecycle/recovery evidence.**
3. Export/hash-verify all Windows evidence before repartitioning.

### [Linux] ARVECTUM-DEMO

After Windows-only gates: create persistent dual boot, install Astra SE 1.8, execute APL-LNX-010 and close Gate R8.

### [Mac]

No release-critical local acceptance task remains.

## 9. Recommended parallel execution

Run four streams without blocking one another:

- **A — [Web]** post-#172 IP candidate/evidence reconciliation;
- **B — [Web + Win]** recover sealed 0.2.2 baseline and execute APL-WIN-014;
- **C — [Human]** R-1/R-2/R-3 legal/IP facts;
- **D — [Human/Admin -> Web verify]** restore GitHub `main` protection, then verify it through API and a negative merge test.

After Windows App Control / exact signed-set evidence are closed, convert ARVECTUM-DEMO to persistent Windows+Astra dual boot and execute **APL-LNX-010 -> Gate R8**.

## Completion discipline

Real-host, human/legal and repository-admin gates remain pending until their named evidence exists. Do not substitute CI, mocks, screenshots or same-version repair for required physical/cross-version acceptance. Historical evidence remains immutable; later installer/compliance changes require explicit candidate/evidence rebinding. GitHub `main` is the source authority; GitVerse is a verified mirror, not an independent competing source of truth.
