<# Authors, but never deploys, the V10.7 ReferenceFullHash candidate policy. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$ReferenceCaptureDir = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'configci_xml_validation.ps1')
. (Join-Path $scriptDir 'checksum_validation.ps1')
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')
if ([string]::IsNullOrWhiteSpace($ReferenceCaptureDir)) { throw 'ReferenceCaptureDir is required; this script never prompts.' }
$capturePath = Join-Path $ReferenceCaptureDir 'reference-capture.json'
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw "Reference capture manifest not found: $capturePath" }
$capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
if ($capture.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v4') { throw "Reference capture schema is unexpected: $($capture.schema)." }
if ($capture.candidate_source_commit -ne $seal.candidate_source_commit -or $capture.candidate_artifact_id -ne $seal.candidate_artifact_id -or $capture.candidate_version -ne $seal.candidate_version) { throw 'Reference capture is not bound to the sealed V10.6.4 candidate.' }
if ((Convert-ClmPolicyGuidIdentity $capture.base_policy_id) -ine (Convert-ClmPolicyGuidIdentity $basePolicyIdText)) { throw 'Reference capture base_policy_id mismatch.' }
if ($capture.bootstrap_policy_friendly_name -ne $seal.bootstrap_policy_friendly_name) { throw 'Reference capture bootstrap friendly name mismatch.' }
if ($capture.bootstrap_policy_id -eq '') { throw 'Reference capture missing bootstrap_policy_id.' }
if ($capture.mandatory_repair_cache.filename -ne $seal.repair_cache_filename -or $capture.mandatory_repair_cache.sha256 -ine $seal.files.setup.sha256) { throw 'Reference capture mandatory repair evidence is incomplete.' }
foreach ($sealedFile in @($seal.files.application, $seal.files.build_manifest, $seal.files.upgrade_helper, $seal.files.uninstall_helper)) {
    if (@($capture.sealed_install_files | Where-Object { $_.filename -eq $sealedFile.filename -and $_.sha256 -ine $sealedFile.sha256 }).Count -ne 1 -or @($capture.files | Where-Object { $_.relative_path -eq $sealedFile.filename -and $_.sha256 -ine $sealedFile.sha256 }).Count -ne 1) { throw "Reference capture mandatory sealed file evidence is incomplete: $($sealedFile.filename)" }
}
if (-not ($capture.PSObject.Properties.Name -contains 'files') -or -not ($capture.PSObject.Properties.Name -contains 'unins000') -or -not ($capture.PSObject.Properties.Name -contains 'processes') -or -not ($capture.PSObject.Properties.Name -contains 'listeners') -or -not ($capture.PSObject.Properties.Name -contains 'wininet') -or -not ($capture.PSObject.Properties.Name -contains 'run_entries') -or -not ($capture.PSObject.Properties.Name -contains 'code_integrity') -or -not ($capture.PSObject.Properties.Name -contains 'policies')) { throw 'Reference capture missing required evidence fields.' }
$captureBaseOptions = @($capture.base_policy_options)
$hasSupplemental = $false
$hasAuditMode = $false
foreach ($opt in $captureBaseOptions) {
    if ($opt -eq 'Enabled:Allow Supplemental Policies') { $hasSupplemental = $true }
    if ($opt -eq 'Enabled:Audit Mode') { $hasAuditMode = $true }
}
if (-not $hasSupplemental) { throw 'Reference capture base policy missing Allow Supplemental Policies at capture time.' }
if ($hasAuditMode) { throw 'Reference capture base policy was in Audit Mode at capture time.' }
if ($capture.bootstrap_policy_enforced -ne $true -or $capture.bootstrap_policy_authorized -ne $true) { throw 'Reference capture bootstrap policy was not enforced/authorized at capture time.' }
if ($capture.PSObject.Properties.Name -contains 'policies' -and $capture.policies.PSObject.Properties.Name -contains 'bootstrap') {
    $bootOpts = @($capture.policies.bootstrap.policy_options)
    foreach ($opt in $bootOpts) { if ($opt -eq 'Enabled:Audit Mode') { throw 'Reference capture bootstrap policy options included Audit Mode.' } }
}
$checksumPath = Join-Path $ReferenceCaptureDir 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) { throw 'Reference capture checksum evidence is missing.' }
$checksumHash = Get-ChecksumEvidenceHash -ChecksumPath $checksumPath -ExpectedFileName 'reference-capture.json'
if (-not (Test-Path -LiteralPath $capture.install_root -PathType Container)) { throw 'Captured install root is not present.' }
$expectedApp = Get-Sha256 (Join-Path $capture.install_root $seal.files.application.filename)
if ($expectedApp -ine $seal.files.application.sha256) { throw 'Live application hash does not match V10.6.4 seal.' }
$expectedRepair = Get-Sha256 (Join-Path $capture.install_root $seal.repair_cache_filename)
if ($expectedRepair -ine $seal.files.setup.sha256) { throw 'Live repair cache hash does not match V10.6.4 seal.' }
foreach ($entry in @($seal.files.upgrade_helper, $seal.files.uninstall_helper, $seal.files.build_manifest)) {
    $liveHash = Get-Sha256 (Join-Path $capture.install_root $entry.filename)
    if ($liveHash -ine $entry.sha256) { throw "Live $($entry.filename) hash does not match V10.6.4 seal." }
}
$expectedInventory = @($capture.files | Sort-Object relative_path)
$liveInventory = @()
Get-ChildItem -LiteralPath $capture.install_root -File -Recurse -Force | Sort-Object FullName | ForEach-Object { $relativePath = Get-ClmRelativePath -BasePath $capture.install_root -FullPath $_.FullName; $liveInventory += [ordered]@{ relative_path=$relativePath; sha256=(Get-Sha256 $_.FullName); size=$_.Length; is_pe=($_.Extension -in @('.exe','.dll','.sys','.ocx')) } }
Compare-ClmInventory -Expected $expectedInventory -Live $liveInventory
$expectedPeNames = @($expectedInventory | Where-Object { $_.is_pe -eq $true } | ForEach-Object { Split-Path -Leaf $_.relative_path } | Sort-Object -Unique)
if ($expectedPeNames.Count -eq 0) { throw 'Reference inventory has no PE files for V10.7 policy authoring.' }
if ($expectedPeNames.Count -ne @($expectedInventory | Where-Object { $_.is_pe -eq $true }).Count) { throw 'Reference inventory has duplicate PE filenames that cannot be exactly bound in ConfigCI XML.' }
$captureHash = Get-Sha256 $capturePath
if ($captureHash -ine $checksumHash) { throw 'Reference capture manifest hash does not match its checksum evidence.' }
foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" } }
$outDir = Join-Path $scriptDir ("v10.7-authoring-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$xml = Join-Path $outDir 'Arvectum-APL-WIN-014-V10.7-FinalCandidate.xml'
New-CIPolicy -MultiplePolicyFormat -ScanPath $capture.install_root -UserPEs -NoScript -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName 'Arvectum APL-WIN-014 Harness V10.7 Final Candidate' -SupplementsBasePolicyID $basePolicyIdText | Out-Null
Set-CIPolicyVersion -FilePath $xml -Version '10.0.0.18' | Out-Null
$policyId = ''
foreach ($line in Get-Content -LiteralPath $xml -Encoding UTF8) { if ($line -match '<PolicyID>\s*([^<]+)\s*</PolicyID>') { $policyId = $matches[1] } }
if ($policyId -eq '') { throw 'Generated policy has no PolicyID.' }
Test-ConfigCiSupplementalXml -XmlPath $xml -PolicyId $policyId -BasePolicyId $basePolicyIdText -PolicyFriendlyName 'Arvectum APL-WIN-014 Harness V10.7 Final Candidate' -ExpectedPolicyVersion '10.0.0.18' -ExpectedHashRuleFileNames $expectedPeNames | Out-Null
$cip = Join-Path $outDir ("{" + ($policyId -replace '[{}]','') + "}.cip")
ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip
if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not create the binary policy.' }
[ordered]@{
    schema='arvectum.proxy.apl-win-014-v10.7-final-authoring.v2'
    candidate_source_commit=$seal.candidate_source_commit
    candidate_artifact_id=$seal.candidate_artifact_id
    reference_capture=(Split-Path -Leaf $capturePath)
    reference_capture_sha256=$captureHash
    base_policy_id=$basePolicyIdText
    supplemental_policy_id=$policyId
    supplemental_policy_friendly_name='Arvectum APL-WIN-014 Harness V10.7 Final Candidate'
    supplemental_policy_version='10.0.0.18'
    supplemental_policy_cip=(Split-Path -Leaf $cip)
    supplemental_policy_cip_sha256=(Get-Sha256 $cip)
    deployment='NOT PERFORMED'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8
Write-Host "V10.7 AUTHORING COMPLETE: $outDir (deployment not performed)"
