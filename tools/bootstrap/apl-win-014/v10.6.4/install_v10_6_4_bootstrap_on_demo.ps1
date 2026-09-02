<# Deploys an explicitly supplied V10.6.4 CIP after its identity is checked. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$CipPath = '', [string]$ExpectedCipSha256 = '', [string]$PolicyId = '', [string]$AuthoringEvidencePath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$friendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if ([string]::IsNullOrWhiteSpace($CipPath) -or [string]::IsNullOrWhiteSpace($ExpectedCipSha256) -or [string]::IsNullOrWhiteSpace($PolicyId) -or [string]::IsNullOrWhiteSpace($AuthoringEvidencePath)) { throw 'CipPath, ExpectedCipSha256, PolicyId, and AuthoringEvidencePath are required; this script never prompts.' }
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
if (-not (Test-Path -LiteralPath $CipPath -PathType Leaf)) { throw "CIP not found: $CipPath" }
if (-not (Test-Path -LiteralPath $AuthoringEvidencePath -PathType Leaf)) { throw "Authoring evidence not found: $AuthoringEvidencePath" }
$authoring = Get-Content -LiteralPath $AuthoringEvidencePath -Raw | ConvertFrom-Json
$expectedXmlFilename = $authoring.supplemental_policy_xml
$expectedXmlSha256 = $authoring.supplemental_policy_xml_sha256
$expectedCipFilename = $authoring.supplemental_policy_cip
$expectedCipSha256Evidence = $authoring.supplemental_policy_cip_sha256
if ($authoring.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-bootstrap-authoring.v3' -or $authoring.base_policy_id -ne $basePolicyIdText -or $authoring.supplemental_policy_id -ne $PolicyId -or $authoring.supplemental_policy_friendly_name -ne $friendlyName -or $authoring.supplemental_policy_version -ne '10.0.0.17' -or $authoring.deployment -ne 'NOT PERFORMED') { throw 'Authoring evidence does not exactly bind the requested deployment.' }
if ($expectedCipFilename -ne (Split-Path -Leaf $CipPath)) { throw 'Authoring evidence CIP filename does not match supplied CIP.' }
if ((Get-Sha256 $CipPath) -ine $ExpectedCipSha256) { throw 'CIP hash mismatch.' }
if ($expectedCipSha256Evidence -ine $ExpectedCipSha256) { throw 'Authoring evidence CIP hash does not match the requested deployment.' }
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
$xmlPath = Join-Path (Split-Path -Parent $AuthoringEvidencePath) $expectedXmlFilename
if (Test-Path -LiteralPath $xmlPath -PathType Leaf) {
    $xmlSha256Actual = Get-Sha256 $xmlPath
    if ($xmlSha256Actual -ine $expectedXmlSha256) { throw 'XML SHA256 does not match authoring evidence.' }
} else {
    if ($expectedXmlSha256 -ne '') { throw 'Authoring evidence references XML but file not found.' }
}
$before = & CiTool.exe -lp -json 2>$null | ConvertFrom-Json
$base = @($before.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText })
if ($before.OperationResult -ne 0 -or $base.Count -ne 1 -or $base[0].BasePolicyID -ne $basePolicyIdText -or $base[0].FriendlyName -ne 'Arvectum APL-WIN-014 Lab Base' -or $base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true -or @($base[0].PolicyOptions | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base validation failed closed.' }
Test-ClmAuditModeRejection -PolicyOptions @($base[0].PolicyOptions) -PolicyLabel 'Canonical Lab Base pre-deploy'
& CiTool.exe --update-policy $CipPath
if ($LASTEXITCODE -ne 0) { throw "CiTool --update-policy failed with exit code $LASTEXITCODE" }
Start-Sleep -Seconds 3
$after = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$deployed = @($after.Policies | Where-Object { $_.PolicyID -eq $PolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq $friendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($after.OperationResult -ne 0 -or $deployed.Count -ne 1) { throw 'V10.6.4 Bootstrap was not uniquely active after deployment.' }
Write-Host "DEPLOYMENT COMPLETE: $PolicyId"
