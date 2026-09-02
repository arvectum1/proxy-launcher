<# Behavioral tests for bootstrap policy identity validation.
   Uses Resolve-ClmPolicyEvidence with RequireBootstrap=true and synthetic CiTool data.
   Proves all identity mismatches are rejected before CiTool mutation. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')

$labBaseId = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$labBaseName = 'Arvectum APL-WIN-014 Lab Base'
$bootstrapId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
$bootstrapName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'

function New-Base {
    @{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }
}

function New-Bootstrap {
    param([string]$Id=$bootstrapId, [string]$Name=$bootstrapName, [string]$BaseId=$labBaseId, [bool]$OnDisk=$true, [bool]$Enforced=$true, [bool]$Authorized=$true, [array]$Options=@())
    @{ PolicyID=$Id; BasePolicyID=$BaseId; FriendlyName=$Name; Version='10.0.0.17'; IsOnDisk=$OnDisk; IsEnforced=$Enforced; IsAuthorized=$Authorized; PolicyOptions=$Options }
}

Write-Host 'BOOTSTRAP POLICY IDENTITY NEGATIVE TESTS:'

# --- 1. PASS: exact Lab Base + exact V10.6.4 Bootstrap ---
$p1 = $false
try {
    $ci = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap)) }
    $r = Resolve-ClmPolicyEvidence -CiToolResult $ci -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
    if ($r.base.policy_id -eq $labBaseId -and $r.bootstrap.policy_id -eq $bootstrapId -and $r.bootstrap.friendly_name -eq $bootstrapName) { $p1 = $true }
} catch { Write-Host "  DEBUG: $_" }
if (-not $p1) { throw 'TEST 1 FAILED: exact Lab Base + exact Bootstrap should PASS.' }
Write-Host '  1. PASS: exact Lab Base + exact Bootstrap -> PASS'

# --- 2. FAIL: wrong bootstrap FriendlyName ---
$f1 = $false
try {
    $ci2 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Name 'WRONG NAME')) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci2 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f1 = $true }
if (-not $f1) { throw 'TEST 2 FAILED: wrong bootstrap FriendlyName should FAIL.' }
Write-Host '  2. PASS: wrong bootstrap FriendlyName -> REJECTED'

# --- 3. FAIL: wrong bootstrap BasePolicyID ---
$f2 = $false
try {
    $ci3 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -BaseId '00000000-0000-0000-0000-000000000000')) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci3 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f2 = $true }
if (-not $f2) { throw 'TEST 3 FAILED: wrong bootstrap BasePolicyID should FAIL.' }
Write-Host '  3. PASS: wrong bootstrap BasePolicyID -> REJECTED'

# --- 4. FAIL: wrong bootstrap PolicyID ---
$f3 = $false
try {
    $ci4 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Id 'wrong-policy-id')) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci4 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f3 = $true }
if (-not $f3) { throw 'TEST 4 FAILED: wrong bootstrap PolicyID should FAIL.' }
Write-Host '  4. PASS: wrong bootstrap PolicyID -> REJECTED'

# --- 5. FAIL: bootstrap not OnDisk ---
$f4 = $false
try {
    $ci5 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -OnDisk $false)) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci5 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f4 = $true }
if (-not $f4) { throw 'TEST 5 FAILED: bootstrap not OnDisk should FAIL.' }
Write-Host '  5. PASS: bootstrap not OnDisk -> REJECTED'

# --- 6. FAIL: bootstrap not Enforced ---
$f5 = $false
try {
    $ci6 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Enforced $false)) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci6 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f5 = $true }
if (-not $f5) { throw 'TEST 6 FAILED: bootstrap not Enforced should FAIL.' }
Write-Host '  6. PASS: bootstrap not Enforced -> REJECTED'

# --- 7. FAIL: bootstrap not Authorized ---
$f6 = $false
try {
    $ci7 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Authorized $false)) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci7 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f6 = $true }
if (-not $f6) { throw 'TEST 7 FAILED: bootstrap not Authorized should FAIL.' }
Write-Host '  7. PASS: bootstrap not Authorized -> REJECTED'

# --- 8. FAIL: bootstrap Audit Mode when PolicyOptions is exposed ---
$f7 = $false
try {
    $ci8 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Options @('Enabled:Audit Mode'))) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci8 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f7 = $true }
if (-not $f7) { throw 'TEST 8 FAILED: bootstrap Audit Mode should FAIL.' }
Write-Host '  8. PASS: bootstrap Audit Mode -> REJECTED'

# --- 9. FAIL: bootstrap missing (RequireBootstrap=true but not present) ---
$f8 = $false
try {
    $ci9 = @{ OperationResult=0; Policies=@((New-Base)) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci9 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $bootstrapId -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
} catch { $f8 = $true }
if (-not $f8) { throw 'TEST 9 FAILED: bootstrap missing should FAIL.' }
Write-Host '  9. PASS: bootstrap missing (RequireBootstrap=true) -> REJECTED'

# --- 10. PASS: braced expected Bootstrap ID + unbraced live CiTool ID ---
$p2 = $false
try {
    $ci10 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Id '8d593266-9e22-463f-b594-df9b734d02de')) }
    $r10 = Resolve-ClmPolicyEvidence -CiToolResult $ci10 -ExpectedBasePolicyId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}' -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId '{8D593266-9E22-463F-B594-DF9B734D02DE}' -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
    if ($r10.bootstrap.policy_id -eq '8d593266-9e22-463f-b594-df9b734d02de') { $p2 = $true }
} catch { Write-Host "  DEBUG: $_" }
if (-not $p2) { throw 'TEST 10 FAILED: braced expected and unbraced live Bootstrap should PASS.' }
Write-Host ' 10. PASS: braced expected / unbraced live -> PASS'

# --- 11. PASS: unbraced expected Bootstrap ID + braced live CiTool ID ---
$p3 = $false
try {
    $ci11 = @{ OperationResult=0; Policies=@((New-Base), (New-Bootstrap -Id '{8D593266-9E22-463F-B594-DF9B734D02DE}' -BaseId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}')) }
    $r11 = Resolve-ClmPolicyEvidence -CiToolResult $ci11 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId '8d593266-9e22-463f-b594-df9b734d02de' -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true
    if ($r11.bootstrap.policy_id -eq '{8D593266-9E22-463F-B594-DF9B734D02DE}') { $p3 = $true }
} catch { Write-Host "  DEBUG: $_" }
if (-not $p3) { throw 'TEST 11 FAILED: unbraced expected and braced live Bootstrap should PASS.' }
Write-Host ' 11. PASS: unbraced expected / braced live -> PASS'

# --- 12-15. FAIL: malformed expected, malformed live, wrong ID, duplicate normalized identity ---
foreach ($case in @(
    @{ label='malformed expected'; id='{8D593266-9E22-463F-B594-DF9B734D02DE'; policies=@((New-Base), (New-Bootstrap -Id '8d593266-9e22-463f-b594-df9b734d02de')) },
    @{ label='malformed live'; id='8d593266-9e22-463f-b594-df9b734d02de'; policies=@((New-Base), (New-Bootstrap -Id '8d593266-9e22-463f-b594-df9b734d02de}')) },
    @{ label='wrong normalized ID'; id='8d593266-9e22-463f-b594-df9b734d02de'; policies=@((New-Base), (New-Bootstrap -Id '00000000-0000-0000-0000-000000000000')) },
    @{ label='duplicate normalized ID'; id='8d593266-9e22-463f-b594-df9b734d02de'; policies=@((New-Base), (New-Bootstrap -Id '8d593266-9e22-463f-b594-df9b734d02de'), (New-Bootstrap -Id '{8D593266-9E22-463F-B594-DF9B734D02DE}')) }
)) {
    $rejected = $false
    try { Resolve-ClmPolicyEvidence -CiToolResult @{ OperationResult=0; Policies=$case.policies } -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -ExpectedBootstrapPolicyId $case.id -ExpectedBootstrapFriendlyName $bootstrapName -RequireBootstrap $true | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Policy identity case was accepted: $($case.label)" }
    Write-Host "  PASS: $($case.label) -> REJECTED"
}

Write-Host 'RESULT: PASS'
