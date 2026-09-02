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
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
if ($authoring.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-bootstrap-authoring.v3') { throw 'Authoring evidence schema mismatch.' }
if ($authoring.candidate_source_commit -ne $seal.candidate_source_commit) { throw ('Authoring candidate_source_commit mismatch: expected {0} got {1}.' -f $seal.candidate_source_commit, $authoring.candidate_source_commit) }
if ($authoring.candidate_artifact_id -ne $seal.candidate_artifact_id) { throw ('Authoring candidate_artifact_id mismatch: expected {0} got {1}.' -f $seal.candidate_artifact_id, $authoring.candidate_artifact_id) }
if ((Convert-ClmPolicyGuidIdentity $authoring.base_policy_id) -ine (Convert-ClmPolicyGuidIdentity $basePolicyIdText)) { throw 'Authoring base_policy_id mismatch.' }
if ((Convert-ClmPolicyGuidIdentity $authoring.supplemental_policy_id) -ine (Convert-ClmPolicyGuidIdentity $PolicyId)) { throw 'Authoring supplemental_policy_id mismatch.' }
if ($authoring.supplemental_policy_friendly_name -ne $friendlyName) { throw 'Authoring supplemental_policy_friendly_name mismatch.' }
if ($authoring.supplemental_policy_version -ne '10.0.0.17') { throw 'Authoring supplemental_policy_version mismatch.' }
if ($authoring.deployment -ne 'NOT PERFORMED') { throw 'Authoring evidence deployment state is not NOT PERFORMED.' }
$expectedXmlFilename = $authoring.supplemental_policy_xml
$expectedXmlSha256 = $authoring.supplemental_policy_xml_sha256
$expectedCipFilename = $authoring.supplemental_policy_cip
$expectedCipSha256Evidence = $authoring.supplemental_policy_cip_sha256
if ($expectedCipFilename -ne (Split-Path -Leaf $CipPath)) { throw 'Authoring evidence CIP filename does not match supplied CIP.' }
if ((Get-Sha256 $CipPath) -ine $ExpectedCipSha256) { throw 'CIP hash mismatch.' }
if ($expectedCipSha256Evidence -ine $ExpectedCipSha256) { throw 'Authoring evidence CIP hash does not match the requested deployment.' }
$xmlPath = Join-Path (Split-Path -Parent $AuthoringEvidencePath) $expectedXmlFilename
if (Test-Path -LiteralPath $xmlPath -PathType Leaf) {
    $xmlSha256Actual = Get-Sha256 $xmlPath
    if ($xmlSha256Actual -ine $expectedXmlSha256) { throw 'XML SHA256 does not match authoring evidence.' }
} else {
    if ($expectedXmlSha256 -ne '') { throw 'Authoring evidence references XML but file not found.' }
}
$before = & CiTool.exe -lp -json 2>$null | ConvertFrom-Json
$baseEvidence = Resolve-ClmPolicyEvidence -CiToolResult $before -ExpectedBasePolicyId $basePolicyIdText -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -RequireBootstrap $false
$base = @($baseEvidence.base)
if ($base.Count -ne 1 -or @($base[0].policy_options | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base validation failed closed.' }
Test-ClmAuditModeRejection -PolicyOptions @($base[0].policy_options) -PolicyLabel 'Canonical Lab Base pre-deploy'
& CiTool.exe --update-policy $CipPath
if ($LASTEXITCODE -ne 0) { throw "CiTool --update-policy failed with exit code $LASTEXITCODE" }
Start-Sleep -Seconds 3
$after = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$afterEvidence = Resolve-ClmPolicyEvidence -CiToolResult $after -ExpectedBasePolicyId $basePolicyIdText -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -ExpectedBootstrapPolicyId $PolicyId -ExpectedBootstrapFriendlyName $friendlyName
$deployed = @($afterEvidence.bootstrap)
if ($deployed.Count -ne 1) { throw 'V10.6.4 Bootstrap was not uniquely active after deployment.' }
Write-Host "DEPLOYMENT COMPLETE: $PolicyId"
