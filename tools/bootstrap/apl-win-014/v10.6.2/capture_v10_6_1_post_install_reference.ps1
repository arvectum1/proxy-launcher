<#
.SYNOPSIS
    Capture exact 0.2.4 reference installation tree after V10.6.1 bootstrap install.
.DESCRIPTION
    Read-only. Run AFTER the user manually executes the canonical setup under V10.6.1.
    Produces an evidence directory for V10.7 ReferenceFullHash policy authoring.
    Does NOT run Repair, Uninstall, or launch APL.
    Written for Windows PowerShell 5.1 ConstrainedLanguage mode.
#>
#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedAppHash    = '0f275a8ab6d1640e3c392308c6ae4af4f613fc2750c62df7f173300eb0e0e447'
$ExpectedSetupHash  = '7b9e7b95b0c26a028ed903ba7281a60dfd83c190ebdcf1208c05c1f687450389'
$ExpectedUpgradeHash  = '411f9e905723d4f5fcffb26057d8e5885087a35b988dda286ade11d9f0f81a95'
$ExpectedUninstallHash = '7abc1fe332975440d2c84be608773a890c5bb4deb130eea54378a128e79b0a44'
$ExpectedManifestHash  = '6f7219be4664947e4cd6082423f9592e7774e34c1c72d92a6a89a29f98eb690d'

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

if ($env:OS -ne 'Windows_NT') { throw 'This script must run on Windows.' }

$documents = "$env:USERPROFILE\Documents"
$installRoot = Join-Path $documents 'ArvectumProxyLauncher'
if (-not (Test-Path -LiteralPath $installRoot -PathType Container)) {
    throw "Installation directory not found: $installRoot"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $scriptDir "v10.6.1-reference-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Write-Host '=== Capturing 0.2.4 reference installation tree ==='
Write-Host "Install root: $installRoot"

$exe = Join-Path $installRoot 'Arvectum Proxy Launcher.exe'
$repair = Join-Path $installRoot 'Arvectum Proxy Launcher Repair.exe'
$uninstaller = Join-Path $installRoot 'unins000.exe'
$manifest = Join-Path $installRoot 'build_manifest.json'
$upgrade = Join-Path $installRoot 'upgrade_helper.ps1'
$uninstall = Join-Path $installRoot 'uninstall_helper.ps1'

$files = @(
    @{ Label='Main EXE'; Path=$exe; Expected=$ExpectedAppHash },
    @{ Label='Repair Setup'; Path=$repair; Expected=$ExpectedSetupHash },
    @{ Label='upgrade_helper'; Path=$upgrade; Expected=$ExpectedUpgradeHash },
    @{ Label='uninstall_helper'; Path=$uninstall; Expected=$ExpectedUninstallHash },
    @{ Label='build_manifest'; Path=$manifest; Expected=$ExpectedManifestHash }
)

Write-Host ''
Write-Host '=== Verifying installed file identities ==='
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f.Path -PathType Leaf)) { throw "Missing: $($f.Label) ($($f.Path))" }
    $actual = Get-Sha256 $f.Path
    $match = $actual -eq $f.Expected
    Write-Host "  $($f.Label): $actual (expected $($f.Expected)) match=$match"
    if (-not $match) { throw "Hash mismatch for $($f.Label)" }
}

if (Test-Path -LiteralPath $uninstaller -PathType Leaf) {
    $unHash = Get-Sha256 $uninstaller
    $unItem = Get-Item -LiteralPath $uninstaller
    $unSize = $unItem.Length
    Write-Host ''
    Write-Host "=== Generated unins000.exe ==="
    Write-Host "  Path:     $uninstaller"
    Write-Host "  SHA256:   $unHash"
    Write-Host "  Size:     $unSize"
} else {
    Write-Host ''
    Write-Host 'WARNING: unins000.exe not found. V10.7 lifecycle policy cannot cover uninstaller.'
}

Write-Host ''
Write-Host '=== Scanning complete installed tree ==='
$allFiles = Get-ChildItem -LiteralPath $installRoot -File -Recurse -Force
$inventory = @()
foreach ($f in $allFiles) {
    $rootEscaped = "$installRoot\" -replace '([\\(){}+.|^$])','\$1'
    $rel = $f.FullName -replace ("^" + $rootEscaped + "(.+)"), '$1'
    $hash = Get-Sha256 $f.FullName
    $inventory += [ordered]@{
        relative_path = $rel
        sha256 = $hash
        size = $f.Length
        is_pe = ($f.Extension -in @('.exe','.dll','.sys','.ocx'))
    }
    Write-Host "  $rel  $hash  $($f.Length)"
}

Write-Host ''
Write-Host "Total files: $($inventory.Count)"

Write-Host ''
Write-Host '=== Collecting process/listener state ==='
$procs = @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue)
$procInfo = @()
foreach ($p in $procs) {
    $procInfo += [ordered]@{
        pid = $p.ProcessId
        command_line = "$($p.CommandLine)"
        executable_path = "$($p.ExecutablePath)"
        creation_date = "$($p.CreationDate)"
    }
    Write-Host "  PID=$($p.ProcessId) CMD=$($p.CommandLine)"
}

Write-Host ''
Write-Host '=== Collecting Code Integrity events ==='
$ciEvents = @()
try {
    $ciEvents = @(Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 50 -ErrorAction Stop |
        Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-30) } |
        Select-Object TimeCreated, Id, LevelDisplayName, Message)
    Write-Host "  CI events in last 30 minutes: $($ciEvents.Count)"
} catch {
    Write-Host '  No CI events accessible.'
}

Write-Host ''
Write-Host '=== Collecting WinINET state ==='
$inetSettings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
$inetState = [ordered]@{
    ProxyEnable = $inetSettings.ProxyEnable
    ProxyServer = $inetSettings.ProxyServer
    ProxyOverride = $inetSettings.ProxyOverride
    AutoConfigURL = $inetSettings.AutoConfigURL
    AutoDetect = $inetSettings.AutoDetect
}
Write-Host "  ProxyEnable:   $($inetState.ProxyEnable)"
Write-Host "  ProxyServer:   $($inetState.ProxyServer)"
Write-Host "  AutoConfigURL: $($inetState.AutoConfigURL)"

Write-Host ''
Write-Host '=== Collecting Run entries ==='
$runMain = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$runRecovery = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue
$mainExists = $null -ne ($runMain.PSObject.Properties | Where-Object { $_.Name -eq 'ArvectumProxyLauncher' })
$recoveryExists = $null -ne ($runRecovery.PSObject.Properties | Where-Object { $_.Name -eq 'ArvectumProxyLauncherRecovery' })
Write-Host "  Main Run exists: $mainExists"
Write-Host "  Recovery Run exists: $recoveryExists"

Write-Host ''
Write-Host '=== Saving reference evidence ==='
$timestamp = Get-Date -UFormat '%Y-%m-%dT%H:%M:%S.0000000Z'

$uninsData = $null
if (Test-Path -LiteralPath $uninstaller -PathType Leaf) {
    $uninsData = [ordered]@{
        sha256 = Get-Sha256 $uninstaller
        size = (Get-Item -LiteralPath $uninstaller).Length
    }
}

$evidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-v10.6.1-reference-capture.v1'
    task = 'APL-WIN-014'
    captured_utc = $timestamp
    candidate_version = '0.2.4'
    install_root = $installRoot
    expected_app_hash = $ExpectedAppHash
    expected_setup_hash = $ExpectedSetupHash
    files = $inventory
    unins000 = $uninsData
    processes = $procInfo
    wininet = $inetState
    run_entries = [ordered]@{
        main_run_exists = $mainExists
        recovery_run_exists = $recoveryExists
    }
    ci_event_count = $ciEvents.Count
}
$evidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outDir 'reference-capture.json') -Encoding UTF8

$checksums = @(
    Get-ChildItem -LiteralPath $outDir -File | Sort-Object Name | ForEach-Object {
        "$(Get-Sha256 $_.FullName)  $($_.Name)"
    }
)
Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

Write-Host ''
Write-Host '=== Reference capture: COMPLETE ==='
Write-Host "Output: $outDir"
Write-Host 'Next: run prepare_v10_7_final_on_demo.ps1 to author the lifecycle policy.'
