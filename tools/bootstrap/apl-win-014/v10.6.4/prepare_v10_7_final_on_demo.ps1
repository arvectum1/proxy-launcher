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
if ([string]::IsNullOrWhiteSpace($ReferenceCaptureDir)) { throw 'ReferenceCaptureDir is required; this script never prompts.' }
$capturePath = Join-Path $ReferenceCaptureDir 'reference-capture.json'
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw "Reference capture manifest not found: $capturePath" }
$capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
if ($capture.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v3' -or $capture.candidate_source_commit -ne $seal.candidate_source_commit -or $capture.candidate_artifact_id -ne $seal.candidate_artifact_id -or $capture.candidate_version -ne $seal.candidate_version -or $capture.base_policy_id -ne $basePolicyIdText -or $capture.bootstrap_policy_friendly_name -ne $seal.bootstrap_policy_friendly_name) { throw 'Reference capture is not bound to the sealed V10.6.4 candidate.' }
if ($capture.bootstrap_policy_id -eq '' -or $capture.mandatory_repair_cache.filename -ne $seal.repair_cache_filename -or $capture.mandatory_repair_cache.sha256 -ine $seal.files.setup.sha256) { throw 'Reference capture mandatory policy or repair evidence is incomplete.' }
foreach ($sealedFile in @($seal.files.application, $seal.files.build_manifest, $seal.files.upgrade_helper, $seal.files.uninstall_helper)) {
    if (@($capture.sealed_install_files | Where-Object { $_.filename -eq $sealedFile.filename -and $_.sha256 -ine $sealedFile.sha256 }).Count -ne 1 -or @($capture.files | Where-Object { $_.relative_path -eq $sealedFile.filename -and $_.sha256 -ine $sealedFile.sha256 }).Count -ne 1) { throw "Reference capture mandatory sealed file evidence is incomplete: $($sealedFile.filename)" }
}
$checksumPath = Join-Path $ReferenceCaptureDir 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) { throw 'Reference capture checksum evidence is missing.' }
$checksumHash = Get-ChecksumEvidenceHash -ChecksumPath $checksumPath -ExpectedFileName 'reference-capture.json'
if (-not (Test-Path -LiteralPath $capture.install_root -PathType Container)) { throw 'Captured install root is not present.' }
$expectedInventory = @($capture.files | Sort-Object relative_path)
$liveInventory = @()
Get-ChildItem -LiteralPath $capture.install_root -File -Recurse -Force | Sort-Object FullName | ForEach-Object { $relativePath = $_.FullName -replace ('^' + ($capture.install_root -replace '([\\(){}+.|^$])','\$1') + '\\?'), ''; $liveInventory += [ordered]@{ relative_path=$relativePath; sha256=(Get-Sha256 $_.FullName); size=$_.Length; is_pe=($_.Extension -in @('.exe','.dll','.sys','.ocx')) } }
if ($expectedInventory.Count -eq 0 -or $liveInventory.Count -ne $expectedInventory.Count) { throw 'Captured live installation tree no longer exactly matches the reference inventory.' }
for ($i = 0; $i -lt $expectedInventory.Count; $i++) {
    $expected = $expectedInventory[$i]; $live = $liveInventory[$i]
    if ($live.relative_path -ine $expected.relative_path -or $live.sha256 -ine $expected.sha256 -or "$($live.size)" -ne "$($expected.size)" -or "$($live.is_pe)" -ne "$($expected.is_pe)") { throw "Captured live installation tree drifted at index $i." }
}
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
[ordered]@{ schema='arvectum.proxy.apl-win-014-v10.7-final-authoring.v2'; candidate_source_commit=$seal.candidate_source_commit; candidate_artifact_id=$seal.candidate_artifact_id; reference_capture=(Split-Path -Leaf $capturePath); reference_capture_sha256=$captureHash; base_policy_id=$basePolicyIdText; supplemental_policy_id=$policyId; supplemental_policy_friendly_name='Arvectum APL-WIN-014 Harness V10.7 Final Candidate'; supplemental_policy_version='10.0.0.18'; supplemental_policy_cip=(Split-Path -Leaf $cip); supplemental_policy_cip_sha256=(Get-Sha256 $cip); deployment='NOT PERFORMED' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8
Write-Host "V10.7 AUTHORING COMPLETE: $outDir (deployment not performed)"
