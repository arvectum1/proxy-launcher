<# Authors, but never deploys, the V10.6.4 BootstrapHash supplemental policy. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$CandidateRoot = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'configci_xml_validation.ps1')
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$baseFriendlyName = 'Arvectum APL-WIN-014 Lab Base'
$policyFriendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
$policyVersion = '10.0.0.17'
if ([string]::IsNullOrWhiteSpace($CandidateRoot)) { throw 'CandidateRoot is required; this script never prompts.' }
if (-not (Test-Path -LiteralPath $CandidateRoot -PathType Container)) { throw "CandidateRoot not found: $CandidateRoot" }
function Get-Sha256([string]$Path) {
    $certUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
    if (-not (Test-Path -LiteralPath $certUtil -PathType Leaf)) { throw 'certutil.exe not found in System32.' }
    $output = & $certUtil -hashfile $Path SHA256
    if ($LASTEXITCODE -ne 0) { throw "certutil SHA256 failed for $Path" }
    $hashes = @($output | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' })
    if ($hashes.Count -ne 1) { throw "certutil SHA256 produced $($hashes.Count) hash candidates for $Path" }
    $hashes[0]
}
$hashes = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
foreach ($entry in @($hashes.files.setup, $hashes.files.application, $hashes.files.build_manifest, $hashes.files.upgrade_helper, $hashes.files.uninstall_helper, $hashes.files.candidate_evidence)) {
    $path = Join-Path $CandidateRoot $entry.filename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Sealed candidate file missing: $($entry.filename)" }
    if ((Get-Sha256 $path) -ine $entry.sha256) { throw "Sealed candidate hash mismatch: $($entry.filename)" }
}
foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy','CiTool.exe')) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" } }
$baseEvi = Get-ClmBasePolicyEvidence -ExpectedBasePolicyId $basePolicyIdText -ExpectedBaseFriendlyName $baseFriendlyName
Test-ClmBasePolicyInvariant -Policy $baseEvi.base -ExpectedPolicyId $basePolicyIdText -ExpectedBasePolicyId $basePolicyIdText -ExpectedFriendlyName $baseFriendlyName
$outDir = Join-Path $scriptDir ("v10.6.4-authoring-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$scanDir = Join-Path $outDir 'scan'
New-Item -ItemType Directory -Path $scanDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $CandidateRoot $hashes.files.setup.filename) -Destination $scanDir -Force
Copy-Item -LiteralPath (Join-Path $CandidateRoot $hashes.files.application.filename) -Destination $scanDir -Force
$xml = Join-Path $outDir 'Arvectum-APL-WIN-014-V10.6.4-Bootstrap.xml'
New-CIPolicy -MultiplePolicyFormat -ScanPath $scanDir -UserPEs -NoScript -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName $policyFriendlyName -SupplementsBasePolicyID $basePolicyIdText | Out-Null
Set-CIPolicyVersion -FilePath $xml -Version $policyVersion | Out-Null
$policyId = ''
foreach ($line in Get-Content -LiteralPath $xml -Encoding UTF8) { if ($line -match '<PolicyID>\s*([^<]+)\s*</PolicyID>') { $policyId = $matches[1] } }
if ($policyId -eq '') { throw 'Generated policy has no PolicyID.' }
Test-ConfigCiSupplementalXml -XmlPath $xml -PolicyId $policyId -BasePolicyId $basePolicyIdText -PolicyFriendlyName $policyFriendlyName -ExpectedPolicyVersion $policyVersion -ExpectedHashRuleFileNames @($hashes.files.application.filename, $hashes.files.setup.filename) | Out-Null
$cip = Join-Path $outDir (("{" + ($policyId -replace '[{}]','') + "}.cip"))
ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip
if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not create the binary supplemental policy.' }
$xmlSha256 = Get-Sha256 $xml
$cipSha256 = Get-Sha256 $cip
[ordered]@{
    schema='arvectum.proxy.apl-win-014-v10.6.4-bootstrap-authoring.v3'
    candidate_source_commit=$hashes.candidate_source_commit
    candidate_artifact_id=$hashes.candidate_artifact_id
    base_policy_id=$basePolicyIdText
    supplemental_policy_id=$policyId
    supplemental_policy_friendly_name=$policyFriendlyName
    supplemental_policy_version=$policyVersion
    supplemental_policy_xml=(Split-Path -Leaf $xml)
    supplemental_policy_xml_sha256=$xmlSha256
    supplemental_policy_cip=(Split-Path -Leaf $cip)
    supplemental_policy_cip_sha256=$cipSha256
    deployment='NOT PERFORMED'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8
"$(Get-Sha256 $xml)  $(Split-Path -Leaf $xml)`n$(Get-Sha256 $cip)  $(Split-Path -Leaf $cip)" | Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "AUTHORING COMPLETE: $outDir (deployment not performed)"
