# APL-WIN-014 — real App Control for Business local gate

Status: **WEB BASELINE RECOVERED / HARNESS READY / REAL WINDOWS 11 HOST EVIDENCE REQUIRED**

Canonical host: dedicated physical **ARVECTUM-DEMO**, Windows 11 Enterprise. The abandoned VM path is out of scope. CI, mocks, screenshots, same-version repair, or a run performed after weakening Windows protection are not acceptance evidence.

Canonical Web evidence: `docs/evidence/APL_WIN_014_0_2_2_BASELINE_RECONCILIATION_2026-08-25.md`.

## Safety invariants

- Never disable Smart App Control, App Control for Business, Defender, or another Windows protection to make the test pass.
- Arvectum acceptance scripts do not deploy/remove App Control policies; deployment remains an explicit lab/customer-IT action.
- Current `0.2.3` uses `ReferenceFullHash` trust.
- Historical `0.2.2 P0.4` uses exact-hash trust for the real retained customer-package lifecycle, including its PowerShell installer scripts.
- Final PASS requires both a real `0.2.2 P0.4 -> 0.2.3` upgrade and the standalone exact-current `0.2.3` enforced gate.
- If a genuine P0.4 byte is denied by App Control, preserve the denial and BLOCK. Do not use execution-policy or App Control bypasses.

## Exact historical baseline

- commit: `0ea08d9c815da36d0175f62db153de78f89731fc`;
- path: `release/Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip`;
- Git blob SHA-1: `574d3dc5f90a116555e3a72ff3288c31c19d3dc7`;
- Git blob size: `15963815`;
- P0.4 QA blob: `163e61cd2e1d8ff798289faf075775af8f9bbd41`;
- application SHA-256: `7EF02652E31BBBD68833BE599135CF59519C42B1F8A8FEBB580B3891FFC35EC0`;
- version: `0.2.2` / `0.2.2.0`;
- historical QA: `RESULT: PASS`, `CUSTOMER UPDATE INSTALLER: APPROVED`, `77/77 PASS`.

Do not rebuild or substitute this baseline.

## Prerequisites

Use elevated PowerShell from the current canonical repository. Stage the exact current Russian release at:

`C:\Arvectum\Releases\0.2.3-russian-production`

Before a retry, archive rather than overwrite previous evidence. The recovery/trust scripts deliberately refuse to overwrite evidence directories.

The product acceptance state must be clean before the final gate: no installed Arvectum tree, no Arvectum process, no current/legacy uninstall registration, and no active product state directory. Do not delete foreign/non-Arvectum state to manufacture cleanliness.

## A — recover exact 0.2.2 P0.4 from Git history

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_recover_0_2_2_baseline.ps1 `
  -RepositoryRoot (Get-Location).Path `
  -OutputDirectory 'C:\Arvectum\Releases\0.2.2-P0.4-baseline' `
  -EvidenceDirectory 'C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery'
```

Require `APL-WIN-014 historical 0.2.2 P0.4 recovery: PASS` and:

`C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery\apl-win-014-0.2.2-baseline-recovery.json`

If the historical object is unavailable locally, fetch canonical Git history. Do not download/rebuild a substitute.

## B — normalize the current Setup filename for the older local-gate resolver

The promoted Russian release remains unchanged. This step creates only an exact-byte local acceptance alias because the old current-release gate expects a shorter filename.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_current_release_alias.ps1 `
  -ReleaseDirectory 'C:\Arvectum\Releases\0.2.3-russian-production'
```

Require `APL-WIN-014 current Setup filename compatibility alias: PASS` (or the already-present exact-byte PASS). The alias SHA-256 must be `5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414`.

## C — prepare current 0.2.3 ReferenceFullHash trust

While the lab base policy is in the appropriate staging/audit state for reference installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_local_gate.ps1 `
  -Phase Prepare `
  -BasePolicyId '{BASE-POLICY-GUID}' `
  -ReleaseDirectory 'C:\Arvectum\Releases\0.2.3-russian-production' `
  -TrustPackDirectory 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack' `
  -EvidenceDirectory 'C:\Arvectum\Evidence\APL-WIN-014' `
  -IsolatedAcceptanceEnvironment
```

Require `PREPARED`, not final PASS. Current `trust-pack.json` must use `ReferenceFullHash` and target the supplied base policy.

## D — generate exact 0.2.2 P0.4 baseline trust

Use the same base policy ID:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\windows_app_control_legacy_baseline_trust_pack.ps1 `
  -BaselineManifestPath 'C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery\apl-win-014-0.2.2-baseline-recovery.json' `
  -BasePolicyId '{BASE-POLICY-GUID}' `
  -OutputDirectory 'C:\Arvectum\Evidence\APL-WIN-014\baseline-trust-pack'
```

Require `APL-WIN-014 0.2.2 P0.4 baseline trust pack: PASS` and `Deployment: NOT PERFORMED`. Retain `supplemental_policy_id` from baseline `trust-pack.json`.

## E — deploy policy through the lab/customer management path

Outside Arvectum acceptance tooling:

1. confirm the base policy permits supplemental policies;
2. deploy the current `.cip` from `...\trust-pack`;
3. deploy the P0.4 `.cip` from `...\baseline-trust-pack`;
4. place/keep the base policy in **Enforced** mode;
5. reboot if required;
6. verify with `CiTool.exe -lp -json` that the requested base is on-disk and enforced and both supplemental policies are on-disk and attached to the intended base.

Do not continue on ambiguous policy identity/state.

## F — canonical final acceptance

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

Do not pass a manufactured `BaselineSetupPath` for P0.4. Those compatibility parameters remain only for a separately governed future Inno predecessor.

## PASS requirements

`C:\Arvectum\Evidence\APL-WIN-014\apl-win-014-final-result.json` must be `PASS` and reference PASS subordinate records for upgrade and exact-current enforcement. Evidence must prove:

- immutable P0.4 commit/blob plus locally materialized ZIP SHA-256;
- exact historical application SHA/version;
- intended base and both supplemental policy IDs;
- base policy enforced before and after;
- P0.4 install and exact historical GUI execution under enforcement;
- real `0.2.2 P0.4 -> 0.2.3` transition;
- state marker preservation;
- exact post-upgrade `0.2.3` application and cached repair bytes;
- exact-current Setup/GUI/core/PAC/system-proxy/rollback path;
- repair/corruption recovery/uninstall lifecycle;
- zero tested Arvectum Code Integrity `3077` blocks.

## Export

Before Linux repartitioning, copy `C:\Arvectum\Evidence\APL-WIN-014` to stable external/company evidence storage and create a recursive SHA-256 inventory. Preserve JSON, logs, trust packs and checksum inventory together.

Only a verified exported evidence set may close APL-WIN-014.