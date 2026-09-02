<# Authors, but never deploys, the V10.7 ReferenceFullHash candidate policy. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$ReferenceCaptureDir = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ReferenceCaptureDir)) { throw 'ReferenceCaptureDir is required; this script never prompts.' }
$capturePath = Join-Path $ReferenceCaptureDir 'reference-capture.json'
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw "Reference capture manifest not found: $capturePath" }
$capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
if ($capture.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v1' -or $capture.candidate_source_commit -ne $seal.candidate_source_commit -or $capture.candidate_artifact_id -ne $seal.candidate_artifact_id) { throw 'Reference capture is not bound to the sealed V10.6.4 candidate.' }
if (-not (Test-Path -LiteralPath $capture.install_root -PathType Container)) { throw 'Captured install root is not present.' }
foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" } }
$outDir = Join-Path $scriptDir ("v10.7-authoring-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$xml = Join-Path $outDir 'Arvectum-APL-WIN-014-V10.7-FinalCandidate.xml'
New-CIPolicy -MultiplePolicyFormat -ScanPath $capture.install_root -UserPEs -NoScript -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName 'Arvectum APL-WIN-014 Harness V10.7 Final Candidate' -SupplementsBasePolicyID ([guid]$basePolicyIdText) | Out-Null
Set-CIPolicyVersion -FilePath $xml -Version '10.0.0.18' | Out-Null
$policyId = (Select-String -Path $xml -Pattern '<PolicyID>\s*([^<]+)\s*</PolicyID>' | Select-Object -First 1).Matches.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($policyId)) { throw 'Generated policy has no PolicyID.' }
$cip = Join-Path $outDir ("{" + ($policyId -replace '[{}]','') + "}.cip")
ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip
if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not create the binary policy.' }
[ordered]@{ schema='arvectum.proxy.apl-win-014-v10.7-final-authoring.v1'; candidate_source_commit=$seal.candidate_source_commit; reference_capture=(Split-Path -Leaf $capturePath); supplemental_policy_id=$policyId; deployment='NOT PERFORMED' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8
Write-Host "V10.7 AUTHORING COMPLETE: $outDir (deployment not performed)"
