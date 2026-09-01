<#
.SYNOPSIS
    Author V10.6.1 Bootstrap supplemental policy on ARVECTUM-DEMO (authoring only, CLM-safe).
.DESCRIPTION
    Generates a narrow BootstrapHash supplemental App Control policy for the exact
    0.2.4 candidate. Does NOT deploy. Produces XML + CIP + evidence only.
    Written for Windows PowerShell 5.1 ConstrainedLanguage mode.
    V10.6.1: Fixed real CiTool schema (PolicyID, not policy_id).
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$BasePolicyId = [guid]$BasePolicyIdText
$PolicyFriendlyName = 'Arvectum APL-WIN-014 Harness V10.6.2 Bootstrap'
$PolicyVersion = '10.0.0.16'
$CandidateVersion = '0.2.4'

$ExpectedSetupHash = '7b9e7b95b0c26a028ed903ba7281a60dfd83c190ebdcf1208c05c1f687450389'
$ExpectedAppHash   = '0f275a8ab6d1640e3c392308c6ae4af4f613fc2750c62df7f173300eb0e0e447'
$ExpectedManifestHash = '6f7219be4664947e4cd6082423f9592e7774e34c1c72d92a6a89a29f98eb690d'
$ExpectedUpgradeHash  = '411f9e905723d4f5fcffb26057d8e5885087a35b988dda286ade11d9f0f81a95'
$ExpectedUninstallHash = '7abc1fe332975440d2c84be608773a890c5bb4deb130eea54378a128e79b0a44'

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

Write-Host '=== Querying CiTool (real schema) ==='
$raw = & CiTool.exe -lp -json 2>$null
$policies = $raw | ConvertFrom-Json

if ($null -eq $policies.OperationResult) { throw 'CiTool output missing OperationResult. FAIL CLOSED.' }
if ($policies.OperationResult -ne 0) { throw "CiTool OperationResult=$($policies.OperationResult). FAIL CLOSED." }
Write-Host "  OperationResult: $($policies.OperationResult)"

$base = @($policies.Policies | Where-Object { $_.PolicyID -eq $BasePolicyIdText })
if ($base.Count -ne 1) { throw "Lab Base policy not found: $BasePolicyIdText (found $($base.Count) matches). FAIL CLOSED." }
$b = $base[0]

if ($null -eq $b.PolicyID) { throw 'Base policy PolicyID is null. FAIL CLOSED.' }
if ($b.PolicyID -ne $BasePolicyIdText) { throw "Base PolicyID mismatch: $($b.PolicyID) != $BasePolicyIdText. FAIL CLOSED." }
if ($null -eq $b.BasePolicyID) { throw 'Base policy BasePolicyID is null. FAIL CLOSED.' }
if ($b.BasePolicyID -ne $BasePolicyIdText) { throw "Base BasePolicyID mismatch: $($b.BasePolicyID) != $BasePolicyIdText. FAIL CLOSED." }
if ($b.FriendlyName -ne 'Arvectum APL-WIN-014 Lab Base') { throw "Base FriendlyName mismatch: $($b.FriendlyName). FAIL CLOSED." }
if ($b.IsOnDisk -ne $true) { throw 'Lab Base is not on-disk. FAIL CLOSED.' }
if ($b.IsEnforced -ne $true) { throw 'Lab Base is not enforced. FAIL CLOSED.' }
if ($b.IsAuthorized -ne $true) { throw 'Lab Base is not authorized. FAIL CLOSED.' }

$hasSupplemental = $false
$hasAuditMode = $false
if ($null -ne $b.PolicyOptions) {
    foreach ($opt in $b.PolicyOptions) {
        if ($opt -eq 'Enabled:Allow Supplemental Policies') { $hasSupplemental = $true }
        if ($opt -eq 'Enabled:Audit Mode') { $hasAuditMode = $true }
    }
}
if (-not $hasSupplemental) { throw 'Lab Base missing Enabled:Allow Supplemental Policies. FAIL CLOSED.' }
if ($hasAuditMode) { throw 'Lab Base has Enabled:Audit Mode. FAIL CLOSED.' }

Write-Host "  PolicyID:       $($b.PolicyID)"
Write-Host "  BasePolicyID:   $($b.BasePolicyID)"
Write-Host "  FriendlyName:   $($b.FriendlyName)"
Write-Host "  IsOnDisk:       $($b.IsOnDisk)"
Write-Host "  IsEnforced:     $($b.IsEnforced)"
Write-Host "  IsAuthorized:   $($b.IsAuthorized)"
Write-Host "  PolicyOptions:  $($b.PolicyOptions -join ', ')"
Write-Host '  Base policy validation: PASS'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$hashesPath = Join-Path $scriptDir 'expected_hashes.json'
$hashes = Get-Content -LiteralPath $hashesPath -Raw | ConvertFrom-Json

$setupPath = Join-Path $scriptDir $hashes.files.setup_exe.filename
$appPath   = Join-Path $scriptDir $hashes.files.main_exe.filename
$manifestPath = Join-Path $scriptDir $hashes.files.build_manifest.filename
$upgradePath  = Join-Path $scriptDir $hashes.files.upgrade_helper.filename
$uninstallPath = Join-Path $scriptDir $hashes.files.uninstall_helper.filename

Write-Host ''
Write-Host '=== Verifying candidate hashes ==='
foreach ($entry in @(
    @{ Label='Setup EXE';    Path=$setupPath;    Expected=$hashes.files.setup_exe.sha256 },
    @{ Label='Main EXE';     Path=$appPath;      Expected=$hashes.files.main_exe.sha256 },
    @{ Label='build_manifest'; Path=$manifestPath; Expected=$hashes.files.build_manifest.sha256 },
    @{ Label='upgrade_helper'; Path=$upgradePath;  Expected=$hashes.files.upgrade_helper.sha256 },
    @{ Label='uninstall_helper'; Path=$uninstallPath; Expected=$hashes.files.uninstall_helper.sha256 }
)) {
    if (-not (Test-Path -LiteralPath $entry.Path -PathType Leaf)) { throw "Missing: $($entry.Label) ($($entry.Path))" }
    $actual = Get-Sha256 $entry.Path
    if ($actual -ne $entry.Expected) { throw "Hash mismatch for $($entry.Label): expected $($entry.Expected), got $actual" }
    Write-Host "  $($entry.Label): PASS ($actual)"
}

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.ffffffZ'
$outDir = Join-Path $scriptDir "v10.6.1-authoring-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$stagingDir = Join-Path $outDir 'scan'
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
Copy-Item -LiteralPath $setupPath -Destination (Join-Path $stagingDir 'Arvectum-Proxy-Launcher-0.2.4-windows-x64-setup.exe') -Force
Copy-Item -LiteralPath $appPath   -Destination (Join-Path $stagingDir 'Arvectum Proxy Launcher.exe') -Force

Write-Host ''
Write-Host '=== Generating V10.6.1 Bootstrap hash policy ==='
$policyXml = Join-Path $outDir 'Arvectum-APL-WIN-014-V10.6.1-Bootstrap.xml'
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
Write-Host '=== V10.6.2 Bootstrap hash rules ==='
$hashRuleIds = @()
$hashRuleNames = @()
$hashRuleHashes = @()
$rawLines = @(Select-String -Path $policyXml -Pattern '<Allow\s+[^>]*Hash="[^"]+"' | ForEach-Object { $_.Line -replace '^\s+|\s+$','' })
for ($i = 0; $i -lt $rawLines.Count; $i++) {
    $line = $rawLines[$i]
    if ($line -match 'ID="([^"]+)"') { $rid = $matches[1] } else { $rid = '' }
    if ($line -match 'FriendlyName="([^"]+)"') { $rfn = $matches[1] } else { $rfn = '' }
    if ($line -match 'Hash="([^"]+)"') { $rh = $matches[1] } else { $rh = '' }
    $hashRuleIds += $rid
    $hashRuleNames += $rfn
    $hashRuleHashes += $rh
    Write-Host "  $rid | $rfn | $rh"
}
Write-Host ''
Write-Host "Rule count: $($rawLines.Count)"

Write-Host ''
Write-Host '=== Structural validation ==='
if ($rawLines.Count -ne 8) { throw "Expected 8 hash Allow rules, found $($rawLines.Count). FAIL CLOSED." }
Write-Host '  Total Allow rules = 8: PASS'

$appCount = 0
$setupCount = 0
for ($i = 0; $i -lt $hashRuleNames.Count; $i++) {
    if ($hashRuleNames[$i] -match 'Arvectum Proxy Launcher\.exe') { $appCount++ }
    elseif ($hashRuleNames[$i] -match 'Arvectum-Proxy-Launcher.*setup\.exe') { $setupCount++ }
}
if ($appCount -ne 4) { throw "Expected 4 rules for application EXE, found $appCount. FAIL CLOSED." }
if ($setupCount -ne 4) { throw "Expected 4 rules for setup EXE, found $setupCount. FAIL CLOSED." }
Write-Host '  Application EXE rules = 4: PASS'
Write-Host '  Setup EXE rules = 4: PASS'

for ($i = 0; $i -lt $hashRuleIds.Count; $i++) {
    if ([string]::IsNullOrEmpty($hashRuleIds[$i])) { throw "Hash rule at index $i missing ID. FAIL CLOSED." }
    if ([string]::IsNullOrEmpty($hashRuleHashes[$i])) { throw "Hash rule $($hashRuleIds[$i]) missing Hash attribute. FAIL CLOSED." }
}
Write-Host '  All rules have non-empty ID and Hash: PASS'

$appVariants = @()
$setupVariants = @()
for ($i = 0; $i -lt $hashRuleNames.Count; $i++) {
    $fn = $hashRuleNames[$i]
    $variant = ''
    if ($fn -match 'Hash Sha256$') { $variant = 'Sha256' }
    elseif ($fn -match 'Hash Sha1$') { $variant = 'Sha1' }
    elseif ($fn -match 'Hash Page Sha256$') { $variant = 'PageSha256' }
    elseif ($fn -match 'Hash Page Sha1$') { $variant = 'PageSha1' }
    if ($fn -match 'Arvectum Proxy Launcher\.exe') { $appVariants += $variant }
    else { $setupVariants += $variant }
}
$expectedVariants = @('Sha1','Sha256','PageSha1','PageSha256')
$appMissing = @($expectedVariants | Where-Object { $_ -notin $appVariants })
$setupMissing = @($expectedVariants | Where-Object { $_ -notin $setupVariants })
if ($appMissing.Count -gt 0) { throw "Application EXE missing variants: $($appMissing -join ', '). FAIL CLOSED." }
if ($setupMissing.Count -gt 0) { throw "Setup EXE missing variants: $($setupMissing -join ', '). FAIL CLOSED." }
Write-Host '  All 4 hash variants present per file: PASS'

$fileRulesRef = @(Select-String -Path $policyXml -Pattern '<FileRuleRef RuleID="ID_ALLOW_A_\d+"' | ForEach-Object { $_.Line -replace '^\s+|\s+$','' })
if ($fileRulesRef.Count -ne 8) { throw "Expected 8 FileRuleRef entries, found $($fileRulesRef.Count). FAIL CLOSED." }
Write-Host '  FileRuleRef count = 8: PASS'

$signingScenario = Select-String -Path $policyXml -Pattern 'SigningScenario Value="12"' | Select-Object -First 1
if ($null -eq $signingScenario) { throw 'Missing user-mode SigningScenario Value="12". FAIL CLOSED.' }
Write-Host '  User-mode SigningScenario present: PASS'

$signers = Select-String -Path $policyXml -Pattern '<Signers\s*/>' | Select-Object -First 1
if ($null -eq $signers) {
    $signersNonEmpty = Select-String -Path $policyXml -Pattern '<Signers>' | Select-Object -First 1
    if ($null -ne $signersNonEmpty) { throw 'Signers element is non-empty. Unexpected signer-based trust path detected. FAIL CLOSED.' }
}
Write-Host '  No signer-based trust path: PASS'

for ($i = 0; $i -lt $hashRuleNames.Count; $i++) {
    if ($hashRuleNames[$i] -notmatch 'Arvectum Proxy Launcher\.exe' -and $hashRuleNames[$i] -notmatch 'Arvectum-Proxy-Launcher.*setup\.exe') {
        throw "Unexpected third-party file in hash rules: $($hashRuleNames[$i]). FAIL CLOSED."
    }
}
Write-Host '  No unexpected third-party files: PASS'

$authSetup = Get-AuthenticodeSignature -LiteralPath $setupPath
$authApp   = Get-AuthenticodeSignature -LiteralPath $appPath

$evidence = New-Object PSObject -Property @{
    schema = 'arvectum.proxy.apl-win-014-v10.6.2-bootstrap-authoring.v1'
    task = 'APL-WIN-014'
    created_at = $timestamp
    version = $CandidateVersion
    mode = 'BootstrapHash'
    base_policy_id = $BasePolicyIdText
    base_policy_friendly_name = $b.FriendlyName
    base_policy_authorized = $b.IsAuthorized
    base_policy_supplemental_allowed = $hasSupplemental
    base_policy_audit_mode = $hasAuditMode
    supplemental_policy_id = $policyId
    supplemental_policy_friendly_name = $PolicyFriendlyName
    supplemental_policy_version = $PolicyVersion
    supplemental_policy_xml = Split-Path -Leaf $policyXml
    supplemental_policy_cip = Split-Path -Leaf $policyCip
    citool_operation_result = $policies.OperationResult
    release = New-Object PSObject -Property @{
        setup_sha256 = (Get-Sha256 $setupPath)
        application_sha256 = (Get-Sha256 $appPath)
        setup_authenticode = "$($authSetup.Status)"
        application_authenticode = "$($authApp.Status)"
    }
    policy_scope = 'BootstrapHash: exact Setup + exact application EXE; use ReferenceFullHash for complete lifecycle'
    verification = New-Object PSObject -Property @{
        base_policy_on_disk = $b.IsOnDisk
        base_policy_enforced = $b.IsEnforced
        base_policy_authorized = $b.IsAuthorized
        base_policy_supplemental_allowed = $hasSupplemental
        base_policy_audit_mode = $hasAuditMode
        hash_policy_xml_valid = $true
        hash_policy_cip_valid = (Test-Path -LiteralPath $policyCip -PathType Leaf)
    }
    deployment_invariants = 'authoring script never deploys App Control policy; base policy must allow supplemental policies; hash policy is release-specific'
}
$evidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outDir 'authoring-evidence.json') -Encoding UTF8

$checksums = @(
    Get-ChildItem -LiteralPath $outDir -File | Sort-Object Name | ForEach-Object {
        "$(Get-Sha256 $_.FullName)  $($_.Name)"
    }
)
Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

Write-Host ''
Write-Host '=== V10.6.1 Bootstrap authoring: COMPLETE ==='
Write-Host "Output: $outDir"
Write-Host "Deployment: NOT PERFORMED"
Write-Host 'DO NOT deploy until install_v10_6_1_bootstrap_on_demo.ps1 is run manually.'
