<#
.SYNOPSIS
    ConstrainedLanguage-safe bootstrap for the APL-WIN-014 lab harness supplemental.
.DESCRIPTION
    Preflight verifies the exact harness trust artifact, exact stand-kit scripts, and
    the already-Enforced dedicated App Control policy state without mutation.

    Deploy adds ONLY the lab-only harness supplemental. It never changes/removes the
    dedicated base, product trust supplementals, Defender, Smart App Control, network,
    Proxy Launcher state, or release bytes.

    This file intentionally contains no .NET method invocations so it can execute as
    an untrusted script while Windows PowerShell is constrained by App Control.
#>
param(
    [string]$Mode = 'Preflight',
    [string]$TrustDirectory = '',
    [string]$StandKitDirectory = 'C:\Arvectum\StandKit\APL-WIN-014-0.2.4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePolicyId = 'DC1C604C-46EA-40B7-9F47-CF582B225D5E'
$HistoricalSupplementalPolicyId = 'EE6C778F-0FC2-4D9B-ACA9-2FA8463D3624'
$Sealed023SupplementalPolicyId = 'C3B6C04A-0C15-4486-A2CE-8490DD286B2C'
$ExpectedComputerName = 'ARVECTUM-DEMO'

if ($Mode -ne 'Preflight' -and $Mode -ne 'Deploy') { throw 'Mode must be Preflight or Deploy.' }
if (-not $TrustDirectory) { $TrustDirectory = Join-Path (Split-Path -Parent $PSCommandPath) 'harness-trust' }

function Normalize-PolicyId($Value) {
    $text = [string]$Value
    $text = $text -replace '[{}]',''
    $text = $text -replace '\s',''
    $text
}

function Read-JsonFile([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-Policies([string]$CiTool) {
    $raw = & $CiTool -lp -json 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'CiTool -lp -json failed.' }
    $parsed = ($raw -join "`n") | ConvertFrom-Json
    if ($null -ne $parsed.Policies) { @($parsed.Policies) } else { @($parsed) }
}

function Get-OnePolicy($Policies, [string]$PolicyId, [string]$Label) {
    $wanted = Normalize-PolicyId $PolicyId
    $matches = @($Policies | Where-Object { (Normalize-PolicyId $_.PolicyID) -ieq $wanted })
    if ($matches.Count -ne 1) { throw "$Label policy is not uniquely present." }
    $matches[0]
}

function Assert-Supplemental($Policies, [string]$PolicyId, [string]$Label) {
    $policy = Get-OnePolicy $Policies $PolicyId $Label
    if (-not $policy.IsOnDisk) { throw "$Label supplemental is not on disk." }
    if ($policy.IsAuthorized -eq $false) { throw "$Label supplemental is not authorized." }
    if ((Normalize-PolicyId $policy.BasePolicyID) -ine (Normalize-PolicyId $BasePolicyId)) { throw "$Label supplemental targets another base." }
    $policy
}

function Assert-KnownBaseAndProductTrust([string]$CiTool) {
    $policies = @(Get-Policies $CiTool)
    $base = Get-OnePolicy $policies $BasePolicyId 'dedicated APL-WIN-014 base'
    if (-not $base.IsOnDisk) { throw 'Dedicated APL-WIN-014 base is not on disk.' }
    if ([string]$base.FriendlyName -ne 'Arvectum APL-WIN-014 Lab Base') { throw 'Dedicated base FriendlyName mismatch.' }
    if (-not $base.IsEnforced) { throw 'Dedicated base is not enforced.' }
    if (@($base.PolicyOptions) -contains 'Enabled:Audit Mode') { throw 'Dedicated base is still in Audit mode.' }
    if (-not (@($base.PolicyOptions) -contains 'Enabled:Allow Supplemental Policies')) { throw 'Dedicated base does not allow supplemental policies.' }
    $null = Assert-Supplemental $policies $HistoricalSupplementalPolicyId 'historical 0.2.2'
    $null = Assert-Supplemental $policies $Sealed023SupplementalPolicyId 'sealed 0.2.3'
    $policies
}

if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw "SAFETY BLOCK: expected $ExpectedComputerName, detected $env:COMPUTERNAME." }

$fltmc = Join-Path $env:SystemRoot 'System32\fltmc.exe'
if (-not (Test-Path -LiteralPath $fltmc -PathType Leaf)) { throw 'fltmc.exe is missing.' }
& $fltmc > $null 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Elevated Administrator PowerShell is required.' }

$ciTool = Join-Path $env:SystemRoot 'System32\CiTool.exe'
if (-not (Test-Path -LiteralPath $ciTool -PathType Leaf)) { throw 'CiTool.exe is missing.' }
if (-not (Test-Path -LiteralPath $StandKitDirectory -PathType Container)) { throw "Stand kit is missing: $StandKitDirectory" }
if (-not (Test-Path -LiteralPath $TrustDirectory -PathType Container)) { throw "Harness trust directory is missing: $TrustDirectory" }

$manifestPath = Join-Path $TrustDirectory 'harness-trust.json'
$manifest = Read-JsonFile $manifestPath 'harness trust manifest'
if ([string]$manifest.schema -ne 'arvectum.proxy.apl-win-014-harness-trust.v1') { throw 'Unsupported harness trust manifest schema.' }
if ([string]$manifest.result -ne 'PASS') { throw 'Harness trust build did not PASS.' }
if ([string]$manifest.purpose -ne 'lab-harness-only') { throw 'Harness trust purpose is not lab-harness-only.' }
if ($manifest.product_trust -ne $false -or $manifest.final_acceptance_evidence -ne $false) { throw 'Harness trust illegally claims product/final trust.' }
if ((Normalize-PolicyId $manifest.base_policy_id) -ine (Normalize-PolicyId $BasePolicyId)) { throw 'Harness trust targets another base.' }
if ([int]$manifest.trusted_script_count -ne 4) { throw 'Harness trust must contain exactly four scripts.' }
if (-not $manifest.script_scan_enabled -or $manifest.no_script_option_used) { throw 'Harness trust was not built with script scanning enabled.' }

$cip = Join-Path $TrustDirectory ([string]$manifest.supplemental_policy_cip)
if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'Harness supplemental CIP is missing.' }
$cipHash = (Get-FileHash -LiteralPath $cip -Algorithm SHA256).Hash
if ($cipHash -ine [string]$manifest.supplemental_policy_cip_sha256) { throw 'Harness supplemental CIP SHA256 mismatch.' }

foreach ($script in @($manifest.trusted_scripts)) {
    $target = Join-Path $StandKitDirectory ([string]$script.stand_relative_path)
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Trusted stand-kit script is missing: $([string]$script.stand_relative_path)" }
    $item = Get-Item -LiteralPath $target
    if ([long]$item.Length -ne [long]$script.size) { throw "Trusted stand-kit script size mismatch: $([string]$script.stand_relative_path)" }
    $sha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($sha -ine [string]$script.sha256) { throw "Trusted stand-kit script SHA256 mismatch: $([string]$script.stand_relative_path)" }
}

$policies = @(Assert-KnownBaseAndProductTrust $ciTool)
$harnessId = [string]$manifest.supplemental_policy_id
$existingHarness = @($policies | Where-Object { (Normalize-PolicyId $_.PolicyID) -ieq (Normalize-PolicyId $harnessId) })
if ($existingHarness.Count -gt 1) { throw 'Duplicate harness supplemental identities detected.' }
if ($existingHarness.Count -eq 1) {
    if (-not $existingHarness[0].IsOnDisk -or $existingHarness[0].IsAuthorized -eq $false) { throw 'Harness supplemental exists but is not active/authorized.' }
    if ((Normalize-PolicyId $existingHarness[0].BasePolicyID) -ine (Normalize-PolicyId $BasePolicyId)) { throw 'Existing harness supplemental targets another base.' }
}

if ($Mode -eq 'Preflight') {
    Write-Host '================================================'
    Write-Host 'APL-WIN-014 HARNESS BOOTSTRAP PREFLIGHT: PASS'
    Write-Host "POWERSHELL LANGUAGE MODE: $($ExecutionContext.SessionState.LanguageMode)"
    Write-Host 'BASE POLICY: ENFORCED'
    Write-Host 'HISTORICAL 0.2.2 SUPPLEMENTAL: ACTIVE'
    Write-Host 'SEALED 0.2.3 SUPPLEMENTAL: ACTIVE'
    if ($existingHarness.Count -eq 1) { Write-Host 'LAB HARNESS SUPPLEMENTAL: ALREADY ACTIVE' } else { Write-Host 'LAB HARNESS SUPPLEMENTAL: READY / NOT DEPLOYED' }
    Write-Host 'EXACT STAND-KIT SCRIPTS: HASH MATCH'
    Write-Host 'POLICY MUTATION: NONE'
    Write-Host 'PRODUCT/NETWORK MUTATION: NONE'
    Write-Host '================================================'
    exit 0
}

if ($existingHarness.Count -eq 0) {
    Write-Host 'Deploying ONLY the exact lab harness supplemental...'
    $update = & $ciTool --update-policy $cip -json 2>&1
    $updateExit = $LASTEXITCODE
    $update | ForEach-Object { Write-Host $_ }
    if ($updateExit -ne 0) { throw "Harness supplemental deployment failed with exit code $updateExit." }

    $active = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $after = @(Assert-KnownBaseAndProductTrust $ciTool)
        $match = @($after | Where-Object { (Normalize-PolicyId $_.PolicyID) -ieq (Normalize-PolicyId $harnessId) })
        if ($match.Count -eq 1 -and $match[0].IsOnDisk -and $match[0].IsAuthorized -ne $false -and (Normalize-PolicyId $match[0].BasePolicyID) -ieq (Normalize-PolicyId $BasePolicyId)) {
            $active = $true
            break
        }
    }
    if (-not $active) { throw 'Harness supplemental did not become active after deployment.' }
}

Write-Host '================================================'
Write-Host 'APL-WIN-014 HARNESS BOOTSTRAP DEPLOY: PASS'
Write-Host 'LAB HARNESS SUPPLEMENTAL: ACTIVE'
Write-Host 'BASE POLICY: UNCHANGED / ENFORCED'
Write-Host 'PRODUCT TRUST: UNCHANGED'
Write-Host 'DEFENDER / SMART APP CONTROL: UNCHANGED'
Write-Host 'NETWORK / PROXY LAUNCHER: UNCHANGED'
Write-Host 'NEXT: start a NEW elevated PowerShell process before running the trusted harness.'
Write-Host '================================================'
