<#
.SYNOPSIS
    Build the post-incident Windows App Control enterprise installer candidate.
.DESCRIPTION
    Produces a multi-file Inno Setup bundle with UseSetupLdr=no, a deterministic
    PyInstaller onedir runtime, and a separately executable native recovery kit.
    This is intentionally NOT the sealed/public single-EXE 0.2.3 installer.

    The output remains a candidate until real Enforced install/repair/upgrade/
    uninstall and native recovery rehearsal evidence are collected.
#>
[CmdletBinding()]
param(
    [string]$PythonExecutable = 'python.exe',
    [string]$IsccPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'App Control installer build must run on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$candidateLabel = "$version-appcontrol-candidate"
$runtimeLabel = "appcontrol-$version"
$baseName = "Arvectum-Proxy-Launcher-$version-windows-x64-appcontrol-setup"

if (-not $IsccPath) {
    $IsccPath = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $IsccPath) { throw 'Exact Inno Setup 6.7.1 ISCC.exe was not found.' }

$staticDir = Join-Path $root "out\app-control-static-runtime-$version"
& (Join-Path $root 'tools\build_windows_appcontrol_static_runtime.ps1') `
    -PythonExecutable $PythonExecutable `
    -OutputDirectory $staticDir
if ($LASTEXITCODE -ne 0) { throw 'Static runtime build failed.' }
$staticManifestPath = Join-Path $staticDir 'static-runtime.json'
$static = Get-Content -LiteralPath $staticManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$static.result -ne 'PASS' -or [string]$static.packaging_layout -ne 'static-runtime' -or [bool]$static.pyinstaller_onefile) {
    throw 'Static runtime manifest is not App-Control-safe.'
}

$recoveryDir = Join-Path $root 'out\app-control-recovery'
& (Join-Path $root 'tools\build_windows_appcontrol_recovery.ps1') `
    -StaticRuntimeDirectory $staticDir `
    -OutputDirectory $recoveryDir
if ($LASTEXITCODE -ne 0) { throw 'Native recovery build failed.' }
$recoveryManifestPath = Join-Path $recoveryDir 'native-recovery.json'
$recovery = Get-Content -LiteralPath $recoveryManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$recovery.result -ne 'PASS' -or [bool]$recovery.requires_powershell_runtime) {
    throw 'Native recovery manifest is not acceptable.'
}

$portableZip = Join-Path $root "out\Arvectum-Proxy-Launcher-$version-windows-x64-portable.zip"
if (-not (Test-Path -LiteralPath $portableZip -PathType Leaf)) {
    throw 'Canonical portable ZIP is required as the verified third-party-license source.'
}
$licenseExtract = Join-Path $root 'out\appcontrol-license-source'
Remove-Item -LiteralPath $licenseExtract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $portableZip -DestinationPath $licenseExtract -Force
$licenseBundle = Join-Path $licenseExtract 'THIRD_PARTY_LICENSES'
if (-not (Test-Path -LiteralPath (Join-Path $licenseBundle 'manifest.json') -PathType Leaf)) {
    throw 'Portable ZIP lacks the verified THIRD_PARTY_LICENSES bundle.'
}

$payload = Join-Path $root 'out\appcontrol-installer-payload'
Remove-Item -LiteralPath $payload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Copy-Item -LiteralPath $staticDir -Destination (Join-Path $payload 'runtime') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $payload 'LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $root 'THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $payload 'THIRD_PARTY_NOTICES.txt') -Force
Copy-Item -LiteralPath $licenseBundle -Destination (Join-Path $payload 'THIRD_PARTY_LICENSES') -Recurse -Force

function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$payloadManifest = [ordered]@{
    schema = 'arvectum.proxy.windows-app-control-installer-candidate.v1'
    task = 'APL-WIN-014'
    created_utc = [DateTime]::UtcNow.ToString('o')
    result = 'PASS'
    version = $version
    candidate_label = $candidateLabel
    source_commit = (git rev-parse HEAD).Trim()
    packaging_layout = 'static-runtime'
    runtime_label = $runtimeLabel
    runtime_entry_sha256 = [string]$static.entry_sha256
    static_runtime_manifest_sha256 = Hash $staticManifestPath
    native_recovery_sha256 = [string]$recovery.artifact_sha256
    use_setup_ldr = $false
    setup_runs_from_temp = $false
    product_powershell_helpers = $false
    repair_model = 'rerun-original-multifile-bundle'
    installer_lifecycle_complete = $false
    enforced_recovery_rehearsal = $false
    enforced_lifecycle_ready = $false
}
$payloadManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $payload 'appcontrol_installer_manifest.json') -Encoding UTF8

$outInstaller = Join-Path $root 'out\appcontrol-installer'
Remove-Item -LiteralPath $outInstaller -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $outInstaller -Force | Out-Null

$isccArgs = @(
    "/DAppVersion=$version",
    "/DPayloadDir=$payload",
    "/DRuntimeLabel=$runtimeLabel",
    "/DSetupBaseName=$baseName",
    'installer\ArvectumProxyLauncher.AppControl.iss'
)
& $IsccPath @isccArgs
if ($LASTEXITCODE -ne 0) { throw 'App Control Inno Setup compilation failed.' }

$setupFiles = @(
    Get-ChildItem -LiteralPath $outInstaller -File |
        Where-Object { $_.BaseName -eq $baseName -or $_.Name -like "$baseName-*.bin" } |
        Sort-Object Name
)
$setupExe = Join-Path $outInstaller "$baseName.exe"
if (-not (Test-Path -LiteralPath $setupExe -PathType Leaf)) { throw 'UseSetupLdr=no Setup EXE is missing.' }
if ($setupFiles.Count -lt 2) { throw 'Expected a multi-file UseSetupLdr=no installer bundle.' }
if (@($setupFiles | Where-Object { $_.Extension -eq '.bin' }).Count -lt 1) {
    throw 'UseSetupLdr=no installer data BIN file is missing.'
}

$bundleRoot = Join-Path $root "out\$baseName-bundle"
Remove-Item -LiteralPath $bundleRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
$setupDir = Join-Path $bundleRoot 'setup'
$rescueDir = Join-Path $bundleRoot 'rescue-runtime'
$bundleRecoveryDir = Join-Path $bundleRoot 'recovery'
New-Item -ItemType Directory -Path $setupDir,$rescueDir,$bundleRecoveryDir -Force | Out-Null
foreach ($file in $setupFiles) { Copy-Item -LiteralPath $file.FullName -Destination $setupDir -Force }
Copy-Item -Path (Join-Path $staticDir '*') -Destination $rescueDir -Recurse -Force
Copy-Item -Path (Join-Path $recoveryDir '*') -Destination $bundleRecoveryDir -Recurse -Force

$setupInventory = @(
    Get-ChildItem -LiteralPath $setupDir -File | Sort-Object Name | ForEach-Object {
        [ordered]@{ name=$_.Name; size=[long]$_.Length; sha256=Hash $_.FullName; executable=$_.Extension -ieq '.exe' }
    }
)
$rescueExecutables = @(
    Get-ChildItem -LiteralPath $rescueDir -File -Recurse |
        Where-Object { @('.exe','.dll','.pyd','.ocx','.sys') -contains $_.Extension.ToLowerInvariant() }
)

$bundleManifest = [ordered]@{
    schema = 'arvectum.proxy.windows-app-control-enterprise-bundle.v1'
    task = 'APL-WIN-014'
    created_utc = [DateTime]::UtcNow.ToString('o')
    result = 'PASS'
    version = $version
    candidate_label = $candidateLabel
    promoted_release = $false
    setup_loader = 'disabled'
    setup_runs_from_temp = $false
    static_runtime = $true
    pyinstaller_onefile = $false
    rescue_runtime_included = $true
    rescue_executable_count = $rescueExecutables.Count
    native_recovery_included = $true
    native_recovery_sha256 = [string]$recovery.artifact_sha256
    setup_files = $setupInventory
    installer_lifecycle_complete = $false
    enforced_recovery_rehearsal = $false
    enforced_lifecycle_ready = $false
}
$bundleManifestPath = Join-Path $bundleRoot 'enterprise-bundle.json'
$bundleManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $bundleManifestPath -Encoding UTF8

$readme = @"
ARVECTUM PROXY LAUNCHER - APP CONTROL ENTERPRISE CANDIDATE
==========================================================

This bundle is intentionally NOT the sealed/public 0.2.3 single-EXE installer.
It exists to eliminate the two real ARVECTUM-DEMO failure modes:
  1. PyInstaller onefile _MEI runtime execution;
  2. Inno Setup SetupLdr TEMP self-copy execution.

Install: extract the entire bundle, then run setup\$baseName.exe with all sibling .bin files present.
Recovery: pre-stage rescue-runtime and recovery before any Enforced destructive rehearsal.

Do not promote this candidate until enterprise-bundle.json has corresponding real
Enforced lifecycle + native recovery rehearsal evidence.
"@
Set-Content -LiteralPath (Join-Path $bundleRoot 'README.txt') -Value $readme -Encoding UTF8

$zip = "$bundleRoot.zip"
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $bundleRoot '*') -DestinationPath $zip -Force
$zipHash = Hash $zip

Remove-Item -LiteralPath $licenseExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'APL-WIN-014 App Control enterprise bundle build: PASS'
Write-Host "Bundle: $zip"
Write-Host "SHA256: $zipHash"
Write-Host 'UseSetupLdr: NO'
Write-Host 'PyInstaller onefile: NO'
Write-Host 'Native recovery: INCLUDED'
Write-Host 'Promoted release: NO'
Write-Host 'Enforced lifecycle readiness: NOT YET PROVEN'
