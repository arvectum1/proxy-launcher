<# Read-only V10.6.4 Bootstrap deployment verification. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$PolicyId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$friendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
if ([string]::IsNullOrWhiteSpace($PolicyId)) { throw 'PolicyId is required; this script never prompts.' }
$result = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$base = @($result.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText })
$bootstrap = @($result.Policies | Where-Object { $_.PolicyID -eq $PolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq $friendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($result.OperationResult -ne 0 -or $base.Count -ne 1 -or $base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true) { throw 'Canonical Lab Base validation failed closed.' }
if ($bootstrap.Count -ne 1) { throw 'V10.6.4 Bootstrap policy is not uniquely active, enforced, and authorized.' }
[ordered]@{ result='PASS'; base_policy_id=$basePolicyIdText; supplemental_policy_id=$PolicyId; candidate_harness='V10.6.4' } | ConvertTo-Json -Compress
