<#
.SYNOPSIS
    Fail-closed readiness barrier for destructive APL-WIN-014 Enforced acceptance.
.DESCRIPTION
    Real ARVECTUM-DEMO testing proved that an exact outer EXE hash is not enough for
    PyInstaller onefile or Inno Setup lifecycle execution under App Control for Business.

    This barrier intentionally blocks the legacy v0.2.3 ReferenceFullHash trust pack.
    It permits destructive enforced acceptance only when a newer trust-pack manifest
    explicitly proves a static runtime layout, complete installer lifecycle coverage,
    and a recovery rehearsal performed under the actual Enforced/ConstrainedLanguage
    environment.

    This script never deploys/removes/changes App Control policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TrustPackDirectory,

    [Parameter(Mandatory = $false)]
    [Guid]$ExpectedBasePolicyId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $TrustPackDirectory 'trust-pack.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "SAFETY BLOCK: App Control trust-pack manifest is missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# v1 / ReferenceFullHash is now known unsafe for destructive Enforced acceptance:
# it trusts the outer onefile EXE/reference installation tree but not the PyInstaller
# _MEI DLL/PYD runtime or Inno Setup temporary lifecycle helpers.
if ([string]$manifest.schema -eq 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v1') {
    throw 'SAFETY BLOCK: legacy trust-pack schema v1 is insufficient for Enforced lifecycle acceptance (ARVECTUM-DEMO incident / issue #10).'
}
if ([string]$manifest.mode -eq 'ReferenceFullHash') {
    throw 'SAFETY BLOCK: ReferenceFullHash alone is insufficient for Enforced lifecycle acceptance.'
}

if ([string]$manifest.schema -ne 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v2') {
    throw "SAFETY BLOCK: unsupported App Control trust-pack schema '$([string]$manifest.schema)'."
}
if ([string]$manifest.result -ne 'PASS') {
    throw 'SAFETY BLOCK: App Control trust pack is not a PASS record.'
}
if ([string]$manifest.packaging_layout -ne 'static-runtime') {
    throw 'SAFETY BLOCK: Enforced acceptance requires packaging_layout=static-runtime; PyInstaller onefile/_MEI is not accepted.'
}
if ([bool]$manifest.pyinstaller_onefile) {
    throw 'SAFETY BLOCK: PyInstaller onefile is prohibited for destructive Enforced acceptance.'
}
if (-not [bool]$manifest.runtime_complete) {
    throw 'SAFETY BLOCK: complete executable runtime coverage is not proven.'
}
if (-not [bool]$manifest.installer_lifecycle_complete) {
    throw 'SAFETY BLOCK: installer fresh/upgrade/repair/uninstall executable coverage is not proven.'
}
if (-not [bool]$manifest.enforced_lifecycle_ready) {
    throw 'SAFETY BLOCK: trust pack is not marked enforced_lifecycle_ready.'
}

if ($ExpectedBasePolicyId -ne [Guid]::Empty) {
    $actualBase = ([string]$manifest.base_policy_id).Trim().Trim('{}')
    $expectedBase = $ExpectedBasePolicyId.ToString('D')
    if ($actualBase -ine $expectedBase) {
        throw "SAFETY BLOCK: trust pack targets base '$actualBase', expected '$expectedBase'."
    }
}

$rehearsal = $manifest.recovery_rehearsal
if ($null -eq $rehearsal) {
    throw 'SAFETY BLOCK: Enforced recovery rehearsal evidence is missing.'
}
if ([string]$rehearsal.environment -ne 'Enforced/ConstrainedLanguage') {
    throw 'SAFETY BLOCK: recovery rehearsal was not performed in Enforced/ConstrainedLanguage.'
}
if ([string]$rehearsal.result -ne 'PASS') {
    throw 'SAFETY BLOCK: recovery rehearsal did not PASS.'
}
if (-not [bool]$rehearsal.restores_exact_current_release) {
    throw 'SAFETY BLOCK: recovery rehearsal did not prove exact-current restoration.'
}
if (-not [bool]$rehearsal.restores_pac_connectivity) {
    throw 'SAFETY BLOCK: recovery rehearsal did not prove PAC/connectivity restoration.'
}
if ([bool]$rehearsal.changes_base_to_audit) {
    throw 'SAFETY BLOCK: recovery rehearsal changes the base policy to Audit.'
}

Write-Host 'APL-WIN-014 enforced destructive readiness barrier: PASS'
Write-Host 'Static runtime packaging: PASS'
Write-Host 'Installer lifecycle trust coverage: PASS'
Write-Host 'Enforced recovery rehearsal: PASS'
Write-Host 'Legacy ReferenceFullHash / PyInstaller onefile path: BLOCKED'
