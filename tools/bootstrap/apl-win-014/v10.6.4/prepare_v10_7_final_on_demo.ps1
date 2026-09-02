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
if ([string]::IsNullOrWhiteSpace($ReferenceCaptureDir)) { throw 'ReferenceCaptureDir is required; this script never prompts.' }
$capturePath = Join-Path $ReferenceCaptureDir 'reference-capture.json'
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw "Reference capture manifest not found: $capturePath" }
$capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
if ($capture.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v2' -or $capture.candidate_source_commit -ne $seal.candidate_source_commit -or $capture.candidate_artifact_id -ne $seal.candidate_artifact_id) { throw 'Reference capture is not bound to the sealed V10.6.4 candidate.' }
if (-not (Test-Path -LiteralPath (Join-Path $ReferenceCaptureDir 'SHA256SUMS.txt') -PathType Leaf)) { throw 'Reference capture checksum evidence is missing.' }
if ((Get-Content -LiteralPath (Join-Path $ReferenceCaptureDir 'SHA256SUMS.txt') -Raw).Trim() -notmatch '^[0-9A-Fa-f]{64}\s\sreference-capture\.json$') { throw 'Reference capture checksum evidence is malformed.' }
if (-not (Test-Path -LiteralPath $capture.install_root -PathType Container)) { throw 'Captured install root is not present.' }
$expectedInventory = @($capture.files | Sort-Object relative_path)
$liveInventory = @()
Get-ChildItem -LiteralPath $capture.install_root -File -Recurse -Force | Sort-Object FullName | ForEach-Object { $liveInventory += [ordered]@{ relative_path=$_.FullName.Substring($capture.install_root.TrimEnd('\').Length).TrimStart('\'); sha256=(Get-Sha256 $_.FullName); size=$_.Length; is_pe=($_.Extension -in @('.exe','.dll','.sys','.ocx')) } }
if ($expectedInventory.Count -eq 0 -or $liveInventory.Count -ne $expectedInventory.Count) { throw 'Captured live installation tree no longer exactly matches the reference inventory.' }
for ($i = 0; $i -lt $expectedInventory.Count; $i++) {
    $expected = $expectedInventory[$i]; $live = $liveInventory[$i]
    if ($live.relative_path -ine $expected.relative_path -or $live.sha256 -ine $expected.sha256 -or [int64]$live.size -ne [int64]$expected.size -or [bool]$live.is_pe -ne [bool]$expected.is_pe) { throw "Captured live installation tree drifted at index $i." }
}
$expectedPeNames = @($expectedInventory | Where-Object { $_.is_pe -eq $true } | ForEach-Object { Split-Path -Leaf $_.relative_path } | Sort-Object -Unique)
if ($expectedPeNames.Count -eq 0) { throw 'Reference inventory has no PE files for V10.7 policy authoring.' }
if ($expectedPeNames.Count -ne @($expectedInventory | Where-Object { $_.is_pe -eq $true }).Count) { throw 'Reference inventory has duplicate PE filenames that cannot be exactly bound in ConfigCI XML.' }
$captureHash = Get-Sha256 $capturePath
if ($captureHash -ine ((Get-Content -LiteralPath (Join-Path $ReferenceCaptureDir 'SHA256SUMS.txt') -Raw).Trim().Split()[0])) { throw 'Reference capture manifest hash does not match its checksum evidence.' }
foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" } }
$outDir = Join-Path $scriptDir ("v10.7-authoring-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$xml = Join-Path $outDir 'Arvectum-APL-WIN-014-V10.7-FinalCandidate.xml'
New-CIPolicy -MultiplePolicyFormat -ScanPath $capture.install_root -UserPEs -NoScript -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName 'Arvectum APL-WIN-014 Harness V10.7 Final Candidate' -SupplementsBasePolicyID ([guid]$basePolicyIdText) | Out-Null
Set-CIPolicyVersion -FilePath $xml -Version '10.0.0.18' | Out-Null
$policyId = (Select-String -Path $xml -Pattern '<PolicyID>\s*([^<]+)\s*</PolicyID>' | Select-Object -First 1).Matches.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($policyId)) { throw 'Generated policy has no PolicyID.' }
Test-ConfigCiSupplementalXml -XmlPath $xml -PolicyId $policyId -BasePolicyId $basePolicyIdText -PolicyFriendlyName 'Arvectum APL-WIN-014 Harness V10.7 Final Candidate' -ExpectedHashRuleFileNames $expectedPeNames | Out-Null
$cip = Join-Path $outDir ("{" + ($policyId -replace '[{}]','') + "}.cip")
ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip
if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not create the binary policy.' }
[ordered]@{ schema='arvectum.proxy.apl-win-014-v10.7-final-authoring.v1'; candidate_source_commit=$seal.candidate_source_commit; reference_capture=(Split-Path -Leaf $capturePath); supplemental_policy_id=$policyId; deployment='NOT PERFORMED' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8
Write-Host "V10.7 AUTHORING COMPLETE: $outDir (deployment not performed)"
