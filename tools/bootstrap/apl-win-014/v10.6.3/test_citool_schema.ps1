<#
.SYNOPSIS
    CiTool schema regression tests for V10.6.3.
.DESCRIPTION
    Validates that the CiTool schema adapter correctly handles real vs synthetic
    schemas, OperationResult checks, base policy validation, and fail-closed behavior.
    Uses fixture JSON files to simulate CiTool output.
#>
#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FixtureDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures'
$BasePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'

$passed = 0
$failed = 0
$tests = @()

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [bool]$ExpectPass
    )
    try {
        $result = & $Test
        if ($ExpectPass) {
            $passed++
            $tests += [ordered]@{ Name=$Name; Status='PASS'; Error=$null }
            Write-Host "  PASS: $Name"
        } else {
            $failed++
            $tests += [ordered]@{ Name=$Name; Status='FAIL'; Error='Expected failure but got PASS' }
            Write-Host "  FAIL: $Name (expected failure, got PASS)"
        }
    } catch {
        if (-not $ExpectPass) {
            $passed++
            $tests += [ordered]@{ Name=$Name; Status='PASS'; Error=$null }
            Write-Host "  PASS: $Name (correctly failed: $($_.Exception.Message))"
        } else {
            $failed++
            $tests += [ordered]@{ Name=$Name; Status='FAIL'; Error=$_.Exception.Message }
            Write-Host "  FAIL: $Name - $($_.Exception.Message)"
        }
    }
}

function Invoke-BasePolicyValidation {
    param([object]$Parsed)
    if ($null -eq $Parsed.OperationResult) { throw 'CiTool output missing OperationResult. FAIL CLOSED.' }
    if ($Parsed.OperationResult -ne 0) { throw "CiTool OperationResult=$($Parsed.OperationResult). FAIL CLOSED." }
    $base = @($Parsed.Policies | Where-Object { $_.PolicyID -eq $BasePolicyIdText })
    if ($base.Count -ne 1) { throw "Lab Base policy not found: $BasePolicyIdText (found $($base.Count)). FAIL CLOSED." }
    $b = $base[0]
    if ($null -eq $b.PolicyID) { throw 'Base policy PolicyID is null. FAIL CLOSED.' }
    if ($b.PolicyID -ne $BasePolicyIdText) { throw "Base PolicyID mismatch: $($b.PolicyID). FAIL CLOSED." }
    if ($null -eq $b.BasePolicyID) { throw 'Base policy BasePolicyID is null. FAIL CLOSED.' }
    if ($b.BasePolicyID -ne $BasePolicyIdText) { throw "Base BasePolicyID mismatch: $($b.BasePolicyID). FAIL CLOSED." }
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
    return $b
}

Write-Host '=== CiTool Schema Regression Tests ==='

Write-Host ''
Write-Host '--- A: Real schema PASS ---'
Test-Case 'A: Real schema finds canonical Lab Base' -ExpectPass $true -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_real_schema.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    $b = Invoke-BasePolicyValidation -Parsed $parsed
    if ($b.PolicyID -ne $BasePolicyIdText) { throw 'PolicyID mismatch' }
    if ($b.FriendlyName -ne 'Arvectum APL-WIN-014 Lab Base') { throw 'FriendlyName mismatch' }
    if ($b.IsOnDisk -ne $true) { throw 'IsOnDisk mismatch' }
    if ($b.IsEnforced -ne $true) { throw 'IsEnforced mismatch' }
    if ($b.IsAuthorized -ne $true) { throw 'IsAuthorized mismatch' }
}

Write-Host ''
Write-Host '--- B: Wrong synthetic schema FAIL ---'
Test-Case 'B: Synthetic schema (policy_id) fails to find base' -ExpectPass $false -Test {
    $parsed = @{
        Policies = @(
            @{ policy_id = $BasePolicyIdText; base_policy_id = $BasePolicyIdText; is_on_disk = $true; is_enforced = $true; is_authorized = $true }
        )
        OperationResult = 0
    }
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- C: OperationResult != 0 FAIL CLOSED ---'
Test-Case 'C: OperationResult=1 fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_operation_result_nonzero.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- D: Missing OperationResult FAIL CLOSED ---'
Test-Case 'D: Missing OperationResult fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_missing_operation_result.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- E: Missing PolicyID FAIL CLOSED ---'
Test-Case 'E: Missing PolicyID fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_missing_policy_id.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- F: Duplicate canonical Base policy FAIL CLOSED ---'
Test-Case 'F: Duplicate base policy fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_duplicate_base_policy.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- G: IsOnDisk=false FAIL CLOSED ---'
Test-Case 'G: IsOnDisk=false fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_base_not_on_disk.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- H: IsEnforced=false FAIL CLOSED ---'
Test-Case 'H: IsEnforced=false fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_base_not_enforced.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- I: IsAuthorized=false FAIL CLOSED ---'
Test-Case 'I: IsAuthorized=false fails closed' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'citool_base_not_authorized.json'
    $raw = Get-Content -LiteralPath $fixturePath -Raw
    $parsed = $raw | ConvertFrom-Json
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- J: Enabled:Audit Mode FAIL CLOSED ---'
Test-Case 'J: Audit Mode fails closed' -ExpectPass $false -Test {
    $parsed = @{
        Policies = @(
            @{
                PolicyID = $BasePolicyIdText
                BasePolicyID = $BasePolicyIdText
                FriendlyName = 'Arvectum APL-WIN-014 Lab Base'
                IsOnDisk = $true
                IsEnforced = $true
                IsAuthorized = $true
                PolicyOptions = @('Enabled:UMCI', 'Enabled:Allow Supplemental Policies', 'Enabled:Audit Mode')
            }
        )
        OperationResult = 0
    }
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '--- K: Missing Allow Supplemental Policies FAIL CLOSED ---'
Test-Case 'K: Missing supplemental policy allowance fails closed' -ExpectPass $false -Test {
    $parsed = @{
        Policies = @(
            @{
                PolicyID = $BasePolicyIdText
                BasePolicyID = $BasePolicyIdText
                FriendlyName = 'Arvectum APL-WIN-014 Lab Base'
                IsOnDisk = $true
                IsEnforced = $true
                IsAuthorized = $true
                PolicyOptions = @('Enabled:UMCI')
            }
        )
        OperationResult = 0
    }
    Invoke-BasePolicyValidation -Parsed $parsed
}

Write-Host ''
Write-Host '=== CiTool Schema Test Summary ==='
Write-Host "  Passed: $passed"
Write-Host "  Failed: $failed"
Write-Host "  Total:  $($passed + $failed)"

if ($failed -gt 0) {
    Write-Host ''
    Write-Host 'RESULT: FAIL'
    throw "CiTool schema tests failed: $failed failure(s)."
} else {
    Write-Host ''
    Write-Host 'RESULT: PASS'
}
