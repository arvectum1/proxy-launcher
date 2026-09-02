<# Fixture regression test for ConfigCI Allow Hash attributes, supplemental semantics, GUID normalization, and path-qualified FriendlyNames. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'configci_xml_validation.ps1')
$fixtures = Join-Path $scriptDir 'fixtures'

# --- Original unbraced fixture ---
$fixture = Join-Path $fixtures 'configci_real_xml_structure.xml'
$rules = @(Select-String -LiteralPath $fixture -Pattern '<Allow\s+[^>]*Hash="[^"]+"')
$refs = @(Select-String -LiteralPath $fixture -Pattern '<FileRuleRef RuleID="ID_ALLOW_A_\d+"')
if ($rules.Count -ne 8 -or $refs.Count -ne 8) { throw 'Real ConfigCI fixture does not have eight hash rules and references.' }
Test-ConfigCiSupplementalXml -XmlPath $fixture -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null
Write-Host '  PASS: unbraced fixture'

# --- Braced uppercase GUID fixture (real Windows ConfigCI form) ---
$bracedFixture = Join-Path $fixtures 'configci_real_braced_guids.xml'
Test-ConfigCiSupplementalXml -XmlPath $bracedFixture -PolicyId '25374c9f-d7ef-448e-8f4b-c99959061e86' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null
Write-Host '  PASS: braced uppercase BasePolicyID vs unbraced expected'

# --- Braced PolicyID normalization ---
Test-ConfigCiSupplementalXml -XmlPath $bracedFixture -PolicyId '{25374C9F-D7EF-448E-8F4B-C99959061E86}' -BasePolicyId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null
Write-Host '  PASS: braced PolicyID normalization'

# --- Path-qualified fixture (real Windows ConfigCI form) ---
$pathQualifiedFixture = Join-Path $fixtures 'configci_real_path_qualified.xml'
Test-ConfigCiSupplementalXml -XmlPath $pathQualifiedFixture -PolicyId '{8B2309ED-EA37-4ABD-86D3-760ACC499274}' -BasePolicyId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe') | Out-Null
Write-Host '  PASS: path-qualified fixture'

# --- Wrong leaf filename (must fail) ---
$wrongLeafXml = Join-Path $fixtures 'configci_wrong_leaf.xml'
$wrongLeafContent = $fixture -replace '<Allow ID="ID_ALLOW_A_1" FriendlyName="Arvectum Proxy Launcher.exe Hash Sha256"', '<Allow ID="ID_ALLOW_A_1" FriendlyName="C:\scan\evil-Arvectum Proxy Launcher.exe Hash Sha256"'
Set-Content -LiteralPath $wrongLeafXml -Value $wrongLeafContent -Encoding UTF8
$wrongLeafFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $wrongLeafXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $wrongLeafFailed = $true }
if (-not $wrongLeafFailed) { throw 'Validator accepted wrong leaf filename.' }
Remove-Item -LiteralPath $wrongLeafXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: wrong leaf rejected'

# --- Expected name only in directory (must fail) ---
$dirOnlyXml = Join-Path $fixtures 'configci_dir_only.xml'
$dirOnlyContent = $fixture -replace '<Allow ID="ID_ALLOW_A_1" FriendlyName="Arvectum Proxy Launcher.exe Hash Sha256"', '<Allow ID="ID_ALLOW_A_1" FriendlyName="C:\Arvectum Proxy Launcher.exe Hash Sha256\evil.exe Hash Sha256"'
Set-Content -LiteralPath $dirOnlyXml -Value $dirOnlyContent -Encoding UTF8
$dirOnlyFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $dirOnlyXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $dirOnlyFailed = $true }
if (-not $dirOnlyFailed) { throw 'Validator accepted expected name only in directory.' }
Remove-Item -LiteralPath $dirOnlyXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: expected name only in directory rejected'

# --- Wrong hash variant (must fail) ---
$wrongVariantXml = Join-Path $fixtures 'configci_wrong_variant.xml'
$wrongVariantContent = $fixture -replace 'FriendlyName="Arvectum Proxy Launcher.exe Hash Sha256"', 'FriendlyName="Arvectum Proxy Launcher.exe Hash SHA512"'
Set-Content -LiteralPath $wrongVariantXml -Value $wrongVariantContent -Encoding UTF8
$wrongVariantFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $wrongVariantXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $wrongVariantFailed = $true }
if (-not $wrongVariantFailed) { throw 'Validator accepted wrong hash variant.' }
Remove-Item -LiteralPath $wrongVariantXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: wrong variant rejected'

# --- Extra hash variant (must fail) ---
$extraVariantXml = Join-Path $fixtures 'configci_extra_variant.xml'
$extraVariantContent = $fixture -replace '<Allow ID="ID_ALLOW_A_1" FriendlyName="Arvectum Proxy Launcher.exe Hash Sha256" Hash="01"/>', '<Allow ID="ID_ALLOW_A_1" FriendlyName="Arvectum Proxy Launcher.exe Hash Sha256" Hash="01"/><Allow ID="ID_ALLOW_A_9" FriendlyName="Arvectum Proxy Launcher.exe Hash MD5" Hash="09"/>'
Set-Content -LiteralPath $extraVariantXml -Value $extraVariantContent -Encoding UTF8
$extraVariantFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $extraVariantXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $extraVariantFailed = $true }
if (-not $extraVariantFailed) { throw 'Validator accepted extra hash variant.' }
Remove-Item -LiteralPath $extraVariantXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: extra variant rejected'

# --- Duplicate variant (must fail) ---
$dupVariantXml = Join-Path $fixtures 'configci_dup_variant.xml'
$dupVariantContent = $fixture -replace '<Allow ID="ID_ALLOW_A_2" FriendlyName="Arvectum Proxy Launcher.exe Hash Sha1" Hash="02"/>', '<Allow ID="ID_ALLOW_A_2" FriendlyName="Arvectum Proxy Launcher.exe Hash Sha256" Hash="02b"/>'
Set-Content -LiteralPath $dupVariantXml -Value $dupVariantContent -Encoding UTF8
$dupVariantFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $dupVariantXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $dupVariantFailed = $true }
if (-not $dupVariantFailed) { throw 'Validator accepted duplicate variant.' }
Remove-Item -LiteralPath $dupVariantXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: duplicate variant rejected'

# --- Unexpected ninth rule (must fail) ---
$ninthRuleXml = Join-Path $fixtures 'configci_ninth_rule.xml'
$ninthRuleContent = $fixture -replace '</FileRules>', '<Allow ID="ID_ALLOW_A_9" FriendlyName="unexpected.exe Hash Sha256" Hash="09"/></FileRules>'
Set-Content -LiteralPath $ninthRuleXml -Value $ninthRuleContent -Encoding UTF8
$ninthRuleFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $ninthRuleXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $ninthRuleFailed = $true }
if (-not $ninthRuleFailed) { throw 'Validator accepted unexpected ninth rule.' }
Remove-Item -LiteralPath $ninthRuleXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: unexpected ninth rule rejected'

# --- Self-referencing PolicyID/BasePolicyID (must fail) ---
$selfRefXml = Join-Path $fixtures 'configci_self_reference.xml'
$selfRefContent = $fixture -replace '<PolicyID>\{11111111-1111-1111-1111-111111111111\}</PolicyID><BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>', '<PolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</PolicyID><BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>'
Set-Content -LiteralPath $selfRefXml -Value $selfRefContent -Encoding UTF8
$selfRefFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $selfRefXml -PolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $selfRefFailed = $true }
if (-not $selfRefFailed) { throw 'Validator accepted self-referencing PolicyID/BasePolicyID.' }
Remove-Item -LiteralPath $selfRefXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: self-referencing rejected'

# --- Self-referencing braced (must also fail) ---
$selfRefBracedXml = Join-Path $fixtures 'configci_self_reference_braced.xml'
$selfRefBracedContent = $fixture -replace '<PolicyID>\{11111111-1111-1111-1111-111111111111\}</PolicyID><BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>', '<PolicyID>{DC1C604C-46EA-40B7-9F47-CF582B225D5E}</PolicyID><BasePolicyID>{DC1C604C-46EA-40B7-9F47-CF582B225D5E}</BasePolicyID>'
Set-Content -LiteralPath $selfRefBracedXml -Value $selfRefBracedContent -Encoding UTF8
$selfRefBracedFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $selfRefBracedXml -PolicyId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}' -BasePolicyId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $selfRefBracedFailed = $true }
if (-not $selfRefBracedFailed) { throw 'Validator accepted braced self-referencing PolicyID/BasePolicyID.' }
Remove-Item -LiteralPath $selfRefBracedXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: braced self-referencing rejected'

# --- Wrong BasePolicyID with braces ---
$wrongBracedBaseXml = Join-Path $fixtures 'configci_wrong_braced_base.xml'
$wrongBracedBaseContent = $fixture -replace '<BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>', '<BasePolicyID>{00000000-0000-0000-0000-000000000000}</BasePolicyID>'
Set-Content -LiteralPath $wrongBracedBaseXml -Value $wrongBracedBaseContent -Encoding UTF8
$wrongBracedBaseFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $wrongBracedBaseXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $wrongBracedBaseFailed = $true }
if (-not $wrongBracedBaseFailed) { throw 'Validator accepted wrong braced BasePolicyID.' }
Remove-Item -LiteralPath $wrongBracedBaseXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: wrong braced BasePolicyID rejected'

# --- Wrong BasePolicyID without braces ---
$wrongBaseXml = Join-Path $fixtures 'configci_wrong_base.xml'
$wrongBaseContent = $fixture -replace '<BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>', '<BasePolicyID>00000000-0000-0000-0000-000000000000</BasePolicyID>'
Set-Content -LiteralPath $wrongBaseXml -Value $wrongBaseContent -Encoding UTF8
$wrongBaseFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $wrongBaseXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $wrongBaseFailed = $true }
if (-not $wrongBaseFailed) { throw 'Validator accepted wrong unbraced BasePolicyID.' }
Remove-Item -LiteralPath $wrongBaseXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: wrong unbraced BasePolicyID rejected'

# --- Malformed brace representation ---
$malformedXml = Join-Path $fixtures 'configci_malformed_braces.xml'
$malformedContent = $fixture -replace '<PolicyID>\{11111111-1111-1111-1111-111111111111\}</PolicyID>', '<PolicyID>{{11111111-1111-1111-1111-111111111111}}</PolicyID>'
Set-Content -LiteralPath $malformedXml -Value $malformedContent -Encoding UTF8
$malformedFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $malformedXml -PolicyId '{{11111111-1111-1111-1111-111111111111}}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $malformedFailed = $true }
if (-not $malformedFailed) { throw 'Validator accepted malformed brace representation.' }
Remove-Item -LiteralPath $malformedXml -Force -ErrorAction SilentlyContinue
Write-Host '  PASS: malformed braces rejected'

# --- Existing negative fixtures ---
foreach ($name in @('configci_missing_hash.xml', 'configci_duplicate_ruled.xml', 'configci_missing_fileruleref.xml', 'configci_third_file.xml', 'configci_missing_variant.xml')) {
    $failedClosed = $false
    try { Test-ConfigCiSupplementalXml -XmlPath (Join-Path $fixtures $name) -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null } catch { $failedClosed = $true }
    if (-not $failedClosed) { throw "Validator accepted malformed fixture: $name" }
}
Write-Host '  PASS: existing negative fixtures'

Write-Host 'RESULT: PASS'
