<# Behavioral tests for the base-only validation path used by prepare_v10_6_4_bootstrap_on_demo.ps1.
   Proves V10.6.4 authoring does not require V10.6.4 to already exist.
   Uses Resolve-ClmPolicyEvidence with RequireBootstrap=false and synthetic CiTool data. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')

$labBaseId = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$labBaseName = 'Arvectum APL-WIN-014 Lab Base'
$v1062BootstrapId = '11b32707-8981-4fe6-a852-3175aa1ac2bb'

Write-Host 'PRE-AUTHORING BASE-ONLY TESTS:'

# --- 1. PASS: Lab Base only (V10.6.4 absent) ---
$p1 = $false
try {
    $ci = @{ OperationResult=0; Policies=@(@{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }
    $result = Resolve-ClmPolicyEvidence -CiToolResult $ci -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
    if ($result.base.policy_id -eq $labBaseId -and $result.bootstrap -eq $null) { $p1 = $true }
} catch { }
if (-not $p1) { throw 'TEST 1 FAILED: Lab Base only with V10.6.4 absent should PASS.' }
Write-Host '  1. PASS: Lab Base only (V10.6.4 absent) -> PASS'

# --- 2. PASS: Lab Base + V10.6.2 present (V10.6.4 still absent) ---
$p2 = $false
try {
    $ci2 = @{ OperationResult=0; Policies=@(
        @{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') },
        @{ PolicyID=$v1062BootstrapId; BasePolicyID=$labBaseId; FriendlyName='Arvectum APL-WIN-014 Harness V10.6.2'; Version='10.0.0.15'; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@() }
    ) }
    $result2 = Resolve-ClmPolicyEvidence -CiToolResult $ci2 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
    if ($result2.base.policy_id -eq $labBaseId -and $result2.bootstrap -eq $null) { $p2 = $true }
} catch { }
if (-not $p2) { throw 'TEST 2 FAILED: Lab Base + V10.6.2 with V10.6.4 absent should PASS.' }
Write-Host '  2. PASS: Lab Base + V10.6.2 (V10.6.4 absent) -> PASS'

# --- 3. FAIL: Lab Base absent ---
$f1 = $false
try {
    $ci3 = @{ OperationResult=0; Policies=@(@{ PolicyID='11111111-1111-1111-1111-111111111111'; BasePolicyID='11111111-1111-1111-1111-111111111111'; FriendlyName='Wrong Policy'; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci3 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f1 = $true }
if (-not $f1) { throw 'TEST 3 FAILED: Lab Base absent should FAIL.' }
Write-Host '  3. PASS: Lab Base absent -> REJECTED'

# --- 4. FAIL: Duplicate Lab Base ---
$f2 = $false
try {
    $ci4 = @{ OperationResult=0; Policies=@(
        @{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') },
        @{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }
    ) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci4 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f2 = $true }
if (-not $f2) { throw 'TEST 4 FAILED: Duplicate Lab Base should FAIL.' }
Write-Host '  4. PASS: Duplicate Lab Base -> REJECTED'

# --- 5. FAIL: Wrong FriendlyName ---
$f3 = $false
try {
    $ci5 = @{ OperationResult=0; Policies=@(@{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName='WRONG NAME'; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci5 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f3 = $true }
if (-not $f3) { throw 'TEST 5 FAILED: Wrong FriendlyName should FAIL.' }
Write-Host '  5. PASS: Wrong FriendlyName -> REJECTED'

# --- 6. FAIL: Not enforced ---
$f4 = $false
try {
    $ci6 = @{ OperationResult=0; Policies=@(@{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$false; IsAuthorized=$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci6 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f4 = $true }
if (-not $f4) { throw 'TEST 6 FAILED: Not enforced should FAIL.' }
Write-Host '  6. PASS: Not enforced -> REJECTED'

# --- 7. FAIL: Not authorized ---
$f5 = $false
try {
    $ci7 = @{ OperationResult=0; Policies=@(@{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$false; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci7 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f5 = $true }
if (-not $f5) { throw 'TEST 7 FAILED: Not authorized should FAIL.' }
Write-Host '  7. PASS: Not authorized -> REJECTED'

# --- 8. FAIL: Allow Supplemental Policies absent ---
$f6 = $false
try {
    $ci8 = @{ OperationResult=0; Policies=@(@{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@() }) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci8 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f6 = $true }
if (-not $f6) { throw 'TEST 8 FAILED: Allow Supplemental Policies absent should FAIL.' }
Write-Host '  8. PASS: Allow Supplemental Policies absent -> REJECTED'

# --- 9. FAIL: Audit Mode present ---
$f7 = $false
try {
    $ci9 = @{ OperationResult=0; Policies=@(@{ PolicyID=$labBaseId; BasePolicyID=$labBaseId; FriendlyName=$labBaseName; IsOnDisk=$true; IsEnforced=$true; IsAuthorized=$true; PolicyOptions=@('Enabled:Audit Mode') }) }
    Resolve-ClmPolicyEvidence -CiToolResult $ci9 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f7 = $true }
if (-not $f7) { throw 'TEST 9 FAILED: Audit Mode present should FAIL.' }
Write-Host '  9. PASS: Audit Mode present -> REJECTED'

# --- 10. FAIL: OperationResult non-zero ---
$f8 = $false
try {
    $ci10 = @{ OperationResult=1; Policies=@() }
    Resolve-ClmPolicyEvidence -CiToolResult $ci10 -ExpectedBasePolicyId $labBaseId -ExpectedBaseFriendlyName $labBaseName -RequireBootstrap $false
} catch { $f8 = $true }
if (-not $f8) { throw 'TEST 10 FAILED: OperationResult non-zero should FAIL.' }
Write-Host ' 10. PASS: OperationResult non-zero -> REJECTED'

Write-Host 'RESULT: PASS'
