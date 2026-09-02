<# Retires the exact enforced V10.6.2 policy only after its exact V10.6.4 replacement is active. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$RetirePolicyId = '', [string]$ReplacementPolicyId = '', [string]$V1062AuthoringEvidencePath = '', [switch]$ConfirmRetirement)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
if ([string]::IsNullOrWhiteSpace($RetirePolicyId) -or [string]::IsNullOrWhiteSpace($ReplacementPolicyId) -or [string]::IsNullOrWhiteSpace($V1062AuthoringEvidencePath) -or -not $ConfirmRetirement) { throw 'RetirePolicyId, ReplacementPolicyId, V1062AuthoringEvidencePath, and -ConfirmRetirement are required; this script never prompts.' }
if ($RetirePolicyId -ieq $ReplacementPolicyId) { throw 'RetirePolicyId and ReplacementPolicyId must be different exact policy IDs.' }
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
if (-not (Test-Path -LiteralPath $V1062AuthoringEvidencePath -PathType Leaf)) { throw "V10.6.2 authoring evidence not found: $V1062AuthoringEvidencePath" }
$oldAuthoring = Get-Content -LiteralPath $V1062AuthoringEvidencePath -Raw | ConvertFrom-Json
if ($oldAuthoring.schema -ne 'arvectum.proxy.apl-win-014-v10.6.2-bootstrap-authoring.v1' -or $oldAuthoring.base_policy_id -ne $basePolicyIdText -or $oldAuthoring.supplemental_policy_id -ne $RetirePolicyId -or $oldAuthoring.supplemental_policy_friendly_name -ne 'Arvectum APL-WIN-014 Harness V10.6.2 Bootstrap' -or $oldAuthoring.supplemental_policy_version -ne '10.0.0.16') { throw 'RetirePolicyId is not hard-bound to canonical V10.6.2 authoring evidence.' }
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
$baseAfter = @($after.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq 'Arvectum APL-WIN-014 Lab Base' -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($baseAfter.Count -ne 1 -or @($baseAfter[0].PolicyOptions | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base validation failed after retirement.' }
$replacementAfter = @($after.Policies | Where-Object { $_.PolicyID -eq $ReplacementPolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap' -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($replacementAfter.Count -ne 1) { throw 'V10.6.4 replacement policy is not uniquely active after retirement.' }
Write-Host "V10.6.2 RETIREMENT COMPLETE: $RetirePolicyId; V10.6.4 replacement remains enforced: $ReplacementPolicyId"
