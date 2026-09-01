<#
.SYNOPSIS
    Post-deploy verification for V10.6.3 Bootstrap supplemental policy.
.DESCRIPTION
    Verifies that V10.6.3 is active/enforced/authorized after deployment.
    Does NOT modify any policies.
    Written for Windows PowerShell 5.1 ConstrainedLanguage mode.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'

$c = Get-Command CiTool.exe -ErrorAction SilentlyContinue
if (-not $c) { throw 'CiTool.exe not found.' }

Write-Host '=== Querying CiTool (real schema) ==='
$raw = & CiTool.exe -lp -json 2>$null
$policies = $raw | ConvertFrom-Json

if ($null -eq $policies.OperationResult) { throw 'CiTool output missing OperationResult. FAIL CLOSED.' }
if ($policies.OperationResult -ne 0) { throw "CiTool OperationResult=$($policies.OperationResult). FAIL CLOSED." }
Write-Host "  OperationResult: $($policies.OperationResult)"

$base = @($policies.Policies | Where-Object { $_.PolicyID -eq $BasePolicyIdText })
if ($base.Count -ne 1) { throw "Lab Base policy not found: $BasePolicyIdText. FAIL CLOSED." }
$b = $base[0]
if ($b.IsOnDisk -ne $true) { throw 'Lab Base is not on-disk. FAIL CLOSED.' }
if ($b.IsEnforced -ne $true) { throw 'Lab Base is not enforced. FAIL CLOSED.' }
Write-Host "  Base PolicyID: $($b.PolicyID) IsOnDisk=$($b.IsOnDisk) IsEnforced=$($b.IsEnforced)"

$supplementals = @($policies.Policies | Where-Object { $_.BasePolicyID -eq $BasePolicyIdText -and $_.PolicyID -ne $BasePolicyIdText })
$active = @($supplementals | Where-Object { $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })

Write-Host ''
Write-Host '=== Supplemental policies ==='
foreach ($p in $supplementals) {
    $status = if ($p.IsOnDisk -and $p.IsEnforced -and $p.IsAuthorized) { 'ACTIVE' } else { 'INACTIVE' }
    Write-Host "  [$status] $($p.PolicyID) | $($p.FriendlyName) | v$($p.Version)"
}

if ($active.Count -eq 0) { throw 'No active supplemental policy found. V10.6.3 deployment may have failed.' }

$v1063 = @($active | Where-Object { $_.FriendlyName -match 'V10\.6\.3' })
if ($v1063.Count -eq 0) { throw 'V10.6.3 Bootstrap policy is not active/enforced/authorized.' }

Write-Host ''
Write-Host '=== V10.6.3 verification ==='
Write-Host "  PolicyID:     $($v1063[0].PolicyID)"
Write-Host "  FriendlyName: $($v1063[0].FriendlyName)"
Write-Host "  IsOnDisk:     $($v1063[0].IsOnDisk)"
Write-Host "  IsEnforced:   $($v1063[0].IsEnforced)"
Write-Host "  IsAuthorized: $($v1063[0].IsAuthorized)"

Write-Host ''
Write-Host 'RESULT: PASS'
Write-Host 'V10.6.3 Bootstrap is active, enforced, and authorized.'
