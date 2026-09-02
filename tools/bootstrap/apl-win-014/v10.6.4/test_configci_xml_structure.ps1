<# Fixture regression test for ConfigCI Allow Hash attributes and supplemental semantics. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'configci_xml_validation.ps1')
$fixtures = Join-Path $scriptDir 'fixtures'
$fixture = Join-Path $fixtures 'configci_real_xml_structure.xml'
$rules = @(Select-String -LiteralPath $fixture -Pattern '<Allow\s+[^>]*Hash="[^"]+"')
$refs = @(Select-String -LiteralPath $fixture -Pattern '<FileRuleRef RuleID="ID_ALLOW_A_\d+"')
if ($rules.Count -ne 8 -or $refs.Count -ne 8) { throw 'Real ConfigCI fixture does not have eight hash rules and references.' }
Test-ConfigCiSupplementalXml -XmlPath $fixture -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null
foreach ($name in @('configci_missing_hash.xml', 'configci_duplicate_ruled.xml', 'configci_missing_fileruleref.xml', 'configci_third_file.xml', 'configci_missing_variant.xml')) {
    $failedClosed = $false
    try { Test-ConfigCiSupplementalXml -XmlPath (Join-Path $fixtures $name) -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null } catch { $failedClosed = $true }
    if (-not $failedClosed) { throw "Validator accepted malformed fixture: $name" }
}
$selfRefXml = Join-Path $fixtures 'configci_self_reference.xml'
$selfRefContent = $fixture -replace '<PolicyID>\{11111111-1111-1111-1111-111111111111\}</PolicyID><BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>', '<PolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</PolicyID><BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>'
Set-Content -LiteralPath $selfRefXml -Value $selfRefContent -Encoding UTF8
$selfRefFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $selfRefXml -PolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $selfRefFailed = $true }
if (-not $selfRefFailed) { throw 'Validator accepted self-referencing PolicyID/BasePolicyID.' }
Remove-Item -LiteralPath $selfRefXml -Force -ErrorAction SilentlyContinue
$wrongBaseXml = Join-Path $fixtures 'configci_wrong_base.xml'
$wrongBaseContent = $fixture -replace '<BasePolicyID>dc1c604c-46ea-40b7-9f47-cf582b225d5e</BasePolicyID>', '<BasePolicyID>00000000-0000-0000-0000-000000000000</BasePolicyID>'
Set-Content -LiteralPath $wrongBaseXml -Value $wrongBaseContent -Encoding UTF8
$wrongBaseFailed = $false
try { Test-ConfigCiSupplementalXml -XmlPath $wrongBaseXml -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') } catch { $wrongBaseFailed = $true }
if (-not $wrongBaseFailed) { throw 'Validator accepted wrong BasePolicyID.' }
Remove-Item -LiteralPath $wrongBaseXml -Force -ErrorAction SilentlyContinue
Write-Host 'RESULT: PASS'
