<#
.SYNOPSIS
    Canonical completion wrapper for the APL-WIN-014 real enforced local gate.
.DESCRIPTION
    Final PASS is emitted only after a fail-closed readiness barrier and the canonical
    enforced acceptance prove BOTH:
      1. immutable historical 0.2.2 P0.4 -> exact current cross-version upgrade;
      2. exact current install/start/PAC/rollback/repair/uninstall lifecycle.

    The readiness barrier exists because real ARVECTUM-DEMO testing proved that the
    legacy v0.2.3 ReferenceFullHash / PyInstaller onefile trust model does not cover
    _MEI runtime DLL/PYD files or Inno Setup temporary lifecycle helpers. Destructive
    acceptance is therefore blocked until a v2 static-runtime trust pack and a real
    Enforced/ConstrainedLanguage recovery rehearsal are present.

    The wrapper is host-only acceptance tooling for a dedicated/isolated Windows 11
    physical acceptance host. It never deploys/removes App Control policy and never
    changes Smart App Control, Defender, or policy rule options.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [Guid]$BaselineSupplementalPolicyId,
    [Parameter(Mandatory = $true)] [string]$BaselineManifestPath,
    [Parameter(Mandatory = $true)] [string]$BaselineTrustPackDirectory,
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$TrustPackDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack',
    [string]$SigningEvidencePath = '',
    [string]$EvidenceDirectory = 'C:\Arvectum\Evidence\APL-WIN-014',
    [switch]$IsolatedAcceptanceEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsolatedAcceptanceEnvironment) {
    throw 'SAFETY BLOCK: final APL-WIN-014 acceptance is allowed only on the dedicated/isolated Windows 11 acceptance host.'
}

$canonical = Join-Path $PSScriptRoot 'windows_app_control_enforced_acceptance.ps1'
$helper = Join-Path $PSScriptRoot 'windows_app_control_preverified_release.ps1'
$readiness = Join-Path $PSScriptRoot 'windows_app_control_enforced_readiness.ps1'
foreach ($required in @($canonical,$helper,$readiness)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required canonical acceptance script is missing: $required"
    }
}

New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$final = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-final-local-gate.v4'
    task = 'APL-WIN-014'
    host = $env:COMPUTERNAME
    base_policy_id = $BasePolicyId.ToString('B')
    baseline_kind = 'LegacyClientZip'
    baseline_version = '0.2.2'
    current_version = '0.2.3+'
    started_utc = [DateTime]::UtcNow.ToString('o')
    result = 'BLOCK'
    readiness_gate = 'NOT_RUN'
    upgrade_gate = 'NOT_RUN'
    current_release_gate = 'NOT_RUN'
}

$gateError = $null
try {
    # Fail closed before any lifecycle mutation. The legacy v0.2.3 v1/ReferenceFullHash
    # trust pack is intentionally rejected after the ARVECTUM-DEMO incident.
    & $readiness -TrustPackDirectory $TrustPackDirectory -ExpectedBasePolicyId $BasePolicyId
    $final.readiness_gate = 'PASS'

    $args = @{
        BasePolicyId = $BasePolicyId
        BaselineSupplementalPolicyId = $BaselineSupplementalPolicyId
        BaselineManifestPath = $BaselineManifestPath
        BaselineTrustPackDirectory = $BaselineTrustPackDirectory
        ReleaseDirectory = $ReleaseDirectory
        CurrentTrustPackDirectory = $TrustPackDirectory
        EvidenceDirectory = $EvidenceDirectory
        IsolatedAcceptanceEnvironment = $true
    }
    if ($SigningEvidencePath) { $args.SigningEvidencePath = $SigningEvidencePath }

    & $canonical @args

    $evidencePath = Join-Path $EvidenceDirectory 'apl-win-014-enforced-result.json'
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        throw 'Canonical enforced acceptance evidence is missing.'
    }
    $gate = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$gate.result -ne 'PASS') { throw 'Canonical enforced acceptance did not PASS.' }
    if ([string]$gate.upgrade_gate -ne 'PASS') { throw 'Real cross-version upgrade sub-gate did not PASS.' }
    if ([string]$gate.current_release_gate -ne 'PASS') { throw 'Exact current-release lifecycle sub-gate did not PASS.' }
    if ([int]$gate.arvectum_3077_block_events -ne 0) { throw 'Canonical evidence contains Arvectum 3077 enforcement blocks.' }

    $final.upgrade_gate = 'PASS'
    $final.current_release_gate = 'PASS'
    $final.canonical_evidence = $evidencePath
    $final.result = 'PASS'
}
catch {
    $gateError = $_
    $final.block_reason = [string]$_.Exception.Message
}
finally {
    $final.finished_utc = [DateTime]::UtcNow.ToString('o')
    $finalPath = Join-Path $EvidenceDirectory 'apl-win-014-final-result.json'
    $final | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $finalPath -Encoding UTF8
    Write-Host "Final evidence: $finalPath"
}

if ($final.result -ne 'PASS') {
    if ($gateError) { throw $gateError }
    throw 'APL-WIN-014 real App Control for Business local gate: BLOCK'
}

Write-Host 'APL-WIN-014 real App Control for Business local gate: PASS'
Write-Host 'Enforced destructive readiness: PASS'
Write-Host 'Cross-version upgrade: PASS'
Write-Host 'Historical 0.2.2 P0.4 -> exact current cross-version upgrade: PASS'
Write-Host 'Exact current lifecycle: PASS'
Write-Host 'Windows App Control remained enforced: PASS'
