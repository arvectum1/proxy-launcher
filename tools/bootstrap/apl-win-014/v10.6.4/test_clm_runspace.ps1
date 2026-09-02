<# Runs the shared ConfigCI validator against real fixtures in ConstrainedLanguage. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialState.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage
$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
$runspace.Open()
$ps = [System.Management.Automation.PowerShell]::Create()
$ps.Runspace = $runspace
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$validator = Join-Path $scriptDir 'configci_xml_validation.ps1'
$fixture = Join-Path (Join-Path $scriptDir 'fixtures') 'configci_real_xml_structure.xml'
$ps.AddScript(". '$validator'; Test-ConfigCiSupplementalXml -XmlPath '$fixture' -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe')") | Out-Null
$output = $ps.Invoke()
$hadErrors = $ps.HadErrors
$ps.Dispose(); $runspace.Close(); $runspace.Dispose()
if ($hadErrors -or $output.Count -ne 1 -or $output[0] -ne $true) { throw 'ConstrainedLanguage ConfigCI validator test failed.' }
Write-Host 'RESULT: PASS'
