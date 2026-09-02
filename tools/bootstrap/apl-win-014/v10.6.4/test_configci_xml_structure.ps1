<# Fixture regression test for ConfigCI Allow Hash attributes. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures') 'configci_real_xml_structure.xml'
$rules = @(Select-String -LiteralPath $fixture -Pattern '<Allow\s+[^>]*Hash="[^"]+"')
$refs = @(Select-String -LiteralPath $fixture -Pattern '<FileRuleRef RuleID="ID_ALLOW_A_\d+"')
if ($rules.Count -ne 8 -or $refs.Count -ne 8) { throw 'Real ConfigCI fixture does not have eight hash rules and references.' }
Write-Host 'RESULT: PASS'
