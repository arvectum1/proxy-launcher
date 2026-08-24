# Arvectum Proxy Launcher — canonical roadmap

Updated: 2026-08-24
Canonical GitHub repository: `arvectum1/proxy-launcher`
Canonical branch: `main`
Current repository head before this roadmap update: `239244653b01a6d16f586ebf1975d47c59b424c7`
Current product line: `0.2.3`

Status legend:

- **DONE** — implementation and required acceptance are complete.
- **CURRENT** — next active execution item for that track.
- **READY** — can be executed now when an operator chooses that track.
- **PARTIAL** — meaningful acceptance exists but the named final gate is not yet closed.
- **HUMAN/LEGAL PENDING** — cannot be truthfully completed by automation.
- **STOP-GATE** — do not continue production implementation until a deliberate decision is made.
- **DEFERRED** — useful hardening/later product work, not on the current critical path.

## 0. Repository authority / mirroring

- **DONE** — current GitHub authority is `arvectum1/proxy-launcher`; default branch is `main`.
- **DONE** — repository history contains the prior `arvectum/proxy-launcher` engineering line; product history was not rewritten.
- **IN PROGRESS / VERIFY** — GitHub -> GitVerse mirror workflow was repaired on 2026-08-24 by commits `ef69edd4e44622fb95798b2087d8ea55270c01e9` and `239244653b01a6d16f586ebf1975d47c59b424c7`.
- **[Web] CURRENT** — verify that GitVerse receives the current GitHub `main` and relevant release tags/branches, and reconcile GitVerse default-branch presentation with GitHub canonical `main` if needed. Do not treat GitVerse `master` as source of truth merely because it is displayed as default.

## 1. Proven Windows/core/release baseline

- **DONE** — customer-proven Windows `0.2.3` system-proxy baseline.
- **DONE** — APL-CORE-001..007 cross-platform backend contract/capability foundation.
- **DONE** — Gates R1-R7.
- **DONE** — P0.1 governed Windows CPython `3.12.10` x64 + exact hash-locked wheelhouse archive and retained offline copy.
- **DONE** — exact Inno Setup `6.7.1` controlled acquisition and canonical installer build.
- **DONE** — Russian-first production provenance/signing contour with CryptoPro/Rutoken detached evidence and fail-closed publication controls.
- **TRUST BOUNDARY** — Russian detached signature proves governed release provenance/integrity; embedded Microsoft Authenticode/SmartScreen/App Control trust is not claimed.
- **DEFERRED** — P0.2 independent endpoint-denied clean-machine rebuild. It is resilience/supply-chain hardening, not a release blocker.

## 2. Physical Windows stand — ARVECTUM-DEMO

Current host: dedicated x86-64 laptop, Windows 11 Enterprise 25H2, 512 GB SSD. Intended final state: persistent Windows 11 + Astra Linux SE 1.8 x86-64 dual boot.

### Portable acceptance

- **DONE** — portable version works on the real Windows 11 host.

### Installer acceptance / defect #171

- **DONE** — real host exposed the portable-active -> installer split-brain/partial-install defect.
- **DONE** — PR/merge `#172` / commit `e2be3445e23eb6e8f0709f37fec0ecba50447dc7` added deterministic rollback wait, pre-install fail-closed maintenance preflight and regression coverage.
- **DONE** — physical follow-up passed: install over the problematic portable-active state, uninstall, fresh reinstall and retained proxy configuration all passed.
- **CONSTRAINT** — this physical installer PASS does not by itself close the separate App Control gate or necessarily prove the exact final signed-set cross-version lifecycle under App Control.

### APL-WIN-014 — App Control for Business

- **CURRENT / REAL HOST AVAILABLE**.
- Repository harness is ready: `docs/APL_WIN_014_LOCAL_GATE.md` and `tools/windows_app_control_*`.
- Host edition is eligible: Windows 11 Enterprise.
- Final PASS requires App Control for Business actually enforced and evidence from both the exact current 0.2.3 enforced gate and a **real cross-version upgrade from a distinct sealed previous build**.
- Historical repository contains 0.2.2 release commits (`18eeccd...`, `0ea08d9...`), but the operator must recover a trustworthy exact previous installer + governed hashes; do not manufacture a fake baseline and do not substitute same-version repair.
- **[Web] READY in parallel** — recover/reconcile the exact sealed previous Windows package/evidence required by the local gate, if retained artifacts are available.
- **[Win] CURRENT** — prepare/deploy the lab App Control policy/trust pack and execute the final local gate on ARVECTUM-DEMO once both current and baseline trust paths are available.

### APL-REL-014 — exact signed-set lifecycle

- **PARTIAL / READY**.
- Installer transition/uninstall/fresh-install behavior is proven on real hardware after #172.
- Keep the exact governed signed-release-set lifecycle/upgrade/recovery evidence visibly pending until the canonical local acceptance record proves the named signed artifacts and required recovery states.
- This may be completed on ARVECTUM-DEMO before Linux repartitioning; export/hash-verify evidence outside the laptop first.

## 3. Linux / Astra Linux

- **DONE** — APL-LNX-001..009 engineering, diagnostics, `.deb`, AppImage engineering and Ubuntu CI acceptance.
- **DONE** — APL-IP-002-LNX conditional sovereignty audit.
- **READY / HOST AVAILABLE** — the same x86-64 laptop is allocated for Astra after the remaining Windows-only gates/evidence are complete.
- **[Win/Linux] NEXT PHYSICAL TRANSITION** — shrink Windows `C:` and install Astra Linux Special Edition 1.8 x86-64 beside Windows using manual GPT/UEFI partitioning; preserve the existing EFI System Partition, Windows/MSR/Recovery partitions and Windows Boot Manager.
- **[Linux] APL-LNX-010 READY** — real Astra GUI/runtime/NetworkManager/PolicyKit/package/autostart/recovery/update/remove/diagnostics acceptance.
- **[Linux] Gate R8 PENDING** — closes only from real Astra-host PASS evidence.
- Preferred promoted Astra/Linux package remains `.deb`.
- **HOLD** — AppImage is not in promoted commercial scope until L-2 downstream/type-2-runtime license obligations are separately cleared.

## 4. macOS

- **DONE** — APL-MAC-001..008.
- **DONE** — APL-IP-002-MAC.
- **DONE** — Gate R9 real macOS acceptance.
- **DEFERRED** — Apple production identity signing/notarization and controlled macOS endpoint-denied rebuild/mirror hardening under the Russia-first priority model.

## 5. IP / sovereignty / legal

- **DONE** — APL-IP-002-WIN/LNX/MAC/FINAL.
- **DONE** — APL-IP-003 canonical source refactor, Slices 1-23.
- **DONE** — APL-IP-004 full third-party license bundle engineering for newly built promoted Windows portable/installer, Debian `.deb` and macOS `.app`/DMG lanes.
- **DONE** — post-APL-IP-004 candidate/evidence reconciliation performed for candidate `ef9846e151a2e4e7046169e0787603969018cc97`.
- **IMPORTANT NEW DRIFT** — installer implementation changed afterwards in fix #171/#172. Therefore `ef9846e...` must not be treated as the final clean-IP candidate for the current installer state.
- **[Web] CURRENT** — perform post-#172 exact candidate/evidence reconciliation: select a current exact candidate, prove the significant product-source review carry-forward where valid, regenerate/rebind provenance/SBOM/package evidence, and record #172 installer changes explicitly.
- **HUMAN/LEGAL PENDING in parallel**:
  1. R-1 — execute/verify author -> ООО «Арвектум» rights basis and retain a stable non-secret reference;
  2. R-2 — record actual Rospatent registration/transfer status;
  3. R-3 — record applicable corporate/interested-transaction basis/approval/exception;
  4. confirm factual provenance for the newly selected exact candidate and sign the final decision.
- **[Web after explicit APPROVED]** — create governed clean-IP baseline/tag for the exact approved candidate only.
- **OPTIONAL / HOLD** — AppImage L-2 clearance if AppImage is later intended for commercial promotion.

## 6. Per-application routing

- **DONE** — APL-ROUTE-001 platform-neutral rule model.
- **DONE** — APL-ROUTE-002 feasibility matrix.
- **DONE** — APL-ROUTE-004 durable ownership/recovery/security journal.
- **AUTONOMOUS COMPLETE / LOCAL-NATIVE PENDING** — APL-ROUTE-003 control-plane prototype.

### Windows production enforcement STOP-GATE

Choose deliberately before production native enforcement:

1. Microsoft Hardware Dev Center + accepted EV identity for optional WFP/kernel SKU;
2. separately reviewed already-signed third-party enforcement component;
3. supported user-mode architecture with equivalent semantics;
4. defer Windows per-app routing and keep system-proxy/domain/IP product line production-ready.

- **[Web/Decision] READY** — architecture/product decision can be worked now in parallel.
- Do not use test-signing/developer mode as a production workaround.

Future native branches after the Windows decision:

- **[Linux]** cgroup/socket + nftables/policy-routing prototype and ownership/recovery acceptance on Astra.
- **[Mac]** NetworkExtension entitlement/distribution proof before native implementation.
- **[Web/Mobile later]** Android/iOS capability architecture; implementation only where platform policy allows per-app routing.

## 7. Sovereignty / recovery hardening backlog

- **DEFERRED** — Windows P0.2 clean-machine endpoint-denied rebuild.
- **DEFERRED / MEDIUM** — controlled Linux build-input mirror + endpoint-denied rebuild.
- **DEFERRED / MEDIUM** — controlled macOS build-input mirror + endpoint-denied rebuild.
- **DEFERRED** — international Microsoft/GlobalSign and Apple signing/notarization paths; not blockers for the Russian-first baseline.

## 8. What can be done now — execution matrix

### [Web] ChatGPT/GitHub — can start immediately and independently

1. **Repository/mirror reconciliation** — verify GitHub `arvectum1/proxy-launcher` `main` -> GitVerse branches/tags and canonical/default-branch presentation after the 2026-08-24 workflow repairs.
2. **APL-IP-001 post-#172 exact candidate/evidence reconciliation** — this is the highest-value autonomous engineering/governance task.
3. **APL-WIN-014 baseline artifact preparation** — locate/reconcile a trustworthy sealed previous Windows package and hashes for the required cross-version App Control upgrade proof.
4. **APL-ROUTE-003 decision work** — compare WFP/third-party/user-mode/defer paths and record the product decision when ready.
5. **AppImage L-2 research/package planning** — optional only; does not block `.deb`/Astra.

### [Human] can run in parallel now

- R-1/R-2/R-3 and final IP/legal factual sign-off preparation.

### [Win] ARVECTUM-DEMO — available now

1. **APL-WIN-014 CURRENT** — App Control for Business prepare/enforced/final gate, subject to the distinct sealed baseline prerequisite.
2. **APL-REL-014 remainder** — exact signed-set lifecycle/recovery evidence if not already captured by the canonical acceptance record.
3. Export/hash-verify all Windows evidence before repartitioning.

### [Linux] ARVECTUM-DEMO — immediately after Windows-only gates

1. create persistent dual boot without deleting Windows;
2. install Astra Linux SE 1.8 x86-64;
3. run `qa/collect_astra_acceptance_preflight.sh`;
4. execute APL-LNX-010;
5. close Gate R8 on real PASS.

### [Mac]

No release-critical macOS acceptance task remains. Only deferred signing/notarization/sovereignty hardening or later per-app routing work.

## 9. Recommended parallel plan

Run four streams without blocking one another:

- **A — [Web]** post-#172 IP candidate/evidence reconciliation;
- **B — [Win]** APL-WIN-014 on ARVECTUM-DEMO, with **[Web]** recovery of the sealed 0.2.2 baseline in parallel;
- **C — [Human]** R-1/R-2/R-3 legal/IP facts;
- **D — [Web]** repository/GitVerse mirror final reconciliation.

After Windows App Control / required signed-set evidence are closed, convert the same laptop to persistent Windows+Astra dual boot and execute **APL-LNX-010 -> Gate R8**.

## Completion discipline

Real-host and human/legal gates remain pending until their named evidence exists. Do not substitute CI, mocks, screenshots or same-version repair for the required physical/cross-version acceptance. Historical evidence remains immutable; later installer/compliance changes require explicit candidate/evidence rebinding. GitHub `main` is the current source authority unless a later governance decision explicitly changes it.