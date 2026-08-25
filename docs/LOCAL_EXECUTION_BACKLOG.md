# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-08-25
Canonical GitHub repository: `arvectum1/proxy-launcher`

This file contains work that cannot be truthfully completed by hosted repository automation alone, plus the immediate local prerequisites for those gates.

## P0 — ARVECTUM-DEMO Windows physical stand

Current stand:

- x86-64 physical laptop;
- Windows 11 Enterprise 25H2;
- 512 GB SSD;
- portable real-host functionality: PASS;
- installer transition defect #171: fixed by #172 / `e2be3445e23eb6e8f0709f37fec0ecba50447dc7`;
- fixed installer over active portable: PASS;
- uninstall: PASS;
- fresh reinstall: PASS;
- persistent proxy settings survived the lifecycle test.

Target permanent state: Windows 11 + Astra Linux SE 1.8 x86-64 dual boot.

### P0.1 — APL-WIN-014 App Control for Business — CURRENT

Status: **REAL HOST AVAILABLE / FINAL EVIDENCE PENDING**.

Use `docs/APL_WIN_014_LOCAL_GATE.md`.

Required local boundary:

1. recover/verify a distinct sealed previous Windows installer (prefer the actual retained 0.2.2 release if available) and its governed Setup/application hashes;
2. generate the current 0.2.3 `ReferenceFullHash` trust pack;
3. deploy current and baseline supplemental trust through the lab/customer App Control management path;
4. keep the base policy actually enforced;
5. run `tools/windows_app_control_local_gate_complete.ps1`;
6. require both subordinate enforced and real cross-version upgrade PASS records;
7. require no tested Arvectum Code Integrity 3077 denial and preserve the enforced policy after the test;
8. export/hash-verify evidence outside the laptop.

Do not replace the cross-version requirement with same-version repair and do not manufacture a historical baseline.

### P0.2 — APL-REL-014 exact signed-set lifecycle — PARTIAL / READY

Real installer transition/uninstall/fresh-reinstall behavior has passed after #172. Keep the exact governed signed-set lifecycle/recovery acceptance pending until its canonical evidence identifies the exact signed artifacts, recovery states and required upgrade/recovery results.

Complete on ARVECTUM-DEMO before Linux repartitioning if still outstanding, then export evidence.

### P0.3 — P0.2 independent clean-machine endpoint-denied rebuild — DEFERRED

The laptop is no longer an untouched clean baseline because product acceptance has already been executed. Do not force a reinstall merely to close this resilience drill. Keep it deferred until a naturally suitable clean environment is available.

## P1 — Astra Linux / Gate R8 — READY AFTER WINDOWS-ONLY GATES

On the same laptop:

1. finish/export Windows App Control and remaining exact signed-set evidence;
2. preserve BitLocker/device-encryption recovery material if applicable;
3. disable Windows Fast Startup/hibernation;
4. shrink Windows `C:` using Windows Disk Management and leave Astra space unallocated;
5. install Astra Linux Special Edition 1.8 x86-64 with manual GPT/UEFI partitioning;
6. reuse the existing EFI System Partition without formatting it;
7. preserve Windows NTFS/MSR/Recovery partitions and Windows Boot Manager;
8. create Astra ext4 root in unallocated space;
9. verify both Windows 11 and Astra boot;
10. capture Astra baseline;
11. run `bash qa/collect_astra_acceptance_preflight.sh`;
12. execute APL-LNX-010 real `.deb` acceptance: GUI/runtime detection, NetworkManager/PolicyKit, enable/sync/disable, rollback, autostart, crash/reboot recovery, update/remove and diagnostics/privacy;
13. close Gate R8 only from real Astra-host PASS evidence.

Ubuntu CI or another distro is not a substitute.

## P2 — APL-IP-001 final human/legal boundary

Status: **POST-#172 ENGINEERING RECONCILED / HUMAN-LEGAL PENDING**.

Hosted/Web reconciliation is complete. The selected current engineering candidate is:

- merge commit `adc917e905acca1f8e97d560a3363b07adc279fb`;
- tree `b36e7dc17830622c510fc7c8b643cfd36bb7fe3f`;
- candidate-equivalent validated PR head `56cfecf27c384591caae32bab53d343d9e6b9085`;
- candidate-equivalent PR test-merge `73f85f86844f9c8c8a216691b8f9c42d92ca40f7`;
- exact evidence: `docs/evidence/APL_IP_001_POST_172_CANDIDATE_RECONCILIATION_2026-08-25.md`;
- canonical decision record: `docs/APL_IP_001_POST_172_SIGNOFF.md`.

The earlier `ef9846e...` post-APL-IP-004 candidate remains historical evidence but is superseded for the current installer state because #172 changed installer implementation afterwards.

Remaining human/legal tasks:

1. R-1 — execute/verify author -> ООО «Арвектум» rights basis covering candidate `adc917e...` / tree `b36e7dc...` and retain stable non-secret evidence reference;
2. R-2 — record actual Rospatent registration/transfer status;
3. R-3 — record actual corporate/interested-transaction basis/approval/exception;
4. confirm factual provenance for the selected post-#172 candidate;
5. sign explicit final `APPROVED`, `CONDITIONAL` or `HOLD` in `docs/APL_IP_001_POST_172_SIGNOFF.md`.

Candidate-binding rights draft addendum is available at `docs/legal/APL_IP_001_RIGHTS_ASSIGNMENT_POST_172_CANDIDATE_ADDENDUM_2026-08-25.md`.

Only explicit `APPROVED` unlocks the Web clean-IP baseline/tag. A material product/build/package implementation change after the selected candidate requires a new exact reconciliation first.

## P3 — repository / GitVerse governance verification — DONE

Status: **DONE / VERIFIED 2026-08-24**.

- canonical GitHub authority is `arvectum1/proxy-launcher` / `main`;
- GitHub -> GitVerse mirror was repaired after owner migration;
- GitVerse canonical/default branch was reconciled to `main`;
- canonical GitHub `main` `c888690928d61e03532de2a023d7870af52354e8` received `gitverse-mirror=success` from workflow run `32769207494`;
- GitHub `main` protection, which had been lost during migration, was restored by the repository owner/admin;
- GitHub branch API now reports `main.protected=true`;
- PR #3 negative acceptance attempted a normal merge while required `build` was in progress and GitHub rejected it with HTTP `405 Repository rule violations found` / `Required status check "build" is in progress.`;
- the connected GitHub identity has `admin` permission, so the negative test also proves the normal connected-admin merge path does not silently bypass the required `build` gate;
- evidence: `docs/evidence/GITHUB_MAIN_PROTECTION_ACCEPTANCE_2026-08-24.md`;
- recovery contract: `docs/GITHUB_MAIN_PROTECTION_RECOVERY.md`.

No remaining local/admin action exists for owner-migration repository governance. The current ChatGPT GitHub connector still does not expose ruleset/branch-protection mutation endpoints; that is a connector action-whitelist limitation, not a repository permission limitation.

## P4 — AppImage L-2 — OPTIONAL / HOLD

AppImage stays outside promoted commercial scope until the pinned type-2 runtime/transitive obligations and applicable LGPL/libfuse path are separately cleared. This does not block Debian `.deb` or Astra acceptance.

## P5 — APL-ROUTE-003 product decision — READY / STOP-GATE

Before production Windows per-app enforcement choose one:

1. Microsoft Hardware Dev Center + accepted EV identity dependency;
2. separately reviewed already-signed third-party component;
3. supported user-mode equivalent semantics;
4. defer Windows per-app routing.

Architecture/product research is Web-executable now. Native production implementation remains blocked until the choice is explicit.

## P6 — deferred sovereignty hardening

- Windows independent endpoint-denied rebuild in a future naturally clean environment;
- controlled Linux build-input mirror + endpoint-denied rebuild;
- controlled macOS build-input mirror + endpoint-denied rebuild;
- later Apple/Microsoft international signing/notarization paths.

## Current parallel execution order

### [Web]

1. recover/reconcile a trustworthy sealed previous Windows package/evidence for APL-WIN-014 cross-version proof;
2. optional APL-ROUTE-003 architecture decision work.

Post-#172 APL-IP-001 reconciliation and repository/GitVerse owner-migration governance are complete and removed from the active Web backlog.

### [Win] ARVECTUM-DEMO

1. APL-WIN-014 App Control final gate when the baseline artifact/trust prerequisite is ready;
2. close any remaining APL-REL-014 exact signed-set lifecycle evidence;
3. export/hash-verify Windows evidence.

### [Human]

R-1/R-2/R-3, post-#172 factual-provenance confirmation and final authorized APL-IP-001 decision can run now in parallel.

### [Linux] ARVECTUM-DEMO

After Windows-only gates: create dual boot, install Astra SE 1.8, execute APL-LNX-010 and close Gate R8.

### [Mac]

No release-critical local task. Only deferred signing/notarization/sovereignty hardening or later per-app routing.

## Completion discipline

Do not relabel physical App Control, cross-version upgrade, Astra, exact signed-set or human/legal gates as complete from CI, mocks or documentation. Keep historical artifacts/evidence immutable, and rebind clean-IP evidence whenever product source, build dependencies or package/compliance implementation materially changes after a selected candidate. Repository owner-migration governance is closed from real mirror evidence, `main.protected=true`, and a rule-enforced negative merge test rather than from assumed settings state.