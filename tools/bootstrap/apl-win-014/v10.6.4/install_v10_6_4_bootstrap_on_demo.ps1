<# Deploys an explicitly supplied V10.6.4 CIP after its identity is checked. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$CipPath = '', [string]$ExpectedCipSha256 = '', [string]$PolicyId = '', [string]$AuthoringEvidencePath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$friendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if ([string]::IsNullOrWhiteSpace($CipPath) -or [string]::IsNullOrWhiteSpace($ExpectedCipSha256) -or [string]::IsNullOrWhiteSpace($PolicyId) -or [string]::IsNullOrWhiteSpace($AuthoringEvidencePath)) { throw 'CipPath, ExpectedCipSha256, PolicyId, and AuthoringEvidencePath are required; this script never prompts.' }
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
if (-not (Test-Path -LiteralPath $CipPath -PathType Leaf)) { throw "CIP not found: $CipPath" }
if (-not (Test-Path -LiteralPath $AuthoringEvidencePath -PathType Leaf)) { throw "Authoring evidence not found: $AuthoringEvidencePath" }
$authoring = Get-Content -LiteralPath $AuthoringEvidencePath -Raw | ConvertFrom-Json
if ($authoring.schema -ne 'arvectum.proxy.apl-win-014-v10.6.4-bootstrap-authoring.v2' -or $authoring.base_policy_id -ne $basePolicyIdText -or $authoring.supplemental_policy_id -ne $PolicyId -or $authoring.supplemental_policy_friendly_name -ne $friendlyName -or $authoring.supplemental_policy_version -ne '10.0.0.17' -or $authoring.supplemental_policy_cip -ne (Split-Path -Leaf $CipPath) -or $authoring.deployment -ne 'NOT PERFORMED') { throw 'Authoring evidence does not exactly bind the requested deployment.' }
if ((Get-Sha256 $CipPath) -ine $ExpectedCipSha256) { throw 'CIP hash mismatch.' }
if ($authoring.supplemental_policy_cip_sha256 -ine $ExpectedCipSha256) { throw 'Authoring evidence CIP hash does not match the requested deployment.' }
$before = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$base = @($before.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText })
if ($before.OperationResult -ne 0 -or $base.Count -ne 1 -or $base[0].BasePolicyID -ne $basePolicyIdText -or $base[0].FriendlyName -ne 'Arvectum APL-WIN-014 Lab Base' -or $base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true -or @($base[0].PolicyOptions | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base validation failed closed.' }
& CiTool.exe --update-policy $CipPath
if ($LASTEXITCODE -ne 0) { throw "CiTool --update-policy failed with exit code $LASTEXITCODE" }
Start-Sleep -Seconds 3
$after = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$deployed = @($after.Policies | Where-Object { $_.PolicyID -eq $PolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq $friendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($after.OperationResult -ne 0 -or $deployed.Count -ne 1) { throw 'V10.6.4 Bootstrap was not uniquely active after deployment.' }
Write-Host "DEPLOYMENT COMPLETE: $PolicyId"
