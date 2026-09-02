<# Retires the exact enforced V10.6.2 policy only after its exact V10.6.4 replacement is active. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$RetirePolicyId = '', [string]$ReplacementPolicyId = '', [string]$V1062AuthoringEvidencePath = '', [switch]$ConfirmRetirement)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$expectedRetirePolicyId = '11b32707-8981-4fe6-a852-3175aa1ac2bb'
$expectedRetireFriendlyName = 'Arvectum APL-WIN-014 Harness V10.6.2 Bootstrap'
$expectedRetireVersion = '10.0.0.16'
$replacementFriendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if ([string]::IsNullOrWhiteSpace($RetirePolicyId) -or [string]::IsNullOrWhiteSpace($ReplacementPolicyId) -or [string]::IsNullOrWhiteSpace($V1062AuthoringEvidencePath) -or -not $ConfirmRetirement) { throw 'RetirePolicyId, ReplacementPolicyId, V1062AuthoringEvidencePath, and -ConfirmRetirement are required; this script never prompts.' }
$normalizedRetirePolicyId = Convert-ClmPolicyGuidIdentity $RetirePolicyId
$normalizedReplacementPolicyId = Convert-ClmPolicyGuidIdentity $ReplacementPolicyId
$normalizedBasePolicyId = Convert-ClmPolicyGuidIdentity $basePolicyIdText
if ($normalizedRetirePolicyId -ieq $normalizedReplacementPolicyId) { throw 'RetirePolicyId and ReplacementPolicyId must be different policy identities.' }
if ($normalizedRetirePolicyId -ine (Convert-ClmPolicyGuidIdentity $expectedRetirePolicyId)) { throw "RetirePolicyId must be the canonical V10.6.2 policy: $expectedRetirePolicyId" }
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
if (-not (Test-Path -LiteralPath $V1062AuthoringEvidencePath -PathType Leaf)) { throw "V10.6.2 authoring evidence not found: $V1062AuthoringEvidencePath" }
$oldAuthoring = Get-Content -LiteralPath $V1062AuthoringEvidencePath -Raw | ConvertFrom-Json
if ($oldAuthoring.schema -ne 'arvectum.proxy.apl-win-014-v10.6.2-bootstrap-authoring.v1' -or (Convert-ClmPolicyGuidIdentity $oldAuthoring.base_policy_id) -ine $normalizedBasePolicyId -or (Convert-ClmPolicyGuidIdentity $oldAuthoring.supplemental_policy_id) -ine $normalizedRetirePolicyId -or $oldAuthoring.supplemental_policy_friendly_name -ne $expectedRetireFriendlyName -or $oldAuthoring.supplemental_policy_version -ne $expectedRetireVersion) { throw 'Authoring evidence does not match the canonical V10.6.2 policy.' }
$result = & CiTool.exe -lp -json 2>$null | ConvertFrom-Json
$target = @($result.Policies | Where-Object { (Convert-ClmPolicyGuidIdentity "$($_.PolicyID)") -ieq $normalizedRetirePolicyId })
if ($result.OperationResult -ne 0 -or $target.Count -ne 1) { throw 'Retirement target is not unique.' }
if ((Convert-ClmPolicyGuidIdentity "$($target[0].BasePolicyID)") -ine $normalizedBasePolicyId -or $target[0].FriendlyName -ne $expectedRetireFriendlyName) { throw 'Retirement target is not the canonical V10.6.2 Bootstrap policy.' }
if ($target[0].IsOnDisk -ne $true -or $target[0].IsEnforced -ne $true -or $target[0].IsAuthorized -ne $true) { throw 'V10.6.2 target is not the expected enforced retirement state.' }
$replacement = @($result.Policies | Where-Object { (Convert-ClmPolicyGuidIdentity "$($_.PolicyID)") -ieq $normalizedReplacementPolicyId -and (Convert-ClmPolicyGuidIdentity "$($_.BasePolicyID)") -ieq $normalizedBasePolicyId -and $_.FriendlyName -eq $replacementFriendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($replacement.Count -ne 1) { throw 'The exact V10.6.4 replacement policy is not uniquely active, enforced, and authorized.' }
if ($replacement[0].PolicyOptions.Count -gt 0) { Test-ClmAuditModeRejection -PolicyOptions @($replacement[0].PolicyOptions) -PolicyLabel 'V10.6.4 replacement supplemental' }
& CiTool.exe --remove-policy $expectedRetirePolicyId
if ($LASTEXITCODE -ne 0) { throw "CiTool --remove-policy failed with exit code $LASTEXITCODE" }
$after = & CiTool.exe -lp -json 2>$null | ConvertFrom-Json
if ($after.OperationResult -ne 0 -or @($after.Policies | Where-Object { (Convert-ClmPolicyGuidIdentity "$($_.PolicyID)") -ieq $normalizedRetirePolicyId }).Count -ne 0) { throw 'V10.6.2 policy remains after retirement.' }
$baseAfter = @($after.Policies | Where-Object { (Convert-ClmPolicyGuidIdentity "$($_.PolicyID)") -ieq $normalizedBasePolicyId -and (Convert-ClmPolicyGuidIdentity "$($_.BasePolicyID)") -ieq $normalizedBasePolicyId -and $_.FriendlyName -eq 'Arvectum APL-WIN-014 Lab Base' -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($baseAfter.Count -ne 1) { throw 'Canonical Lab Base not uniquely present after retirement.' }
if (@($baseAfter[0].PolicyOptions | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base missing Allow Supplemental Policies after retirement.' }
Test-ClmAuditModeRejection -PolicyOptions @($baseAfter[0].PolicyOptions) -PolicyLabel 'Canonical Lab Base post-retirement'
$replacementAfter = @($after.Policies | Where-Object { (Convert-ClmPolicyGuidIdentity "$($_.PolicyID)") -ieq $normalizedReplacementPolicyId -and (Convert-ClmPolicyGuidIdentity "$($_.BasePolicyID)") -ieq $normalizedBasePolicyId -and $_.FriendlyName -eq $replacementFriendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($replacementAfter.Count -ne 1) { throw 'V10.6.4 replacement policy is not uniquely active after retirement.' }
if ($replacementAfter[0].PolicyOptions.Count -gt 0) { Test-ClmAuditModeRejection -PolicyOptions @($replacementAfter[0].PolicyOptions) -PolicyLabel 'V10.6.4 replacement post-retirement' }
Write-Host "V10.6.2 RETIREMENT COMPLETE: $expectedRetirePolicyId; V10.6.4 replacement remains enforced: $ReplacementPolicyId"
