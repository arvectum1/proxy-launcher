<# Deploys an explicitly supplied V10.6.4 CIP after its identity is checked. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$CipPath = '', [string]$ExpectedCipSha256 = '', [string]$PolicyId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$friendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if ([string]::IsNullOrWhiteSpace($CipPath) -or [string]::IsNullOrWhiteSpace($ExpectedCipSha256) -or [string]::IsNullOrWhiteSpace($PolicyId)) { throw 'CipPath, ExpectedCipSha256, and PolicyId are required; this script never prompts.' }
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
if (-not (Test-Path -LiteralPath $CipPath -PathType Leaf)) { throw "CIP not found: $CipPath" }
if ((Get-Sha256 $CipPath) -ine $ExpectedCipSha256) { throw 'CIP hash mismatch.' }
$before = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$base = @($before.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText })
if ($before.OperationResult -ne 0 -or $base.Count -ne 1 -or $base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true) { throw 'Canonical Lab Base validation failed closed.' }
& CiTool.exe --update-policy $CipPath
if ($LASTEXITCODE -ne 0) { throw "CiTool --update-policy failed with exit code $LASTEXITCODE" }
Start-Sleep -Seconds 3
$after = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$deployed = @($after.Policies | Where-Object { $_.PolicyID -eq $PolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq $friendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($after.OperationResult -ne 0 -or $deployed.Count -ne 1) { throw 'V10.6.4 Bootstrap was not uniquely active after deployment.' }
Write-Host "DEPLOYMENT COMPLETE: $PolicyId"
