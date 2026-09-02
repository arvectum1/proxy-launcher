<# Static contract: every real-stand script must avoid CLM-blocked .NET APIs. #>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$BootstrapDir = (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$production = @(Get-ChildItem -LiteralPath $BootstrapDir -Filter '*.ps1' -File | Where-Object { $_.Name -notlike 'test_*' })
if ($production.Count -eq 0) { throw 'No production scripts found.' }
foreach ($script in $production) {
    $text = Get-Content -LiteralPath $script.FullName -Raw
    foreach ($rule in @(
        @{ pattern='Parameter\s*\(\s*Mandatory'; name='Mandatory parameter' },
        @{ pattern='Get-FileHash'; name='Get-FileHash' },
        @{ pattern='\[xml\]'; name='XML cast' },
        @{ pattern='\.SelectNodes\('; name='XML SelectNodes()' },
        @{ pattern='\.GetAttribute\('; name='XML GetAttribute()' },
        @{ pattern='\.Matches\.'; name='MatchInfo .Matches access' },
        @{ pattern='\.Trim\('; name='String Trim()' },
        @{ pattern='\.TrimStart\('; name='String TrimStart()' },
        @{ pattern='\.TrimEnd\('; name='String TrimEnd()' },
        @{ pattern='\.Substring\('; name='String Substring()' },
        @{ pattern='\.Split\('; name='String Split()' },
        @{ pattern='\.ToLowerInvariant\('; name='String ToLowerInvariant()' },
        @{ pattern='\.ToUpperInvariant\('; name='String ToUpperInvariant()' },
        @{ pattern='\[guid\]'; name='Guid cast' },
        @{ pattern='\[IO\.'; name='System.IO static API' },
        @{ pattern='\[Environment\]::'; name='Environment static API' },
        @{ pattern='Add-Type|Invoke-Expression'; name='dynamic code API' }
    )) {
        if ($text -match $rule.pattern) { throw "$($script.Name) uses CLM-unsafe $($rule.name)." }
    }
}
Write-Host 'RESULT: PASS'
