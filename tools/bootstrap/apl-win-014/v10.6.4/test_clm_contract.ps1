<# Static contract: V10.6.4 real-stand scripts must use certutil and never prompt. #>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$BootstrapDir = (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$production = @(Get-ChildItem -LiteralPath $BootstrapDir -Filter '*.ps1' -File | Where-Object { $_.Name -notlike 'test_*' -and $_.Name -ne 'validate_v10_6_4_candidate.ps1' })
if ($production.Count -eq 0) { throw 'No production scripts found.' }
foreach ($script in $production) {
    $text = Get-Content -LiteralPath $script.FullName -Raw
    if ($text -match 'Parameter\s*\(\s*Mandatory') { throw "$($script.Name) has a Mandatory parameter." }
    if ($text -match 'Get-FileHash') { throw "$($script.Name) uses Get-FileHash instead of CLM-safe certutil." }
}
Write-Host 'RESULT: PASS'
