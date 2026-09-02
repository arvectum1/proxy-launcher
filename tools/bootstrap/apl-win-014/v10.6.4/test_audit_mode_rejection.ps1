<# Behavioral tests for Audit Mode rejection across policy validation paths. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')

# --- Test 1: valid base -> PASS ---
$validBase = Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=$true; is_enforced=$true; is_authorized=$true; policy_options=@('Enabled:Allow Supplemental Policies') }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'
if ($validBase -ne $true) { throw 'Test 1 failed: valid base should PASS.' }

# --- Test 2: base Audit Mode -> FAIL ---
$baseAuditFailed = $false
try {
    Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=$true; is_enforced=$true; is_authorized=$true; policy_options=@('Enabled:Audit Mode') }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'
} catch { $baseAuditFailed = $true }
if (-not $baseAuditFailed) { throw 'Test 2 failed: base Audit Mode should FAIL.' }

# --- Test 3: base with supplemental + audit mode -> FAIL ---
$baseBothFailed = $false
try {
    Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=$true; is_enforced=$true; is_authorized=$true; policy_options=@('Enabled:Allow Supplemental Policies','Enabled:Audit Mode') }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'
} catch { $baseBothFailed = $true }
if (-not $baseBothFailed) { throw 'Test 3 failed: base with supplemental+audit should FAIL.' }

# --- Test 4: supplemental Audit Mode -> FAIL ---
$suppAuditFailed = $false
try {
    Test-ClmAuditModeRejection -PolicyOptions @('Enabled:Audit Mode') -PolicyLabel 'V10.6.4 Bootstrap supplemental'
} catch { $suppAuditFailed = $true }
if (-not $suppAuditFailed) { throw 'Test 4 failed: supplemental Audit Mode should FAIL.' }

# --- Test 5: supplemental with options valid -> PASS ---
$suppValid = Test-ClmAuditModeRejection -PolicyOptions @('Enabled:Allow Supplemental Policies') -PolicyLabel 'V10.6.4 Bootstrap supplemental'
if ($suppValid -ne $true) { throw 'Test 5 failed: valid supplemental should PASS.' }

# --- Test 6: empty options -> PASS (no audit mode) ---
$emptyOpts = Test-ClmAuditModeRejection -PolicyOptions @() -PolicyLabel 'V10.6.4 Bootstrap supplemental'
if ($emptyOpts -ne $true) { throw 'Test 6 failed: empty options should PASS.' }

# --- Test 7: base not enforced -> FAIL ---
$notEnforcedFailed = $false
try {
    Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=$true; is_enforced=$false; is_authorized=$true; policy_options=@('Enabled:Allow Supplemental Policies') }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'
} catch { $notEnforcedFailed = $true }
if (-not $notEnforcedFailed) { throw 'Test 7 failed: not enforced should FAIL.' }

# --- Test 8: base missing supplemental option -> FAIL ---
$missingSuppFailed = $false
try {
    Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=$true; is_enforced=$true; is_authorized=$true; policy_options=@() }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'
} catch { $missingSuppFailed = $true }
if (-not $missingSuppFailed) { throw 'Test 8 failed: missing supplemental option should FAIL.' }

Write-Host 'RESULT: PASS'
