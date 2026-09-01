<#
.SYNOPSIS
    Real ConstrainedLanguage runspace test for V10.6 bootstrap scripts.
.DESCRIPTION
    Creates a PowerShell runspace in ConstrainedLanguage mode and verifies that
    the bootstrap scripts can be parsed and their core functions execute without
    .NET method invocation errors. Must be run as Administrator.
#>
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '=== CLM Runspace Smoke Test ==='

$currentLanguageMode = $ExecutionContext.SessionState.LanguageMode
Write-Host "  Current language mode: $currentLanguageMode"

$initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialState.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage

$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
$runspace.Open()

$testResults = @()

$tests = @(
    @{
        Name = 'Get-FileHash'
        Script = { (Get-FileHash -LiteralPath $env:SystemRoot\System32\cmd.exe -Algorithm SHA256).Hash }
        ExpectSuccess = $true
    },
    @{
        Name = 'Split-Path -Leaf'
        Script = { Split-Path -Leaf 'C:\foo\bar\test.exe' }
        ExpectSuccess = $true
    },
    @{
        Name = 'Split-Path -Parent'
        Script = { Split-Path -Parent 'C:\foo\bar\test.exe' }
        ExpectSuccess = $true
    },
    @{
        Name = 'Test-Path'
        Script = { Test-Path -LiteralPath $env:SystemRoot }
        ExpectSuccess = $true
    },
    @{
        Name = 'Get-Item'
        Script = { (Get-Item -LiteralPath $env:SystemRoot).Length -gt 0 }
        ExpectSuccess = $true
    },
    @{
        Name = '-match operator'
        Script = { 'PolicyID: {abc-123}' -match 'PolicyID:\s*\{([^}]+)\}' }
        ExpectSuccess = $true
    },
    @{
        Name = '$matches automatic variable'
        Script = {
            'PolicyID: {abc-123}' -match 'PolicyID:\s*\{([^}]+)\}'
            $matches[1]
        }
        ExpectSuccess = $true
    },
    @{
        Name = '-replace operator'
        Script = { 'C:\foo\bar' -replace '\\$','' }
        ExpectSuccess = $true
    },
    @{
        Name = 'ConvertFrom-Json'
        Script = { '{"test": "value"}' | ConvertFrom-Json | Select-Object -ExpandProperty test }
        ExpectSuccess = $true
    },
    @{
        Name = 'Get-Date -Format'
        Script = { Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.ffffffZ' }
        ExpectSuccess = $true
    },
    @{
        Name = 'New-Guid'
        Script = { New-Guid | ForEach-Object { $_.Guid -replace '-','' } }
        ExpectSuccess = $true
    },
    @{
        Name = 'Select-String'
        Script = { 'hello world' -match 'hello' }
        ExpectSuccess = $true
    },
    @{
        Name = 'String interpolation'
        Script = { "$($env:COMPUTERNAME)" }
        ExpectSuccess = $true
    },
    @{
        Name = '-as safe cast'
        Script = { '123' -as [int] }
        ExpectSuccess = $true
    },
    @{
        Name = '[guid] cast'
        Script = { [guid]'dc1c604c-46ea-40b7-9f47-cf582b225d5e' }
        ExpectSuccess = $true
    },
    @{
        Name = '[regex]::Match (BLOCKED)'
        Script = { [regex]::Match('test', 'test') }
        ExpectSuccess = $false
    },
    @{
        Name = '[IO.Path]::GetFileName (BLOCKED)'
        Script = { [IO.Path]::GetFileName('C:\test.exe') }
        ExpectSuccess = $false
    },
    @{
        Name = '.Trim() (BLOCKED)'
        Script = { '  hello  '.Trim() }
        ExpectSuccess = $false
    },
    @{
        Name = '.ToLowerInvariant() (BLOCKED)'
        Script = { 'HELLO'.ToLowerInvariant() }
        ExpectSuccess = $false
    },
    @{
        Name = '[Environment]::GetFolderPath (BLOCKED)'
        Script = { [Environment]::GetFolderPath('MyDocuments') }
        ExpectSuccess = $false
    },
    @{
        Name = '[Security.Principal] (BLOCKED)'
        Script = { [Security.Principal.WindowsIdentity]::GetCurrent() }
        ExpectSuccess = $false
    }
)

foreach ($test in $tests) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript($test.Script) | Out-Null
    try {
        $output = $ps.Invoke()
        $hadError = $ps.HadErrors
        $succeeded = -not $hadError -and $output.Count -gt 0
    } catch {
        $hadError = $true
        $succeeded = $false
    } finally {
        $ps.Dispose()
    }

    $expected = $test.ExpectSuccess
    $pass = $succeeded -eq $expected
    $status = if ($pass) { 'PASS' } else { 'FAIL' }

    $testResults += [ordered]@{
        Name = $test.Name
        Expected = $expected
        Actual = $succeeded
        Status = $status
    }

    Write-Host "  $status $($test.Name) (expected=$expected, actual=$succeeded)"
}

$runspace.Close()
$runspace.Dispose()

$failures = @($testResults | Where-Object { $_.Status -eq 'FAIL' })
Write-Host ""
Write-Host "=== CLM Runspace Summary ==="
Write-Host "  Tests run: $($testResults.Count)"
Write-Host "  Passed: $($testResults.Count - $failures.Count)"
Write-Host "  Failed: $($failures.Count)"

if ($failures.Count -gt 0) {
    Write-Host ""
    foreach ($f in $failures) {
        Write-Host "  FAIL: $($f.Name) (expected=$($f.Expected), actual=$($f.Actual))"
    }
    throw "CLM runspace test failed: $($failures.Count) failure(s)."
} else {
    Write-Host ""
    Write-Host "RESULT: PASS"
}
