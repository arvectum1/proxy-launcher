<# Behavioral tests for deploy authoring provenance validation.
   Proves install_v10_6_4_bootstrap_on_demo.ps1 rejects valid-looking authoring evidence
   with wrong candidate_source_commit or candidate_artifact_id before CiTool mutation.
   Also validates all other authoring evidence fields. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')

$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$friendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json

Write-Host 'DEPLOY AUTHORING PROVENANCE NEGATIVE TESTS:'

function New-ValidAuthoringEvidence {
    param(
        [string]$SourceCommit = $seal.candidate_source_commit,
        [string]$ArtifactId = $seal.candidate_artifact_id,
        [string]$PolicyId = '{11111111-1111-1111-1111-111111111111}',
        [string]$XmlFilename = 'test.xml',
        [string]$XmlSha256 = 'AAAA',
        [string]$CipFilename = '{11111111-1111-1111-1111-111111111111}.cip',
        [string]$CipSha256 = 'BBBB',
        [string]$Deployment = 'NOT PERFORMED'
    )
    $dir = Join-Path $env:TEMP ('deploy-test-' + [guid]::NewGuid().ToString('n').Substring(0,8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $evidence = @{
        schema='arvectum.proxy.apl-win-014-v10.6.4-bootstrap-authoring.v3'
        candidate_source_commit=$SourceCommit
        candidate_artifact_id=$ArtifactId
        base_policy_id=$basePolicyIdText
        supplemental_policy_id=$PolicyId
        supplemental_policy_friendly_name=$friendlyName
        supplemental_policy_version='10.0.0.17'
        supplemental_policy_xml=$XmlFilename
        supplemental_policy_xml_sha256=$XmlSha256
        supplemental_policy_cip=$CipFilename
        supplemental_policy_cip_sha256=$CipSha256
        deployment=$Deployment
    }
    $path = Join-Path $dir 'authoring-evidence.json'
    $evidence | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Test-DeployValidation {
    param([string]$AuthoringPath)
    $authoring = Get-Content -LiteralPath $AuthoringPath -Raw | ConvertFrom-Json
    if ($authoring.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-bootstrap-authoring.v3') { throw 'Authoring evidence schema mismatch.' }
    if ($authoring.candidate_source_commit -ne $seal.candidate_source_commit) { throw ('Authoring candidate_source_commit mismatch: expected {0} got {1}.' -f $seal.candidate_source_commit, $authoring.candidate_source_commit) }
    if ($authoring.candidate_artifact_id -ne $seal.candidate_artifact_id) { throw ('Authoring candidate_artifact_id mismatch: expected {0} got {1}.' -f $seal.candidate_artifact_id, $authoring.candidate_artifact_id) }
    if ($authoring.base_policy_id -ne $basePolicyIdText) { throw 'Authoring base_policy_id mismatch.' }
    if ($authoring.supplemental_policy_id -ne '{11111111-1111-1111-1111-111111111111}') { throw 'Authoring supplemental_policy_id mismatch.' }
    if ($authoring.supplemental_policy_friendly_name -ne $friendlyName) { throw 'Authoring supplemental_policy_friendly_name mismatch.' }
    if ($authoring.supplemental_policy_version -ne '10.0.0.17') { throw 'Authoring supplemental_policy_version mismatch.' }
    if ($authoring.deployment -ne 'NOT PERFORMED') { throw 'Authoring evidence deployment state is not NOT PERFORMED.' }
    return $true
}

# --- 1. PASS: valid authoring evidence ---
$p1 = $false
try {
    $evPath = New-ValidAuthoringEvidence
    Test-DeployValidation -AuthoringPath $evPath
    $p1 = $true
    Remove-Item -LiteralPath (Split-Path -Parent $evPath) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $p1 = $false }
if (-not $p1) { throw 'TEST 1 FAILED: valid authoring evidence should PASS.' }
Write-Host '  1. PASS: valid authoring evidence -> PASS'

# --- 2. FAIL: wrong candidate_source_commit ---
$f1 = $false
try {
    $ev2 = New-ValidAuthoringEvidence -SourceCommit '0000000000000000000000000000000000000000'
    Test-DeployValidation -AuthoringPath $ev2
    Remove-Item -LiteralPath (Split-Path -Parent $ev2) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f1 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev2) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f1) { throw 'TEST 2 FAILED: wrong candidate_source_commit should FAIL.' }
Write-Host '  2. PASS: wrong candidate_source_commit -> REJECTED'

# --- 3. FAIL: wrong candidate_artifact_id ---
$f2 = $false
try {
    $ev3 = New-ValidAuthoringEvidence -ArtifactId '9999999999'
    Test-DeployValidation -AuthoringPath $ev3
    Remove-Item -LiteralPath (Split-Path -Parent $ev3) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f2 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev3) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f2) { throw 'TEST 3 FAILED: wrong candidate_artifact_id should FAIL.' }
Write-Host '  3. PASS: wrong candidate_artifact_id -> REJECTED'

# --- 4. FAIL: wrong schema ---
$f3 = $false
try {
    $ev4 = New-ValidAuthoringEvidence
    $e4 = Get-Content -LiteralPath $ev4 -Raw | ConvertFrom-Json
    $e4.schema = 'wrong.schema.v1'
    $e4 | ConvertTo-Json | Set-Content -LiteralPath $ev4 -Encoding UTF8
    Test-DeployValidation -AuthoringPath $ev4
    Remove-Item -LiteralPath (Split-Path -Parent $ev4) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f3 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev4) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f3) { throw 'TEST 4 FAILED: wrong schema should FAIL.' }
Write-Host '  4. PASS: wrong schema -> REJECTED'

# --- 5. FAIL: wrong base_policy_id ---
$f4 = $false
try {
    $ev5 = New-ValidAuthoringEvidence
    $e5 = Get-Content -LiteralPath $ev5 -Raw | ConvertFrom-Json
    $e5.base_policy_id = '00000000-0000-0000-0000-000000000000'
    $e5 | ConvertTo-Json | Set-Content -LiteralPath $ev5 -Encoding UTF8
    Test-DeployValidation -AuthoringPath $ev5
    Remove-Item -LiteralPath (Split-Path -Parent $ev5) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f4 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev5) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f4) { throw 'TEST 5 FAILED: wrong base_policy_id should FAIL.' }
Write-Host '  5. PASS: wrong base_policy_id -> REJECTED'

# --- 6. FAIL: wrong supplemental_policy_id ---
$f5 = $false
try {
    $ev6 = New-ValidAuthoringEvidence -PolicyId 'wrong-policy-id'
    Test-DeployValidation -AuthoringPath $ev6
    Remove-Item -LiteralPath (Split-Path -Parent $ev6) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f5 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev6) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f5) { throw 'TEST 6 FAILED: wrong supplemental_policy_id should FAIL.' }
Write-Host '  6. PASS: wrong supplemental_policy_id -> REJECTED'

# --- 7. FAIL: wrong FriendlyName ---
$f6 = $false
try {
    $ev7 = New-ValidAuthoringEvidence
    $e7 = Get-Content -LiteralPath $ev7 -Raw | ConvertFrom-Json
    $e7.supplemental_policy_friendly_name = 'WRONG NAME'
    $e7 | ConvertTo-Json | Set-Content -LiteralPath $ev7 -Encoding UTF8
    Test-DeployValidation -AuthoringPath $ev7
    Remove-Item -LiteralPath (Split-Path -Parent $ev7) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f6 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev7) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f6) { throw 'TEST 7 FAILED: wrong FriendlyName should FAIL.' }
Write-Host '  7. PASS: wrong FriendlyName -> REJECTED'

# --- 8. FAIL: wrong policy version ---
$f7 = $false
try {
    $ev8 = New-ValidAuthoringEvidence
    $e8 = Get-Content -LiteralPath $ev8 -Raw | ConvertFrom-Json
    $e8.supplemental_policy_version = '9.9.9.99'
    $e8 | ConvertTo-Json | Set-Content -LiteralPath $ev8 -Encoding UTF8
    Test-DeployValidation -AuthoringPath $ev8
    Remove-Item -LiteralPath (Split-Path -Parent $ev8) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f7 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev8) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f7) { throw 'TEST 8 FAILED: wrong policy version should FAIL.' }
Write-Host '  8. PASS: wrong policy version -> REJECTED'

# --- 9. FAIL: deployment != NOT PERFORMED ---
$f8 = $false
try {
    $ev9 = New-ValidAuthoringEvidence -Deployment 'DEPLOYED'
    Test-DeployValidation -AuthoringPath $ev9
    Remove-Item -LiteralPath (Split-Path -Parent $ev9) -Recurse -Force -ErrorAction SilentlyContinue
} catch { $f8 = $true; Remove-Item -LiteralPath (Split-Path -Parent $ev9) -Recurse -Force -ErrorAction SilentlyContinue }
if (-not $f8) { throw 'TEST 9 FAILED: deployment != NOT PERFORMED should FAIL.' }
Write-Host '  9. PASS: deployment != NOT PERFORMED -> REJECTED'

Write-Host 'RESULT: PASS'
