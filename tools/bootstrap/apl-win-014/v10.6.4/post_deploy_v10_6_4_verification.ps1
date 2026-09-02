<# Read-only V10.6.4 Bootstrap deployment verification with full Audit Mode rejection. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$PolicyId = '', [string]$EvidencePath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$baseFriendlyName = 'Arvectum APL-WIN-014 Lab Base'
$bootstrapFriendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
if ([string]::IsNullOrWhiteSpace($PolicyId) -or [string]::IsNullOrWhiteSpace($EvidencePath)) { throw 'PolicyId and EvidencePath are required; this script never prompts.' }
$policyEvi = Get-ClmPolicyEvidence -ExpectedBasePolicyId $basePolicyIdText -ExpectedBaseFriendlyName $baseFriendlyName -ExpectedBootstrapPolicyId $PolicyId -ExpectedBootstrapFriendlyName $bootstrapFriendlyName
$basePolicy = $policyEvi.base
$bootstrapPolicy = $policyEvi.bootstrap
Test-ClmBasePolicyInvariant -Policy $basePolicy -ExpectedPolicyId $basePolicyIdText -ExpectedBasePolicyId $basePolicyIdText -ExpectedFriendlyName $baseFriendlyName
if ($bootstrapPolicy.policy_id -ne $PolicyId) { throw 'Bootstrap PolicyID does not match expected.' }
if ($bootstrapPolicy.base_policy_id -ne $basePolicyIdText) { throw 'Bootstrap BasePolicyID does not match canonical Lab Base.' }
if ($bootstrapPolicy.friendly_name -ne $bootstrapFriendlyName) { throw 'Bootstrap FriendlyName does not match expected.' }
if ($bootstrapPolicy.is_on_disk -ne $true -or $bootstrapPolicy.is_enforced -ne $true -or $bootstrapPolicy.is_authorized -ne $true) { throw 'Bootstrap policy is not OnDisk/Enforced/Authorized.' }
if ($bootstrapPolicy.policy_options.Count -gt 0) { Test-ClmAuditModeRejection -PolicyOptions $bootstrapPolicy.policy_options -PolicyLabel 'V10.6.4 Bootstrap supplemental' }
$auditPolicies = @($policyEvi.base, $policyEvi.bootstrap)
[ordered]@{
    schema='arvectum.proxy.apl-win-014-v10.6.4-post-deploy-audit.v2'
    result='PASS'
    audited_utc=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    base_policy=[ordered]@{ id=$basePolicy.policy_id; base_id=$basePolicy.base_policy_id; friendly_name=$basePolicy.friendly_name; on_disk=$basePolicy.is_on_disk; enforced=$basePolicy.is_enforced; authorized=$basePolicy.is_authorized; policy_options=$basePolicy.policy_options; audit_mode=$false }
    supplemental_policy=[ordered]@{ id=$bootstrapPolicy.policy_id; base_id=$bootstrapPolicy.base_policy_id; friendly_name=$bootstrapPolicy.friendly_name; version=$bootstrapPolicy.version; on_disk=$bootstrapPolicy.is_on_disk; enforced=$bootstrapPolicy.is_enforced; authorized=$bootstrapPolicy.is_authorized; policy_options=$bootstrapPolicy.policy_options; audit_mode=$false }
    supplemental_policy_id=$PolicyId
    policies=$auditPolicies
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
Get-Content -LiteralPath $EvidencePath -Raw
