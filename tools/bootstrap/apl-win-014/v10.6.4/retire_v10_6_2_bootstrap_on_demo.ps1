<# Safely retires only an explicitly identified, inactive V10.6.2 supplemental policy. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$RetirePolicyId = '', [switch]$ConfirmRetirement)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
if ([string]::IsNullOrWhiteSpace($RetirePolicyId) -or -not $ConfirmRetirement) { throw 'RetirePolicyId and -ConfirmRetirement are required; this script never prompts.' }
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
$result = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$target = @($result.Policies | Where-Object { $_.PolicyID -eq $RetirePolicyId })
if ($result.OperationResult -ne 0 -or $target.Count -ne 1) { throw 'Retirement target is not unique.' }
if ($target[0].BasePolicyID -ne $basePolicyIdText -or $target[0].FriendlyName -ne 'Arvectum APL-WIN-014 Harness V10.6.2 Bootstrap') { throw 'Retirement target is not the canonical V10.6.2 Bootstrap policy.' }
if ($target[0].IsEnforced -eq $true) { throw 'Refusing to retire an enforced policy; establish and verify replacement coverage first.' }
& CiTool.exe --remove-policy $RetirePolicyId
if ($LASTEXITCODE -ne 0) { throw "CiTool --remove-policy failed with exit code $LASTEXITCODE" }
$after = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
if ($after.OperationResult -ne 0 -or @($after.Policies | Where-Object { $_.PolicyID -eq $RetirePolicyId }).Count -ne 0) { throw 'V10.6.2 policy remains after retirement.' }
Write-Host "V10.6.2 RETIREMENT COMPLETE: $RetirePolicyId"
