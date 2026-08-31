<#
.SYNOPSIS
    Author V10.7 Final Candidate lifecycle policy on ARVECTUM-DEMO (authoring only, CLM-safe).
.DESCRIPTION
    Generates a ReferenceFullHash supplemental policy covering the complete installed
    0.2.4 tree including generated unins000.exe. Requires the reference capture from
    capture_v10_6_1_post_install_reference.ps1. Does NOT deploy.
    Written for Windows PowerShell 5.1 ConstrainedLanguage mode.
    V10.6.1: Fixed real CiTool schema (PolicyID, not policy_id).
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string]$ReferenceCaptureDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$BasePolicyId = [guid]$BasePolicyIdText
$PolicyFriendlyName = 'Arvectum APL-WIN-014 Harness V10.7 Final Candidate'
$PolicyVersion = '10.0.0.17'
$CandidateVersion = '0.2.4'

$ExpectedSetupHash = '7b9e7b95b0c26a028ed903ba7281a60dfd83c190ebdcf1208c05c1f687450389'
$ExpectedAppHash   = '0f275a8ab6d1640e3c392308c6ae4af4f613fc2750c62df7f173300eb0e0e447'

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-PolicyIdFromXml {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -match '<PolicyID>\s*([^<]+)\s*</PolicyID>') {
        return $matches[1]
    }
    throw 'Generated policy has no PolicyID.'
}

$c = Get-Command New-CIPolicy -ErrorAction SilentlyContinue
if (-not $c) { throw 'Required command not found: New-CIPolicy' }
$c = Get-Command Set-CIPolicyIdInfo -ErrorAction SilentlyContinue
if (-not $c) { throw 'Required command not found: Set-CIPolicyIdInfo' }
$c = Get-Command Set-CIPolicyVersion -ErrorAction SilentlyContinue
if (-not $c) { throw 'Required command not found: Set-CIPolicyVersion' }
$c = Get-Command ConvertFrom-CIPolicy -ErrorAction SilentlyContinue
if (-not $c) { throw 'Required command not found: ConvertFrom-CIPolicy' }
$c = Get-Command CiTool.exe -ErrorAction SilentlyContinue
if (-not $c) { throw 'Required command not found: CiTool.exe' }

if (-not (Test-Path -LiteralPath $ReferenceCaptureDir -PathType Container)) { throw "Reference capture directory not found: $ReferenceCaptureDir" }
$captureManifest = Join-Path $ReferenceCaptureDir 'reference-capture.json'
if (-not (Test-Path -LiteralPath $captureManifest -PathType Leaf)) { throw "Reference capture manifest not found: $captureManifest" }
$capture = Get-Content -LiteralPath $captureManifest -Raw | ConvertFrom-Json
$installRoot = "$($capture.install_root)"
if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) { throw "Install root not found: $installRoot" }

$documents = "$env:USERPROFILE\Documents"
$expectedRoot = Join-Path $documents 'ArvectumProxyLauncher'
if ($installRoot -ne $expectedRoot) { throw "Install root differs from expected: $installRoot != $expectedRoot" }

Write-Host '=== Querying CiTool (real schema) ==='
$raw = & CiTool.exe -lp -json 2>$null
$policies = $raw | ConvertFrom-Json

if ($null -eq $policies.OperationResult) { throw 'CiTool output missing OperationResult. FAIL CLOSED.' }
if ($policies.OperationResult -ne 0) { throw "CiTool OperationResult=$($policies.OperationResult). FAIL CLOSED." }
Write-Host "  OperationResult: $($policies.OperationResult)"

$base = @($policies.Policies | Where-Object { $_.PolicyID -eq $BasePolicyIdText })
if ($base.Count -ne 1) { throw "Lab Base policy not found: $BasePolicyIdText. FAIL CLOSED." }
$b = $base[0]
if ($b.IsOnDisk -ne $true) { throw 'Lab Base is not on-disk. FAIL CLOSED.' }
if ($b.IsEnforced -ne $true) { throw 'Lab Base is not enforced. FAIL CLOSED.' }
Write-Host "  Base PolicyID: $($b.PolicyID) IsOnDisk=$($b.IsOnDisk) IsEnforced=$($b.IsEnforced)"

Write-Host ''
Write-Host '=== Verifying reference installation ==='
$exe = Join-Path $installRoot 'Arvectum Proxy Launcher.exe'
$repair = Join-Path $installRoot 'Arvectum Proxy Launcher Repair.exe'
$uninstaller = Join-Path $installRoot 'unins000.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Installed application EXE is missing.' }
if (-not (Test-Path -LiteralPath $repair -PathType Leaf)) { throw 'Cached repair setup is missing.' }
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { throw 'Generated unins000.exe is missing.' }
if ((Get-Sha256 $exe) -ne $ExpectedAppHash) { throw 'Installed EXE hash mismatch.' }
if ((Get-Sha256 $repair) -ne $ExpectedSetupHash) { throw 'Cached repair setup hash mismatch.' }

$unHash = Get-Sha256 $uninstaller
Write-Host "  Application EXE: $(Get-Sha256 $exe)"
Write-Host "  Cached Repair:   $(Get-Sha256 $repair)"
Write-Host "  unins000.exe:    $unHash"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $scriptDir "v10.7-authoring-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$stagingDir = Join-Path $outDir 'scan'
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $scriptDir 'Arvectum-Proxy-Launcher-0.2.4-windows-x64-setup.exe') -Destination $stagingDir -Force
Copy-Item -LiteralPath $exe -Destination (Join-Path $stagingDir 'Arvectum Proxy Launcher.exe') -Force

$referenceStage = Join-Path $stagingDir 'installed-reference-tree'
Copy-Item -LiteralPath $installRoot -Destination $referenceStage -Recurse -Force

$referenceFiles = @()
Get-ChildItem -LiteralPath $installRoot -File -Recurse -Force | ForEach-Object {
    $rootEscaped = "$installRoot\" -replace '([\\(){}+.|^$])','\$1'
    $rel = $_.FullName -replace ("^" + $rootEscaped + "(.+)"), '$1'
    $hash = Get-Sha256 $_.FullName
    $referenceFiles += [ordered]@{
        relative_path = $rel
        sha256 = $hash
        size = $_.Length
    }
    Write-Host "  $rel  $hash  $($_.Length)"
}

Write-Host ''
Write-Host '=== Generating V10.7 Final Candidate lifecycle policy ==='
$policyXml = Join-Path $outDir 'Arvectum-APL-WIN-014-V10.7-FinalCandidate.xml'
New-CIPolicy -MultiplePolicyFormat -ScanPath $stagingDir -UserPEs -NoScript -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null

Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName $PolicyFriendlyName -SupplementsBasePolicyID $BasePolicyId | Out-Null
Set-CIPolicyVersion -FilePath $policyXml -Version $PolicyVersion | Out-Null

$policyId = Get-PolicyIdFromXml $policyXml
$policyFileSafe = $policyId -replace '[{}]',''
$policyCip = Join-Path $outDir ("{$policyFileSafe}.cip")
ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) { throw 'ConfigCI did not create the binary supplemental policy.' }

Write-Host ''
Write-Host "PolicyID:       $policyId"
Write-Host "BasePolicyID:   $BasePolicyIdText"
Write-Host "FriendlyName:   $PolicyFriendlyName"
Write-Host "Version:        $PolicyVersion"
Write-Host "XML SHA256:     $(Get-Sha256 $policyXml)"
Write-Host "CIP SHA256:     $(Get-Sha256 $policyCip)"

Write-Host ''
Write-Host '=== Static verification ==='
$xmlText = Get-Content -LiteralPath $policyXml -Raw -Encoding UTF8
if ($xmlText -notmatch $policyId) { throw 'PolicyID not found in XML.' }
if ($xmlText -notmatch 'dc1c604c-46ea-40b7-9f47-cf582b225d5e') { throw 'BasePolicyID not found in XML.' }
if (-not ($xmlText -clike "*$PolicyFriendlyName*")) { throw 'FriendlyName not found in XML.' }
if ($xmlText -notmatch $PolicyVersion) { throw 'Version not found in XML.' }
Write-Host '  PolicyID/BasePolicyID/FriendlyName/Version: PASS'

Write-Host ''
Write-Host '=== V10.7 lifecycle hash rules ==='
$hashRules = Select-String -Path $policyXml -Pattern '<Allow Type="Hash"' | ForEach-Object { $_.Line -replace '^\s+|\s+$','' }
$hashRules | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host "Rule count: $($hashRules.Count)"

$evidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-v10.7-final-authoring.v1'
    task = 'APL-WIN-014'
    created_utc = Get-Date -UFormat '%Y-%m-%dT%H:%M:%S.0000000Z'
    version = $CandidateVersion
    mode = 'ReferenceFullHash'
    base_policy_id = $BasePolicyIdText
    supplemental_policy_id = $policyId
    supplemental_policy_friendly_name = $PolicyFriendlyName
    supplemental_policy_version = $PolicyVersion
    supplemental_policy_xml = Split-Path -Leaf $policyXml
    supplemental_policy_cip = Split-Path -Leaf $policyCip
    release = [ordered]@{
        setup_sha256 = $ExpectedSetupHash
        application_sha256 = $ExpectedAppHash
    }
    unins000_hash = $unHash
    reference_files = $referenceFiles
    policy_scope = 'ReferenceFullHash: exact Setup + application + complete installed tree including generated maintenance binaries'
    verification = [ordered]@{
        base_policy_on_disk = $b.IsOnDisk
        base_policy_enforced = $b.IsEnforced
        base_policy_authorized = $b.IsAuthorized
        hash_policy_xml_valid = $true
        hash_policy_cip_valid = (Test-Path -LiteralPath $policyCip -PathType Leaf)
        unins000_included = ($xmlText -match $unHash)
    }
    deployment_invariants = @(
        'authoring script never deploys App Control policy',
        'base policy must allow supplemental policies',
        'hash policy is release-specific and must be regenerated for changed bytes'
    )
}
$evidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8

$checksums = @(
    Get-ChildItem -LiteralPath $outDir -File | Sort-Object Name | ForEach-Object {
        "$(Get-Sha256 $_.FullName)  $($_.Name)"
    }
)
Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

Write-Host ''
Write-Host '=== V10.7 Final Candidate authoring: COMPLETE ==='
Write-Host "Output: $outDir"
Write-Host "Deployment: NOT PERFORMED"
Write-Host 'Deploy V10.7 after authoring, before Repair or Uninstall is executed.'
