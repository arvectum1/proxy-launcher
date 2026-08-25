# APL-WIN-014 — real App Control for Business local gate

Status: **WEB BASELINE RECOVERED / HARNESS READY / REAL WINDOWS 11 HOST EVIDENCE REQUIRED**

For the current Arvectum Proxy Launcher workflow this gate is executed on the dedicated physical **ARVECTUM-DEMO** Windows 11 Enterprise acceptance host with **App Control for Business actually enforced**. The abandoned Windows VM path is out of scope. CI, mocks, Smart App Control screenshots, or a successful run after disabling protection are not acceptance evidence.

## Safety boundary

- Use ARVECTUM-DEMO, not a normal owner workstation and not the abandoned VM.
- Never disable Smart App Control, App Control for Business, Defender, or another Windows protection to make Arvectum run.
- Never change `VerifiedAndReputablePolicyState` as an acceptance workaround.
- The Arvectum acceptance tooling does not deploy/remove App Control policies.
- Policy deployment remains an explicit lab/customer-IT action.
- Current `0.2.3` requires `ReferenceFullHash` trust because Setup alone does not cover generated maintenance/uninstall binaries.
- The canonical historical baseline is the retained **0.2.2 P0.4 LegacyClientZip**, not a newly manufactured 0.2.2 Inno Setup package.
- Final PASS requires a real `0.2.2 P0.4 -> 0.2.3` transition under enforcement plus the standalone exact-current `0.2.3` enforced gate.
- Same-version repair is not upgrade evidence.

Canonical Web evidence: `docs/evidence/APL_WIN_014_0_2_2_BASELINE_RECONCILIATION_2026-08-25.md`.

## Exact historical baseline

The Web-side reconciliation selected:

- source commit: `0ea08d9c815da36d0175f62db153de78f89731fc`;
- retained package: `release/Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip`;
- package Git blob SHA-1: `574d3dc5f90a116555e3a72ff3288c31c19d3dc7`;
- Git blob size: `15963815` bytes;
- P0.4 QA evidence blob: `163e61cd2e1d8ff798289faf075775af8f9bbd41`;
- application SHA-256: `7EF02652E31BBBD68833BE599135CF59519C42B1F8A8FEBB580B3891FFC35EC0`;
- application version: `0.2.2` / file version `0.2.2.0`;
- historical QA: `RESULT: PASS`, `CUSTOMER UPDATE INSTALLER: APPROVED`, `77/77 PASS`.

Do not download an arbitrary similarly named package and do not rebuild 0.2.2. The local recovery script materializes the exact retained Git blob from the local canonical repository and fails closed on any mismatch.

## Canonical scripts

1. `tools/windows_app_control_recover_0_2_2_baseline.ps1`
   - restores the exact historical package from immutable Git history;
   - proves commit/path/blob/size/QA evidence/app hash/version;
   - inventories every recovered file;
   - emits `apl-win-014-0.2.2-baseline-recovery.json`.
2. `tools/windows_app_control_local_gate.ps1`
   - `Prepare`: verifies exact current `0.2.3`, reference-installs it, creates current `ReferenceFullHash` trust pack; no policy deployment;
   - `Enforced`: exact current standalone App Control acceptance.
3. `tools/windows_app_control_legacy_baseline_trust_pack.ps1`
   - consumes the exact recovery manifest;
   - creates a hash supplemental policy for the genuine P0.4 lifecycle, including its historical PowerShell installer scripts;
   - does not deploy the policy.
4. `tools/windows_app_control_upgrade_acceptance.ps1`
   - installs exact recovered P0.4 under active baseline supplemental trust;
   - observes execution of the exact historical GUI;
   - upgrades in place to exact current `0.2.3`;
   - proves exact post-upgrade bytes/state/uninstall/Code Integrity.
5. `tools/windows_app_control_local_gate_complete.ps1`
   - the **only final completion entry point**;
   - emits PASS only if both the real historical upgrade gate and exact-current enforced gate PASS.

## Phase 0 — prepare a clean evidence root

Use elevated PowerShell from the current canonical repository on ARVECTUM-DEMO.

Before beginning, preserve any earlier acceptance evidence instead of overwriting it. The recovery/trust scripts intentionally refuse to overwrite an existing output directory. If this is a retry, move the previous `C:\Arvectum\Evidence\APL-WIN-014` and recovered baseline directory into a timestamped archive first.

The application acceptance state must be clean before the final gate: no installed Arvectum tree in `Documents\ArvectumProxyLauncher`, no Arvectum process, no current/legacy uninstall registration, and no active product state directory. Do not delete foreign/non-Arvectum state to satisfy this precondition.

## Phase A — recover exact historical 0.2.2 P0.4

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_recover_0_2_2_baseline.ps1 `
  -RepositoryRoot (Get-Location).Path `
  -OutputDirectory 'C:\Arvectum\Releases\0.2.2-P0.4-baseline' `
  -EvidenceDirectory 'C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery'
```

Required result: `APL-WIN-014 historical 0.2.2 P0.4 recovery: PASS`.

Required manifest:

`C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery\apl-win-014-0.2.2-baseline-recovery.json`

It must record `result = PASS`, commit `0ea08d9...`, Git blob `574d3dc5...`, version `0.2.2`, and application SHA-256 `7ef02652...ffc35ec0`. The recovered ZIP SHA-256 is generated locally from the exact blob and becomes part of the evidence.

If recovery fails because the historical commit/blob is missing locally, fetch canonical Git history first. Do not replace the missing object with a downloaded/rebuilt substitute.

## Phase B — prepare current 0.2.3 ReferenceFullHash trust pack

While the lab/customer base policy is in an appropriate staging/audit state for reference installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_local_gate.ps1 `
  -Phase Prepare `
  -BasePolicyId '{BASE-POLICY-GUID}' `
  -ReleaseDirectory 'C:\Arvectum\Releases\0.2.3-russian-production' `
  -TrustPackDirectory 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack' `
  -EvidenceDirectory 'C:\Arvectum\Evidence\APL-WIN-014' `
  -IsolatedAcceptanceEnvironment
```

Expected result: `PREPARED`, not final PASS. The generated current trust pack must use `ReferenceFullHash` and target the supplied base policy ID.

## Phase C — generate exact historical baseline trust pack

Use the **same base policy ID**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_legacy_baseline_trust_pack.ps1 `
  -BaselineManifestPath 'C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery\apl-win-014-0.2.2-baseline-recovery.json' `
  -BasePolicyId '{BASE-POLICY-GUID}' `
  -OutputDirectory 'C:\Arvectum\Evidence\APL-WIN-014\baseline-trust-pack'
```

Required result: `APL-WIN-014 0.2.2 P0.4 baseline trust pack: PASS` and `Deployment: NOT PERFORMED`.

Read the generated baseline `trust-pack.json` and retain its `supplemental_policy_id` for the final command.

## Phase D — deploy App Control policies outside Arvectum tooling

Using the approved isolated-host/customer App Control management path:

1. confirm the base policy permits supplemental policies;
2. if the base policy is signed, authorize supplemental policy signers as required by that policy model;
3. deploy current `.cip` from `C:\Arvectum\Evidence\APL-WIN-014\trust-pack`;
4. deploy baseline `.cip` from `C:\Arvectum\Evidence\APL-WIN-014\baseline-trust-pack`;
5. place/keep the base policy in the intended **Enforced** state;
6. reboot if required by the management path;
7. verify with `CiTool.exe -lp -json` that:
   - the requested base policy is present, on disk, and enforced;
   - the current supplemental policy is present/on disk;
   - the baseline supplemental policy is present/on disk;
   - both supplement the intended base policy.

Arvectum scripts intentionally do not perform these policy mutations.

If the historical P0.4 PowerShell installer is denied by App Control, **do not use `ExecutionPolicy Bypass` as a trust bypass and do not weaken App Control**. Preserve the denial evidence and stop: that is a legitimate BLOCK requiring policy/trust analysis.

## Phase E — canonical final acceptance

After both supplemental policies are active and the base policy is enforced, ensure the product state is clean, then run:

```powershell
$baselineTrust = Get-Content `
  'C:\Arvectum\Evidence\APL-WIN-014\baseline-trust-pack\trust-pack.json' `
  -Raw | ConvertFrom-Json

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_local_gate_complete.ps1 `
  -BasePolicyId '{BASE-POLICY-GUID}' `
  -BaselineSupplementalPolicyId $baselineTrust.supplemental_policy_id `
  -BaselineKind LegacyClientZip `
  -BaselineManifestPath 'C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery\apl-win-014-0.2.2-baseline-recovery.json' `
  -BaselineTrustPackDirectory 'C:\Arvectum\Evidence\APL-WIN-014\baseline-trust-pack' `
  -BaselineVersion '0.2.2' `
  -ReleaseDirectory 'C:\Arvectum\Releases\0.2.3-russian-production' `
  -TrustPackDirectory 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack' `
  -EvidenceDirectory 'C:\Arvectum\Evidence\APL-WIN-014' `
  -IsolatedAcceptanceEnvironment
```

Do not pass a manufactured `BaselineSetupPath` for the canonical P0.4 path. Those legacy parameters remain only for separately governed future Inno predecessors.

## Required final evidence

`C:\Arvectum\Evidence\APL-WIN-014\apl-win-014-final-result.json` must contain `result = PASS` and reference two subordinate PASS records:

- `apl-win-014-upgrade-result.json`;
- `apl-win-014-enforced-result.json`.

The evidence set must prove, at minimum:

- immutable P0.4 source commit/blob identity and locally materialized ZIP SHA-256;
- exact historical `0.2.2` app SHA-256/version;
- baseline and current supplemental policy IDs;
- requested base policy remained enforced;
- exact P0.4 install and historical GUI execution succeeded under enforcement;
- real `0.2.2 P0.4 -> 0.2.3` upgrade succeeded;
- per-user state marker survived upgrade;
- exact post-upgrade `0.2.3` application and cached repair hashes matched the sealed release;
- standalone exact-current Setup/first GUI/core/PAC/system-proxy/rollback path passed;
- repair/corruption recovery/uninstall lifecycle passed;
- no tested Arvectum Code Integrity event `3077` was recorded;
- App Control remained enforced after acceptance.

## Export requirement

Before repartitioning or relying on the result, copy `C:\Arvectum\Evidence\APL-WIN-014` to stable external/company evidence storage and calculate a recursive SHA-256 inventory. Preserve the raw JSON/logs/trust packs and the hash inventory together.

Only after the exported evidence is verified may APL-WIN-014 be changed from local `PENDING` to `PASS`.