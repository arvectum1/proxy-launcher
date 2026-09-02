<# Retires the exact enforced V10.6.2 policy only after its exact V10.6.4 replacement is active. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$RetirePolicyId = '', [string]$ReplacementPolicyId = '', [switch]$ConfirmRetirement)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
if ([string]::IsNullOrWhiteSpace($RetirePolicyId) -or [string]::IsNullOrWhiteSpace($ReplacementPolicyId) -or -not $ConfirmRetirement) { throw 'RetirePolicyId, ReplacementPolicyId, and -ConfirmRetirement are required; this script never prompts.' }
if ($RetirePolicyId -ieq $ReplacementPolicyId) { throw 'RetirePolicyId and ReplacementPolicyId must be different exact policy IDs.' }
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
$result = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$target = @($result.Policies | Where-Object { $_.PolicyID -eq $RetirePolicyId })
if ($result.OperationResult -ne 0 -or $target.Count -ne 1) { throw 'Retirement target is not unique.' }
if ($target[0].BasePolicyID -ne $basePolicyIdText -or $target[0].FriendlyName -ne 'Arvectum APL-WIN-014 Harness V10.6.2 Bootstrap') { throw 'Retirement target is not the canonical V10.6.2 Bootstrap policy.' }
if ($target[0].IsOnDisk -ne $true -or $target[0].IsEnforced -ne $true -or $target[0].IsAuthorized -ne $true) { throw 'V10.6.2 target is not the expected enforced retirement state.' }
$replacement = @($result.Policies | Where-Object { $_.PolicyID -eq $ReplacementPolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap' -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($replacement.Count -ne 1) { throw 'The exact V10.6.4 replacement policy is not uniquely active, enforced, and authorized.' }
& CiTool.exe --remove-policy $RetirePolicyId
if ($LASTEXITCODE -ne 0) { throw "CiTool --remove-policy failed with exit code $LASTEXITCODE" }
$after = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
if ($after.OperationResult -ne 0 -or @($after.Policies | Where-Object { $_.PolicyID -eq $RetirePolicyId }).Count -ne 0) { throw 'V10.6.2 policy remains after retirement.' }
$replacementAfter = @($after.Policies | Where-Object { $_.PolicyID -eq $ReplacementPolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap' -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($replacementAfter.Count -ne 1) { throw 'V10.6.4 replacement policy is not uniquely active after retirement.' }
Write-Host "V10.6.2 RETIREMENT COMPLETE: $RetirePolicyId; V10.6.4 replacement remains enforced: $ReplacementPolicyId"
