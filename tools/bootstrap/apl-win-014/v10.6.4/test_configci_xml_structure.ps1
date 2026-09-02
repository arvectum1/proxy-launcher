<# Fixture regression test for ConfigCI Allow Hash attributes. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'configci_xml_validation.ps1')
$fixture = Join-Path (Join-Path $scriptDir 'fixtures') 'configci_real_xml_structure.xml'
$rules = @(Select-String -LiteralPath $fixture -Pattern '<Allow\s+[^>]*Hash="[^"]+"')
$refs = @(Select-String -LiteralPath $fixture -Pattern '<FileRuleRef RuleID="ID_ALLOW_A_\d+"')
if ($rules.Count -ne 8 -or $refs.Count -ne 8) { throw 'Real ConfigCI fixture does not have eight hash rules and references.' }
Test-ConfigCiSupplementalXml -XmlPath $fixture -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null
Write-Host 'RESULT: PASS'
