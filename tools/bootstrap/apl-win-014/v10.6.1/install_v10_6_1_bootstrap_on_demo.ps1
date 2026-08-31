<#
.SYNOPSIS
    Deploy V10.6.1 Bootstrap supplemental policy on ARVECTUM-DEMO (manual only, CLM-safe).
.DESCRIPTION
    Deploys the pre-authored V10.6.1 CIP. Must be run manually by an administrator.
    Written for Windows PowerShell 5.1 ConstrainedLanguage mode.
    V10.6.1: Fixed real CiTool schema (PolicyID, not policy_id).
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string]$CipPath,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedCipSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePolicyIdText = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'

$c = Get-Command CiTool.exe -ErrorAction SilentlyContinue
if (-not $c) { throw 'CiTool.exe not found.' }

if (-not (Test-Path -LiteralPath $CipPath -PathType Leaf)) { throw "CIP not found: $CipPath" }
$actualHash = (Get-FileHash -LiteralPath $CipPath -Algorithm SHA256).Hash
if ($actualHash -ne $ExpectedCipSha256) { throw "CIP hash mismatch: expected $ExpectedCipSha256, got $actualHash" }

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

Write-Host ''
Write-Host '=== Deploying V10.6.1 Bootstrap supplemental policy ==='
Write-Host "  CIP: $CipPath"
Write-Host "  CIP SHA256: $actualHash"
Write-Host "  Base: $BasePolicyIdText"

& CiTool.exe --update-policy $CipPath
if ($LASTEXITCODE -ne 0) { throw "CiTool --update-policy failed with exit code $LASTEXITCODE" }

Start-Sleep -Seconds 3

Write-Host ''
Write-Host '=== Verifying deployed policy ==='
$afterRaw = & CiTool.exe -lp -json 2>$null
$after = $afterRaw | ConvertFrom-Json

if ($null -eq $after.OperationResult) { throw 'Post-deploy CiTool output missing OperationResult. FAIL CLOSED.' }
if ($after.OperationResult -ne 0) { throw "Post-deploy CiTool OperationResult=$($after.OperationResult). FAIL CLOSED." }

$newPolicies = @($after.Policies | Where-Object { $_.BasePolicyID -eq $BasePolicyIdText -and $_.PolicyID -ne $BasePolicyIdText })

$deployed = @()
foreach ($p in $newPolicies) {
    if ($p.IsOnDisk -eq $true) { $deployed += $p }
}

if ($deployed.Count -eq 0) { throw 'No new supplemental policy found on-disk after deployment.' }

Write-Host ''
foreach ($p in $deployed) {
    Write-Host "  PolicyID:     $($p.PolicyID)"
    Write-Host "  BasePolicyID: $($p.BasePolicyID)"
    Write-Host "  FriendlyName: $($p.FriendlyName)"
    Write-Host "  Version:      $($p.Version)"
    Write-Host "  IsOnDisk:     $($p.IsOnDisk)"
    Write-Host "  IsEnforced:   $($p.IsEnforced)"
    Write-Host "  IsAuthorized: $($p.IsAuthorized)"
    Write-Host ''
}

Write-Host '=== Lab Base ==='
$baseAfter = @($after.Policies | Where-Object { $_.PolicyID -eq $BasePolicyIdText })
if ($baseAfter.Count -eq 1) {
    Write-Host "  PolicyID:     $($baseAfter[0].PolicyID)"
    Write-Host "  IsOnDisk:     $($baseAfter[0].IsOnDisk)"
    Write-Host "  IsEnforced:   $($baseAfter[0].IsEnforced)"
    Write-Host "  IsAuthorized: $($baseAfter[0].IsAuthorized)"
}

Write-Host ''
Write-Host '=== V10.6.1 Bootstrap deployment: COMPLETE ==='
Write-Host 'Next: execute the canonical setup under V10.6.1, then run capture_v10_6_1_post_install_reference.ps1.'
