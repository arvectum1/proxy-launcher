<#
.SYNOPSIS
    Static CLM contract test for V10.6 bootstrap scripts.
.DESCRIPTION
    Validates that all production PowerShell scripts in the bootstrap package use only
    ConstrainedLanguage-safe patterns. Excludes test infrastructure files.
    Does NOT modify any files.
#>
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BootstrapDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BootstrapDir -PathType Container)) {
    throw "Bootstrap directory not found: $BootstrapDir"
}

$excludePatterns = @('test_*.ps1', '*_test.ps1', 'CLM_*.ps1', 'upgrade_helper.ps1', 'uninstall_helper.ps1')
$allScripts = Get-ChildItem -LiteralPath $BootstrapDir -Filter '*.ps1' -File
$scripts = @($allScripts | Where-Object {
    $excluded = $false
    foreach ($ep in $excludePatterns) {
        if ($_.Name -like $ep) { $excluded = $true; break }
    }
    -not $excluded
})

if ($scripts.Count -eq 0) { throw "No production .ps1 files found in $BootstrapDir" }

Write-Host "=== CLM Contract Test: $($scripts.Count) production scripts ==="

$forbiddenPatterns = @(
    @{ Pattern = '\.ToLowerInvariant\(\)'; Name = '.ToLowerInvariant()'; Severity = 'HIGH' },
    @{ Pattern = '\.ToUpperInvariant\(\)'; Name = '.ToUpperInvariant()'; Severity = 'HIGH' },
    @{ Pattern = '\.Trim\(\)'; Name = '.Trim()'; Severity = 'HIGH' },
    @{ Pattern = '\.TrimStart\('; Name = '.TrimStart('; Severity = 'HIGH' },
    @{ Pattern = '\.TrimEnd\('; Name = '.TrimEnd('; Severity = 'HIGH' },
    @{ Pattern = '\.Substring\('; Name = '.Substring('; Severity = 'HIGH' },
    @{ Pattern = '\.Split\('; Name = '.Split('; Severity = 'HIGH' },
    @{ Pattern = '\.Replace\('; Name = '.Replace('; Severity = 'HIGH' },
    @{ Pattern = '\.Contains\('; Name = '.Contains('; Severity = 'HIGH' },
    @{ Pattern = '\.StartsWith\('; Name = '.StartsWith('; Severity = 'HIGH' },
    @{ Pattern = '\.EndsWith\('; Name = '.EndsWith('; Severity = 'HIGH' },
    @{ Pattern = '\.ToString\('; Name = '.ToString('; Severity = 'HIGH' },
    @{ Pattern = '\.Equals\('; Name = '.Equals('; Severity = 'HIGH' },
    @{ Pattern = '\.GetEnumerator\(\)'; Name = '.GetEnumerator()'; Severity = 'HIGH' },
    @{ Pattern = '\[regex\]::'; Name = '[regex]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[IO\.Path\]::'; Name = '[IO.Path]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[System\.IO\.Path\]::'; Name = '[System.IO.Path]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[IO\.File\]::'; Name = '[IO.File]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[Environment\]::'; Name = '[Environment]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[Security\.Principal\]'; Name = '[Security.Principal] type'; Severity = 'CRITICAL' },
    @{ Pattern = '\[System\.Security\.\w+\]::'; Name = '[System.Security]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[BitConverter\]::'; Name = '[BitConverter]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[DateTime\]::'; Name = '[DateTime]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[int\]::'; Name = '[int]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[long\]::'; Name = '[long]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[guid\]::'; Name = '[guid]:: static call'; Severity = 'HIGH' },
    @{ Pattern = '\[Guid\]::'; Name = '[Guid]:: static call'; Severity = 'HIGH' },
    @{ Pattern = 'Add-Type'; Name = 'Add-Type'; Severity = 'CRITICAL' },
    @{ Pattern = 'Invoke-Expression'; Name = 'Invoke-Expression'; Severity = 'CRITICAL' },
    @{ Pattern = '\.VersionInfo\.'; Name = '.VersionInfo. chained access'; Severity = 'MEDIUM' },
    @{ Pattern = '\.PSObject\.Properties\['; Name = '.PSObject.Properties[] indexer'; Severity = 'HIGH' },
    @{ Pattern = '\[pscustomobject\]'; Name = '[pscustomobject] cast'; Severity = 'MEDIUM' },
    @{ Pattern = '\[xml\]\$'; Name = '[xml] cast'; Severity = 'HIGH' },
    @{ Pattern = '\[IO\.FileAttributes\]::'; Name = '[IO.FileAttributes] enum access'; Severity = 'MEDIUM' },
    @{ Pattern = '\.ComputeHash\('; Name = '.ComputeHash()'; Severity = 'HIGH' },
    @{ Pattern = '\.Dispose\(\)'; Name = '.Dispose()'; Severity = 'HIGH' },
    @{ Pattern = '\[IO\.FileMode\]::'; Name = '[IO.FileMode] enum access'; Severity = 'HIGH' },
    @{ Pattern = '\[IO\.FileAccess\]::'; Name = '[IO.FileAccess] enum access'; Severity = 'HIGH' },
    @{ Pattern = '\[IO\.FileShare\]::'; Name = '[IO.FileShare] enum access'; Severity = 'HIGH' },
    @{ Pattern = 'New-Object System\.Xml\.'; Name = 'New-Object System.Xml'; Severity = 'HIGH' },
    @{ Pattern = '\.SelectNodes\('; Name = '.SelectNodes()'; Severity = 'HIGH' },
    @{ Pattern = '\.AddNamespace\('; Name = '.AddNamespace()'; Severity = 'HIGH' },
    @{ Pattern = '\.DocumentElement'; Name = '.DocumentElement'; Severity = 'HIGH' },
    @{ Pattern = '\.NameTable'; Name = '.NameTable'; Severity = 'HIGH' }
)

$failed = $false
$results = @()

foreach ($script in $scripts) {
    Write-Host ""
    Write-Host "--- $($script.Name) ---"
    $lines = Get-Content -LiteralPath $script.FullName -Encoding UTF8
    $scriptFailed = $false

    foreach ($fp in $forbiddenPatterns) {
        $violations = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $fp.Pattern) {
                $content = $lines[$i] -replace '^\s+|\s+$',''
                $violations += @{ Line = $i + 1; Content = $content }
            }
        }
        if ($violations.Count -gt 0) {
            $failed = $true
            $scriptFailed = $true
            foreach ($v in $violations) {
                Write-Host "  FAIL [$($fp.Severity)] $($fp.Name) at line $($v.Line): $($v.Content)"
                $results += [ordered]@{
                    script = $script.Name
                    line = $v.Line
                    pattern = $fp.Name
                    severity = $fp.Severity
                    content = $v.Content
                }
            }
        }
    }

    if (-not $scriptFailed) {
        Write-Host "  PASS"
    }
}

Write-Host ""
Write-Host "=== CLM Contract Summary ==="
Write-Host "  Production scripts scanned: $($scripts.Count)"
Write-Host "  Violations found: $($results.Count)"

if ($failed) {
    Write-Host ""
    Write-Host "RESULT: FAIL"
    foreach ($r in $results) {
        Write-Host "  $($r.script):$($r.line) [$($r.severity)] $($r.pattern)"
    }
    throw "CLM contract test failed: $($results.Count) violation(s) found."
} else {
    Write-Host ""
    Write-Host "RESULT: PASS"
}
