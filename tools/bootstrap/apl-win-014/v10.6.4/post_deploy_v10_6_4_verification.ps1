<# Read-only V10.6.4 Bootstrap deployment verification. #>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$PolicyId = '', [string]$EvidencePath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$basePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$friendlyName = 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
if ([string]::IsNullOrWhiteSpace($PolicyId) -or [string]::IsNullOrWhiteSpace($EvidencePath)) { throw 'PolicyId and EvidencePath are required; this script never prompts.' }
$result = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$base = @($result.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText })
$bootstrap = @($result.Policies | Where-Object { $_.PolicyID -eq $PolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq $friendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($result.OperationResult -ne 0 -or $base.Count -ne 1 -or $base[0].BasePolicyID -ne $basePolicyIdText -or $base[0].FriendlyName -ne 'Arvectum APL-WIN-014 Lab Base' -or $base[0].IsOnDisk -ne $true -or $base[0].IsEnforced -ne $true -or $base[0].IsAuthorized -ne $true -or @($base[0].PolicyOptions | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base validation failed closed.' }
if ($bootstrap.Count -ne 1) { throw 'V10.6.4 Bootstrap policy is not uniquely active, enforced, and authorized.' }
$audit = @($result.Policies | Where-Object { $_.BasePolicyID -eq $basePolicyIdText } | Select-Object PolicyID, BasePolicyID, FriendlyName, Version, IsOnDisk, IsEnforced, IsAuthorized, PolicyOptions)
[ordered]@{ schema='arvectum.proxy.apl-win-014-v10.6.4-post-deploy-audit.v1'; result='PASS'; audited_utc=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'); base_policy_id=$basePolicyIdText; base_policy_friendly_name=$base[0].FriendlyName; base_policy_options=@($base[0].PolicyOptions); supplemental_policy_id=$PolicyId; supplemental_policy_friendly_name=$friendlyName; supplemental_policy_version=$bootstrap[0].Version; policies=$audit } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
Get-Content -LiteralPath $EvidencePath -Raw
