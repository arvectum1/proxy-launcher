<#
.SYNOPSIS
    Fail-closed readiness barrier for destructive APL-WIN-014 Enforced acceptance.
.DESCRIPTION
    Real ARVECTUM-DEMO testing proved that an exact outer EXE hash is not enough for
    PyInstaller onefile or Inno Setup lifecycle execution under App Control for Business.

    This barrier intentionally blocks the legacy v0.2.3 ReferenceFullHash trust pack.
    It accepts only final v2 evidence promoted from the exact rehearsal-tested provisional
    supplemental, with static-runtime lifecycle coverage and a native recovery rehearsal
    performed under actual Enforced/ConstrainedLanguage.

    This script never deploys/removes/changes App Control policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$TrustPackDirectory,
    [Parameter(Mandatory = $false)] [Guid]$ExpectedBasePolicyId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Sha256([object]$Value, [string]$Label) {
    $text = ([string]$Value).ToLowerInvariant()
    if ($text -notmatch '^[0-9a-f]{64}$') { throw "SAFETY BLOCK: $Label is not a SHA256." }
    $text
}

$manifestPath = Join-Path $TrustPackDirectory 'trust-pack.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "SAFETY BLOCK: App Control trust-pack manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]$manifest.schema -eq 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v1') {
    throw 'SAFETY BLOCK: legacy trust-pack schema v1 is insufficient for Enforced lifecycle acceptance (ARVECTUM-DEMO incident / issue #10).'
}
if ([string]$manifest.mode -eq 'ReferenceFullHash') {
    throw 'SAFETY BLOCK: ReferenceFullHash alone is insufficient for Enforced lifecycle acceptance.'
}
if ([string]$manifest.schema -ne 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v2') {
    throw "SAFETY BLOCK: unsupported App Control trust-pack schema '$([string]$manifest.schema)'."
}
if ([string]$manifest.result -ne 'PASS') { throw 'SAFETY BLOCK: App Control trust pack is not a PASS record.' }
if ([string]$manifest.mode -ne 'StaticRuntimeLifecycleHash') { throw 'SAFETY BLOCK: final v2 mode must be StaticRuntimeLifecycleHash.' }
if ([string]$manifest.packaging_layout -ne 'static-runtime') { throw 'SAFETY BLOCK: Enforced acceptance requires packaging_layout=static-runtime.' }
if ([bool]$manifest.pyinstaller_onefile) { throw 'SAFETY BLOCK: PyInstaller onefile is prohibited.' }
if (-not [bool]$manifest.runtime_complete) { throw 'SAFETY BLOCK: complete executable runtime coverage is not proven.' }
if (-not [bool]$manifest.installer_lifecycle_complete) { throw 'SAFETY BLOCK: installer lifecycle coverage is not proven.' }
if (-not [bool]$manifest.enforced_lifecycle_ready) { throw 'SAFETY BLOCK: trust pack is not marked enforced_lifecycle_ready.' }

$null = Require-Sha256 $manifest.enterprise_bundle_manifest_sha256 'enterprise bundle manifest hash'
$null = Require-Sha256 $manifest.provisional_trust_pack_manifest_sha256 'provisional trust manifest hash'
$null = Require-Sha256 $manifest.supplemental_policy_cip_sha256 'supplemental CIP hash'
$null = Require-Sha256 $manifest.setup_exe_sha256 'Setup hash'
$null = Require-Sha256 $manifest.native_recovery_sha256 'native recovery hash'
$null = Require-Sha256 $manifest.runtime_entry_sha256 'runtime entry hash'
$null = Require-Sha256 $manifest.reference_uninstaller_sha256 'reference uninstaller hash'
$null = Require-Sha256 $manifest.enforced_lifecycle_evidence_sha256 'Enforced lifecycle evidence hash'
$null = Require-Sha256 $manifest.recovery_rehearsal_evidence_sha256 'recovery rehearsal evidence hash'

if ([string]$manifest.supplemental_policy_id -notmatch '[0-9a-fA-F-]{36}') {
    throw 'SAFETY BLOCK: final v2 has no valid supplemental policy identity.'
}
if ($ExpectedBasePolicyId -ne [Guid]::Empty) {
    $actualBase = ([Guid](([string]$manifest.base_policy_id).Trim().Trim('{}'))).ToString('D')
    $expectedBase = $ExpectedBasePolicyId.ToString('D')
    if ($actualBase -ine $expectedBase) { throw "SAFETY BLOCK: trust pack targets base '$actualBase', expected '$expectedBase'." }
}

$cipPath = Join-Path $TrustPackDirectory ([string]$manifest.supplemental_policy_cip)
if (-not (Test-Path -LiteralPath $cipPath -PathType Leaf)) { throw 'SAFETY BLOCK: final v2 supplemental CIP is missing.' }
$actualCip = (Get-FileHash -LiteralPath $cipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualCip -ne ([string]$manifest.supplemental_policy_cip_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: final v2 supplemental CIP bytes differ from manifest.' }
$xmlPath = Join-Path $TrustPackDirectory ([string]$manifest.supplemental_policy_xml)
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) { throw 'SAFETY BLOCK: final v2 supplemental XML is missing.' }
if (Select-String -LiteralPath $xmlPath -Pattern 'Enabled:Audit Mode' -Quiet) { throw 'SAFETY BLOCK: final supplemental XML contains Audit Mode.' }

$provisionalManifestPath = Join-Path $TrustPackDirectory 'provisional-trust-pack.json'
if (-not (Test-Path -LiteralPath $provisionalManifestPath -PathType Leaf)) { throw 'SAFETY BLOCK: promoted provisional manifest is missing.' }
$actualProvisional = (Get-FileHash -LiteralPath $provisionalManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualProvisional -ne ([string]$manifest.provisional_trust_pack_manifest_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: promoted provisional manifest hash mismatch.' }
$provisional = Get-Content -LiteralPath $provisionalManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$provisional.schema -ne 'arvectum.proxy.windows-app-control-provisional-trust-pack.v1' -or [string]$provisional.purpose -ne 'rehearsal-only') {
    throw 'SAFETY BLOCK: embedded provisional evidence has an unsupported identity.'
}
if ([bool]$provisional.final_acceptance_evidence -or [bool]$provisional.enforced_lifecycle_ready) {
    throw 'SAFETY BLOCK: embedded provisional evidence illegally claims final readiness.'
}
if (([string]$provisional.supplemental_policy_id) -ine ([string]$manifest.supplemental_policy_id)) {
    throw 'SAFETY BLOCK: final v2 policy ID differs from the rehearsal-tested provisional policy.'
}
if (([string]$provisional.supplemental_policy_cip_sha256).ToLowerInvariant() -ne $actualCip) {
    throw 'SAFETY BLOCK: final v2 CIP differs from the rehearsal-tested provisional CIP.'
}

$rehearsal = $manifest.recovery_rehearsal
if ($null -eq $rehearsal) { throw 'SAFETY BLOCK: Enforced recovery rehearsal evidence is missing.' }
if ([string]$rehearsal.environment -ne 'Enforced/ConstrainedLanguage') { throw 'SAFETY BLOCK: recovery rehearsal was not performed in Enforced/ConstrainedLanguage.' }
if ([string]$rehearsal.result -ne 'PASS') { throw 'SAFETY BLOCK: recovery rehearsal did not PASS.' }
if (-not [bool]$rehearsal.restores_exact_current_release) { throw 'SAFETY BLOCK: recovery rehearsal did not prove exact-current restoration.' }
if (-not [bool]$rehearsal.restores_pac_connectivity) { throw 'SAFETY BLOCK: recovery rehearsal did not prove PAC/connectivity restoration.' }
if (-not [bool]$rehearsal.base_remained_enforced) { throw 'SAFETY BLOCK: recovery rehearsal did not keep base Enforced.' }
if (-not [bool]$rehearsal.supplemental_remained_active) { throw 'SAFETY BLOCK: recovery rehearsal did not keep supplemental active.' }
if ([bool]$rehearsal.changes_base_to_audit) { throw 'SAFETY BLOCK: recovery rehearsal changes the base policy to Audit.' }
if ([int]$rehearsal.code_integrity_3077_blocks -ne 0) { throw 'SAFETY BLOCK: recovery rehearsal contains Code Integrity 3077 blocks.' }

Write-Host 'APL-WIN-014 enforced destructive readiness barrier: PASS'
Write-Host 'Static runtime packaging: PASS'
Write-Host 'Exact provisional policy promotion: PASS'
Write-Host 'Installer lifecycle trust coverage: PASS'
Write-Host 'Enforced recovery rehearsal: PASS'
Write-Host 'Code Integrity 3077 blocks: 0'
Write-Host 'Legacy ReferenceFullHash / PyInstaller onefile path: BLOCKED'
