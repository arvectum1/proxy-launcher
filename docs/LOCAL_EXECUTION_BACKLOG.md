# Arvectum Proxy Launcher — remaining local / human / infrastructure backlog

Updated: 2026-08-24
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

Status: **HUMAN/LEGAL PENDING**.

Engineering note: the previous post-APL-IP-004 candidate `ef9846e...` is no longer sufficient as the final clean-IP candidate because installer implementation changed in #172 afterwards. Hosted work must first select/rebind a current post-#172 exact candidate/evidence set.

Human/legal tasks can proceed in parallel with that Web reconciliation:

1. R-1 — execute/verify author -> ООО «Арвектум» rights basis and retain stable non-secret evidence reference;
2. R-2 — record actual Rospatent registration/transfer status;
3. R-3 — record actual corporate/interested-transaction basis/approval/exception;
4. confirm factual provenance for the finally selected exact candidate;
5. sign explicit final `APPROVED`, `CONDITIONAL` or `HOLD`.

Only explicit `APPROVED` unlocks the Web clean-IP baseline/tag.

## P3 — repository / GitVerse governance verification

Status: **WEB/MANUAL GOVERNANCE VERIFICATION REQUIRED**.

GitHub authority is now `arvectum1/proxy-launcher` / `main`. The GitHub->GitVerse mirror workflow was repaired on 2026-08-24. Verify that:

- current GitHub `main` reaches GitVerse;
- intended release tags/branches reach GitVerse;
- GitVerse default/canonical branch presentation does not cause `master` to be mistaken for current source authority;
- no history rewrite or silent branch divergence is introduced.

Also verify/reinstate the pre-migration GitHub protection/governance contract. During roadmap reconciliation PR #1 could be merged while its Actions workflows were still queued. This is evidence that the new repository's effective merge controls must be checked rather than assumed. Confirm in GitHub settings that the intended `main` rules still require PR-based changes, the required `build`/other chosen checks, strictness/conversation resolution as intended, no force-push/delete, and the desired administrator enforcement/bypass policy. Record the resulting protection state as evidence.

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

1. post-#172 APL-IP-001 exact candidate/evidence reconciliation;
2. recover/reconcile a trustworthy sealed previous Windows package/evidence for APL-WIN-014 cross-version proof;
3. verify GitHub `main` -> GitVerse mirror/canonical branch state;
4. verify/reinstate GitHub `main` branch protection/rules after repository migration;
5. optional APL-ROUTE-003 architecture decision work.

### [Win] ARVECTUM-DEMO

1. APL-WIN-014 App Control final gate when the baseline artifact/trust prerequisite is ready;
2. close any remaining APL-REL-014 exact signed-set lifecycle evidence;
3. export/hash-verify Windows evidence.

### [Human]

R-1/R-2/R-3 and final factual/legal sign-off preparation can run now in parallel.

### [Linux] ARVECTUM-DEMO

After Windows-only gates: create dual boot, install Astra SE 1.8, execute APL-LNX-010 and close Gate R8.

### [Mac]

No release-critical local task. Only deferred signing/notarization/sovereignty hardening or later per-app routing.

## Completion discipline

Do not relabel physical App Control, cross-version upgrade, Astra, exact signed-set or human/legal gates as complete from CI, mocks or documentation. Keep historical artifacts/evidence immutable, and rebind clean-IP evidence whenever product/package implementation changes after a selected candidate. Do not assume repository protection survived owner/repository migration until the effective rules have been verified.