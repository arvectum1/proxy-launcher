# APL-WIN-014 — exact retained 0.2.2 baseline reconciliation

Status: **WEB RECONCILIATION: PASS / LOCAL APP CONTROL ACCEPTANCE: PENDING**  
Date: 2026-08-25

## Purpose

APL-WIN-014 requires a real cross-version transition under enforced App Control for Business. Same-version repair of `0.2.3` is not upgrade evidence, and a historical predecessor must not be manufactured after the fact.

This record identifies the exact retained Windows `0.2.2` package that may be used as the predecessor for the physical ARVECTUM-DEMO acceptance and adapts the local gate to its real historical lifecycle.

## Selected historical baseline

The selected predecessor is the latest governed `0.2.2` customer-update state retained in canonical Git history:

- repository: `arvectum1/proxy-launcher`;
- commit: `0ea08d9c815da36d0175f62db153de78f89731fc`;
- commit subject: `Release Arvectum Proxy Launcher 0.2.2 P0.4`;
- retained package path: `release/Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip`;
- Git blob SHA-1: `574d3dc5f90a116555e3a72ff3288c31c19d3dc7`;
- Git blob size: `15963815` bytes;
- application product version: `0.2.2`;
- application file version: `0.2.2.0`;
- application EXE SHA-256: `7EF02652E31BBBD68833BE599135CF59519C42B1F8A8FEBB580B3891FFC35EC0`.

The immutable Git blob is the Web-side byte anchor. The local recovery script additionally computes and records the recovered ZIP SHA-256 after materialization from that exact blob; the value is intentionally not invented in this Web record.

## Why P0.4, not the first 0.2.2 commit

The repository also preserves the earlier `0.2.2` release commit `18eeccd01b5644f64d4a6cb9f310958b337f8be0`. P0.4 is selected instead because it is the later governed customer-update state within the same `0.2.2` version line and has explicit native update-safety acceptance.

The P0.4 QA evidence is itself retained at:

- path: `qa/CHATGPT_REPORT_0.2.2_P0.4.md`;
- Git blob SHA-1: `163e61cd2e1d8ff798289faf075775af8f9bbd41`.

That report records:

- `RESULT: PASS`;
- `CUSTOMER UPDATE INSTALLER: APPROVED`;
- `AUTHENTICODE: NOT SIGNED`;
- automated regression suite `77/77 PASS`;
- native active-legacy-recovery migration PASS;
- exact source/staged/installed hash verification PASS;
- missing-legacy, foreign-recovery and open-GUI safety gates PASS;
- WinINET/environment rollback PASS.

The lack of Microsoft Authenticode is not hidden or reinterpreted. APL-WIN-014 uses explicit App Control exact-hash supplemental trust for this historical baseline; the test is specifically intended to prove execution under the chosen enforced policy rather than to claim historical Microsoft signing.

## Historical lifecycle boundary

P0.4 is not an Inno Setup predecessor. It is the genuine earlier customer ZIP lifecycle:

- `install.bat`;
- `install.ps1`;
- `uninstall.ps1`;
- `Arvectum Proxy Launcher.exe`.

The historical installer places the application under the user's `Documents\ArvectumProxyLauncher`, uses an ownership marker, protects foreign recovery/autostart state, and starts the exact installed GUI after a successful install.

Therefore the previous APL-WIN-014 harness contract that demanded a historical `BaselineSetupPath` `.exe` could not truthfully consume the retained P0.4 package. Creating a synthetic `0.2.2` Inno Setup package now would destroy the evidentiary value of the cross-version test.

## Web-side remediation

The current repository now provides a fail-closed path for the real predecessor.

### Exact recovery

`tools/windows_app_control_recover_0_2_2_baseline.ps1`:

1. requires a Git working copy;
2. verifies commit `0ea08d9...` exists;
3. verifies the exact package path resolves to blob `574d3dc5...`;
4. verifies blob size `15963815`;
5. verifies the P0.4 QA record blob `163e61cd...`;
6. materializes the retained ZIP with `git archive` rather than rebuilding it;
7. proves the materialized ZIP reproduces the same Git blob with `git hash-object`;
8. expands it and deterministically locates the package root through the single exact launcher EXE;
9. verifies application SHA-256 and `0.2.2` / `0.2.2.0` version metadata;
10. inventories every recovered file and emits a PASS recovery manifest plus checksum.

Any mismatch blocks the local gate.

### Exact App Control trust

`tools/windows_app_control_legacy_baseline_trust_pack.ps1`:

- consumes only the verified recovery manifest;
- rechecks the complete recovered file inventory;
- generates a `Hash` supplemental App Control policy bound to the requested base policy;
- deliberately includes the historical `install.ps1` / `uninstall.ps1` script bytes instead of using `-NoScript`;
- emits `trust-pack.json`, `.xml`, `.cip`, deployment notes and checksums;
- **does not deploy the policy** and does not weaken App Control.

If the historical installer scripts cannot execute under the actual enforced App Control configuration, acceptance must BLOCK. `ExecutionPolicy Bypass`, disabling App Control, Smart App Control changes or another trust bypass are not acceptable substitutes.

### Real transition gate

`tools/windows_app_control_upgrade_acceptance.ps1` now has canonical `LegacyClientZip` support. Under the exact active baseline and current supplemental policies it must prove:

1. recovered P0.4 installation succeeds under enforcement;
2. the exact installed `0.2.2` EXE hash matches historical evidence;
3. the historical GUI actually executes under enforcement;
4. the real current `0.2.3` Inno Setup upgrades that installation in place;
5. per-user state marker survives;
6. post-upgrade app and cached repair bytes match the sealed current release;
7. current version registration is `0.2.3`;
8. uninstall succeeds;
9. no Arvectum Code Integrity event `3077` is observed during the transition;
10. the base App Control policy remains enforced.

`tools/windows_app_control_local_gate_complete.ps1` remains the only final completion entry point and still requires the separate exact-current `0.2.3` enforced gate after the cross-version sub-gate.

## Current disposition

**WEB RECONCILIATION: PASS.**

A trustworthy previous baseline has been identified without rebuilding or manufacturing historical artifacts, and the repository harness now models its actual lifecycle.

**LOCAL APP CONTROL ACCEPTANCE: PENDING.**

The following still require the physical ARVECTUM-DEMO Windows 11 Enterprise host:

- materialize the historical ZIP from local Git and capture its generated SHA-256/recovery manifest;
- prepare current `0.2.3` ReferenceFullHash trust;
- generate the exact P0.4 baseline trust pack against the same base policy;
- deploy both supplemental policies through the lab/customer App Control management path;
- put/keep the base policy in Enforced mode;
- execute the canonical final gate;
- export/hash-verify the evidence set outside the laptop.

No local PASS is claimed by this Web record.