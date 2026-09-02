<# Smoke test for the CLM-safe certutil hash parser primitives. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialState.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage
$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
$runspace.Open()
$ps = [System.Management.Automation.PowerShell]::Create()
$ps.Runspace = $runspace
$ps.AddScript("'ABC' -replace 'A','a'") | Out-Null
$output = $ps.Invoke()
$ps.Dispose(); $runspace.Close(); $runspace.Dispose()
if ($output.Count -ne 1 -or $output[0] -ne 'aBC') { throw 'ConstrainedLanguage smoke test failed.' }
Write-Host 'RESULT: PASS'
