<#
.SYNOPSIS
    Generate the exact App Control supplemental trust pack for the recovered 0.2.2 P0.4 baseline.
.DESCRIPTION
    Consumes only a PASS manifest emitted by windows_app_control_recover_0_2_2_baseline.ps1,
    re-verifies the immutable historical identity and every recovered file hash, then creates
    a hash-only supplemental App Control policy for the exact legacy package tree.

    This script does NOT deploy, remove, disable, weaken or otherwise mutate App Control policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$BaselineManifestPath,
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [string]$OutputDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\baseline-trust-pack'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedRecoverySchema = 'arvectum.proxy.apl-win-014-baseline-recovery.v1'
$ExpectedCommit = '0ea08d9c815da36d0175f62db153de78f89731fc'
$ExpectedPath = 'release/Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip'
$ExpectedBlobSha1 = '574d3dc5f90a116555e3a72ff3288c31c19d3dc7'
$ExpectedBlobSize = 15963815
$ExpectedVersion = '0.2.2'
$ExpectedApplicationSha256 = '7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required Windows command/cmdlet is unavailable: $Name" }
}

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim().Trim('{}')
    try { return ([Guid]$text).ToString('D').ToLowerInvariant() } catch { return $text.ToLowerInvariant() }
}

function Get-PolicyIdFromXml([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, '<PolicyID>\s*([^<]+)\s*</PolicyID>', 'IgnoreCase')
    if (-not $match.Success) { throw 'Generated App Control policy has no PolicyID.' }
    return $match.Groups[1].Value.Trim()
}

if ($env:OS -ne 'Windows_NT') { throw 'Baseline App Control trust-pack generation must run on Windows.' }
foreach ($cmd in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) { Assert-Command $cmd }

$BaselineManifestPath = (Resolve-Path -LiteralPath $BaselineManifestPath).Path
$baseline = Get-Content -LiteralPath $BaselineManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$baseline.schema -ne $ExpectedRecoverySchema -or [string]$baseline.result -ne 'PASS') { throw 'Baseline recovery manifest is not a PASS record of the expected schema.' }
if ([string]$baseline.source.repository -ne 'arvectum1/proxy-launcher') { throw 'Recovered baseline names another repository.' }
if ([string]$baseline.source.commit -ne $ExpectedCommit) { throw 'Recovered baseline commit identity mismatch.' }
if ([string]$baseline.source.path -ne $ExpectedPath) { throw 'Recovered baseline Git path mismatch.' }
if ([string]$baseline.source.git_blob_sha1 -ne $ExpectedBlobSha1) { throw 'Recovered baseline Git blob mismatch.' }
if ([long]$baseline.source.git_blob_size -ne $ExpectedBlobSize) { throw 'Recovered baseline Git blob size mismatch.' }
if ([string]$baseline.baseline.kind -ne 'LegacyClientZip') { throw 'Recovered baseline is not the governed LegacyClientZip kind.' }
if ([string]$baseline.baseline.version -ne $ExpectedVersion) { throw 'Recovered baseline version mismatch.' }
if (([string]$baseline.baseline.application_exe_sha256).ToLowerInvariant() -ne $ExpectedApplicationSha256) { throw 'Recovered baseline application hash mismatch.' }

$packageZip = (Resolve-Path -LiteralPath ([string]$baseline.baseline.package_zip)).Path
$packageDirectory = (Resolve-Path -LiteralPath ([string]$baseline.baseline.package_directory)).Path
if ((Get-Sha256 $packageZip) -ne ([string]$baseline.baseline.package_sha256).ToLowerInvariant()) { throw 'Recovered baseline package ZIP SHA256 no longer matches its manifest.' }

$manifestFiles = @($baseline.files)
if ($manifestFiles.Count -eq 0) { throw 'Recovered baseline manifest has no file inventory.' }
foreach ($record in $manifestFiles) {
    $full = Join-Path $packageDirectory ([string]$record.relative_path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Recovered baseline file is missing: $($record.relative_path)" }
    if ([long](Get-Item -LiteralPath $full).Length -ne [long]$record.size) { throw "Recovered baseline file size mismatch: $($record.relative_path)" }
    if ((Get-Sha256 $full) -ne ([string]$record.sha256).ToLowerInvariant()) { throw "Recovered baseline file SHA256 mismatch: $($record.relative_path)" }
}

$appExe = Join-Path $packageDirectory ([string]$baseline.baseline.application_relative_path)
if ((Get-Sha256 $appExe) -ne $ExpectedApplicationSha256) { throw 'Recovered baseline application EXE is not the exact governed P0.4 binary.' }

if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory already exists; refusing to overwrite a prior baseline trust pack: $OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$policyXml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-0.2.2-P0.4-AppControl-Supplemental.xml'
$policyName = 'Arvectum Proxy Launcher 0.2.2 P0.4 Exact Hash'
Write-Host '=== Generating exact-hash baseline App Control policy ==='
New-CIPolicy -MultiplePolicyFormat -ScanPath $packageDirectory -UserPEs -NoScript -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null
Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName $policyName -SupplementsBasePolicyID $BasePolicyId | Out-Null
Set-CIPolicyVersion -FilePath $policyXml -Version '0.2.2.4'

$policyId = Get-PolicyIdFromXml $policyXml
$policyFileSafe = $policyId.Trim('{}')
$policyCip = Join-Path $OutputDirectory ("{$policyFileSafe}.cip")
ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) { throw 'ConfigCI did not create the binary baseline supplemental policy.' }

$trust = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-baseline-trust-pack.v1'
    task = 'APL-WIN-014'
    created_utc = [DateTime]::UtcNow.ToString('o')
    mode = 'LegacyPackageExactHash'
    base_policy_id = $BasePolicyId.ToString('B')
    supplemental_policy_id = $policyId
    supplemental_policy_xml = [IO.Path]::GetFileName($policyXml)
    supplemental_policy_cip = [IO.Path]::GetFileName($policyCip)
    baseline = [ordered]@{
        version = $ExpectedVersion
        source_commit = $ExpectedCommit
        source_path = $ExpectedPath
        git_blob_sha1 = $ExpectedBlobSha1
        git_blob_size = $ExpectedBlobSize
        package_sha256 = ([string]$baseline.baseline.package_sha256).ToLowerInvariant()
        application_exe_sha256 = $ExpectedApplicationSha256
        recovery_manifest_sha256 = Get-Sha256 $BaselineManifestPath
    }
    policy_scope = 'exact executable/script/package bytes in the recovered historical 0.2.2 P0.4 customer package tree'
    deployment_invariants = @(
        'pack generation never deploys App Control policy',
        'base policy must allow supplemental policies',
        'Smart App Control and App Control for Business must not be disabled as a workaround',
        'hash trust is exact-byte trust and covers only the recovered P0.4 package bytes',
        'baseline was recovered from immutable Git history and was not rebuilt'
    )
    result = 'PASS'
}
$trustPath = Join-Path $OutputDirectory 'trust-pack.json'
$trust | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $trustPath -Encoding UTF8

$deployment = @"
APL-WIN-014 - HISTORICAL 0.2.2 P0.4 BASELINE TRUST PACK
========================================================

Baseline: 0.2.2 P0.4
Source commit: $ExpectedCommit
Source Git blob: $ExpectedBlobSha1
Base policy ID: $($BasePolicyId.ToString('B'))
Supplemental policy ID: $policyId

This pack DOES NOT deploy itself and DOES NOT weaken App Control.
Deploy the generated .cip only through the approved lab/customer App Control management path.
The policy is exact-hash trust for the immutable recovered historical package tree.
Do not rebuild, rename-by-substitution, or replace the 0.2.2 baseline with a same-version 0.2.3 artifact.
"@
Set-Content -LiteralPath (Join-Path $OutputDirectory 'DEPLOYMENT.txt') -Value $deployment -Encoding UTF8

$checksums = @(Get-ChildItem -LiteralPath $OutputDirectory -File | Sort-Object Name | ForEach-Object { "$(Get-Sha256 $_.FullName)  $($_.Name)" })
Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

Write-Host 'APL-WIN-014 0.2.2 P0.4 baseline trust pack: PASS'
Write-Host "Policy ID: $policyId"
Write-Host "Output: $OutputDirectory"
Write-Host 'Deployment: NOT PERFORMED'
