<# Fixture regression test for the real CiTool schema used by V10.6.4. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures') 'citool_real_schema.json'
$parsed = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json
$base = @($parsed.Policies | Where-Object { $_.PolicyID -eq 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' })
if ($parsed.OperationResult -ne 0 -or $base.Count -ne 1 -or $base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true) { throw 'Real CiTool fixture failed canonical base validation.' }
Write-Host 'RESULT: PASS'
