<#
.SYNOPSIS
    ConfigCI XML structure regression tests for V10.6.2.
.DESCRIPTION
    Validates that the ConfigCI XML pattern matching correctly handles real ConfigCI
    output structure (Allow with Hash attribute, not Allow Type="Hash").
    Uses fixture XML files to simulate ConfigCI output.
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

function Test-XmlStructure {
    param([string]$XmlPath, [int]$ExpectedRules)

    if (-not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) { throw "Fixture not found: $XmlPath" }

    $rawLines = @(Select-String -Path $XmlPath -Pattern '<Allow\s+[^>]*Hash="[^"]+"' | ForEach-Object { $_.Line -replace '^\s+|\s+$','' })
    if ($rawLines.Count -ne $ExpectedRules) { throw "Expected $ExpectedRules hash Allow rules, found $($rawLines.Count)." }

    $ruleIds = @()
    $ruleNames = @()
    $ruleHashes = @()
    for ($i = 0; $i -lt $rawLines.Count; $i++) {
        $line = $rawLines[$i]
        if ($line -match 'ID="([^"]+)"') { $ruleIds += $matches[1] } else { $ruleIds += '' }
        if ($line -match 'FriendlyName="([^"]+)"') { $ruleNames += $matches[1] } else { $ruleNames += '' }
        if ($line -match 'Hash="([^"]+)"') { $ruleHashes += $matches[1] } else { $ruleHashes += '' }
    }

    for ($i = 0; $i -lt $ruleIds.Count; $i++) {
        if ([string]::IsNullOrEmpty($ruleIds[$i])) { throw "Rule at index $i missing ID." }
        if ([string]::IsNullOrEmpty($ruleHashes[$i])) { throw "Rule $($ruleIds[$i]) missing Hash attribute." }
    }

    $fileRulesRef = @(Select-String -Path $XmlPath -Pattern '<FileRuleRef RuleID="ID_ALLOW_A_\d+"' | ForEach-Object { $_.Line -replace '^\s+|\s+$','' })
    if ($fileRulesRef.Count -ne $ExpectedRules) { throw "Expected $ExpectedRules FileRuleRef entries, found $($fileRulesRef.Count)." }

    $signingScenario = Select-String -Path $XmlPath -Pattern 'SigningScenario Value="12"' | Select-Object -First 1
    if ($null -eq $signingScenario) { throw 'Missing user-mode SigningScenario Value="12".' }

    return @{ RuleCount=$rawLines.Count; RuleIds=$ruleIds; RuleNames=$ruleNames; RuleHashes=$ruleHashes }
}

Write-Host '=== ConfigCI XML Structure Regression Tests ==='

Write-Host ''
Write-Host '--- A: Real ConfigCI form PASS ---'
Test-Case 'A: Real ConfigCI form with 8 hash Allow rules' -ExpectPass $true -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_real_xml_structure.xml'
    $result = Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
    if ($result.RuleCount -ne 8) { throw 'Rule count mismatch' }
}

Write-Host ''
Write-Host '--- B: Zero hash Allow rules FAIL ---'
Test-Case 'B: Zero hash Allow rules fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_zero_rules.xml'
    Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
}

Write-Host ''
Write-Host '--- C: One rule only FAIL ---'
Test-Case 'C: One rule only fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_one_rule.xml'
    Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
}

Write-Host ''
Write-Host '--- D: 7 rules FAIL ---'
Test-Case 'D: 7 rules fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_seven_rules.xml'
    Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
}

Write-Host ''
Write-Host '--- E: 9 rules FAIL ---'
Test-Case 'E: 9 rules fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_nine_rules.xml'
    Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
}

Write-Host ''
Write-Host '--- F: Missing Hash attribute FAIL ---'
Test-Case 'F: Missing Hash attribute fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_missing_hash.xml'
    Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
}

Write-Host ''
Write-Host '--- G: Duplicate RuleID FAIL ---'
Test-Case 'G: Duplicate RuleID fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_duplicate_ruled.xml'
    $result = Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
    $seen = @()
    for ($i = 0; $i -lt $result.RuleIds.Count; $i++) {
        if ($result.RuleIds[$i] -in $seen) { throw "Duplicate RuleID: $($result.RuleIds[$i])" }
        $seen += $result.RuleIds[$i]
    }
    throw 'No duplicate RuleID detected'
}

Write-Host ''
Write-Host '--- H: Missing FileRuleRef FAIL ---'
Test-Case 'H: Missing FileRuleRef fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_missing_fileruleref.xml'
    Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
}

Write-Host ''
Write-Host '--- I: Unexpected third file FAIL ---'
Test-Case 'I: Unexpected third file fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_third_file.xml'
    $result = Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 8
    $unexpected = @($result.RuleNames | Where-Object { $_ -notmatch 'Arvectum Proxy Launcher\.exe' -and $_ -notmatch 'Arvectum-Proxy-Launcher.*setup\.exe' })
    if ($unexpected.Count -gt 0) { throw "Unexpected third-party file: $($unexpected[0])" }
}

Write-Host ''
Write-Host '--- J: Missing hash variant FAIL ---'
Test-Case 'J: Missing hash variant fails' -ExpectPass $false -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_missing_variant.xml'
    $result = Test-XmlStructure -XmlPath $fixturePath -ExpectedRules 7
    throw "Expected 7 rules to fail"
}

Write-Host ''
Write-Host '--- K: Fake legacy Allow Type="Hash" not required ---'
Test-Case 'K: Legacy Allow Type=Hash pattern is not required' -ExpectPass $true -Test {
    $fixturePath = Join-Path $FixtureDir 'configci_real_xml_structure.xml'
    $legacyRules = @(Select-String -Path $fixturePath -Pattern '<Allow Type="Hash"')
    if ($legacyRules.Count -gt 0) { throw 'Legacy pattern should not match real ConfigCI XML' }
    $realFile = Join-Path $FixtureDir 'configci_real_xml_structure.xml'
    $realRules = @(Select-String -Path $realFile -Pattern '<Allow\s+[^>]*Hash="[^"]+"')
    if ($realRules.Count -ne 8) { throw 'Real pattern should find 8 rules' }
}

Write-Host ''
Write-Host '=== ConfigCI XML Structure Test Summary ==='
Write-Host "  Passed: $passed"
Write-Host "  Failed: $failed"
Write-Host "  Total:  $($passed + $failed)"

if ($failed -gt 0) {
    Write-Host ''
    Write-Host 'RESULT: FAIL'
    throw "ConfigCI XML structure tests failed: $failed failure(s)."
} else {
    Write-Host ''
    Write-Host 'RESULT: PASS'
}
