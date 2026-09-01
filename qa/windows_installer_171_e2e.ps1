<#
Regression harness for GitHub issue #171.

Proves two installer invariants on Windows:
  1. a portable-owned recovery state is rolled back synchronously before the
     installer replaces the payload;
  2. a maintenance preflight failure aborts Setup before installer ownership
     metadata, repair cache, shortcuts, or uninstall registration are committed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CurrentSetup,
    [Parameter(Mandatory)] [string]$CurrentPortableExe,
    [Parameter(Mandatory)] [string]$CurrentVersion,
    [string]$EvidencePath = 'out\windows-installer-171-e2e.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Installer #171 regression must run on Windows.' }

$CurrentSetup = (Resolve-Path -LiteralPath $CurrentSetup).Path
$CurrentPortableExe = (Resolve-Path -LiteralPath $CurrentPortableExe).Path
$documents = [Environment]::GetFolderPath('MyDocuments')
$installRoot = Join-Path $documents 'ArvectumProxyLauncher'
$installedExe = Join-Path $installRoot 'Arvectum Proxy Launcher.exe'
$manifestPath = Join-Path $installRoot 'build_manifest.json'
$ownerMarker = Join-Path $installRoot '.arvectum-install-owner'
$repairExe = Join-Path $installRoot 'Arvectum Proxy Launcher Repair.exe'
$uninstaller = Join-Path $installRoot 'unins000.exe'
$stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$internetBackup = Join-Path $stateRoot 'proxy_internet_backup.json'
$envBackup = Join-Path $stateRoot 'proxy_env_backup.json'
$installLog = Join-Path $stateRoot 'install.log'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1'
$programs = [Environment]::GetFolderPath('Programs')
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$mainProgramShortcut = Join-Path $programs 'Arvectum Proxy Launcher.lnk'
$repairProgramShortcut = Join-Path $programs 'Repair Arvectum Proxy Launcher.lnk'
$desktopShortcut = Join-Path $desktop 'Arvectum Proxy Launcher.lnk'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$processTimeoutMs = 300000

$evidence = [ordered]@{
    schema = 'arvectum.proxy.windows-installer-171-e2e.v1'
    issue = 171
    current_version = $CurrentVersion
    current_setup_sha256 = (Get-FileHash -LiteralPath $CurrentSetup -Algorithm SHA256).Hash.ToLowerInvariant()
    current_portable_exe_sha256 = (Get-FileHash -LiteralPath $CurrentPortableExe -Algorithm SHA256).Hash.ToLowerInvariant()
    phases = [ordered]@{}
}

function Remove-OwnedTestSurface {
    Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $mainProgramShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $repairProgramShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $runPath -Force | Out-Null
    Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue
}

function Get-RegistrySnapshot([string]$SubKey, [string[]]$Names) {
    $snapshot = [ordered]@{}
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey)
    try {
        $present = @()
        if ($null -ne $key) { $present = @($key.GetValueNames()) }
        foreach ($name in $Names) {
            if ($present -contains $name) {
                $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $snapshot[$name] = [ordered]@{ exists = $true; value = $value }
            } else {
                $snapshot[$name] = [ordered]@{ exists = $false; value = $null }
            }
        }
    } finally {
        if ($null -ne $key) { $key.Close() }
    }
    return $snapshot
}

function Write-RecoverySnapshots {
    New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
    $internet = Get-RegistrySnapshot 'Software\Microsoft\Windows\CurrentVersion\Internet Settings' @(
        'AutoConfigURL','ProxyEnable','ProxyServer','ProxyOverride','AutoDetect'
    )
    $environment = Get-RegistrySnapshot 'Environment' @(
        'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY'
    )
    [IO.File]::WriteAllText($internetBackup, ($internet | ConvertTo-Json -Depth 5 -Compress), $utf8NoBom)
    [IO.File]::WriteAllText($envBackup, ($environment | ConvertTo-Json -Depth 5 -Compress), $utf8NoBom)
}

function Publish-SetupDiagnostics([string]$Label, [int]$ExitCode, [string]$InnoLog) {
    $diagLog = Join-Path $PWD "windows-installer-171-$Label-install.log"
    if (Test-Path -LiteralPath $installLog) {
        Copy-Item -LiteralPath $installLog -Destination $diagLog -Force
    }
    Write-Host "=== SETUP DIAGNOSTICS: $Label ==="
    Write-Host "Label: $Label"
    Write-Host "Setup exit code: $ExitCode"
    Write-Host "CurrentSetup: $CurrentSetup"
    Write-Host "InstallRoot: $installRoot"
    Write-Host "StateRoot: $stateRoot"
    $installLogExists = Test-Path -LiteralPath $installLog
    Write-Host "install.log exists: $installLogExists"
    if ($installLogExists) {
        Write-Host "install.log length: $((Get-Item -LiteralPath $installLog).Length)"
    }
    $innoLogExists = Test-Path -LiteralPath $InnoLog
    Write-Host "Inno log exists: $innoLogExists"
    if ($innoLogExists) {
        Write-Host "Inno log length: $((Get-Item -LiteralPath $InnoLog).Length)"
    }
    if ($innoLogExists) {
        Write-Host "=== INNO SETUP LOG: $Label ==="
        Get-Content -LiteralPath $InnoLog | ForEach-Object { Write-Host "INNO> $_" }
    }
    if ($installLogExists) {
        Write-Host "=== UPGRADE HELPER INSTALL.LOG: $Label ==="
        Get-Content -LiteralPath $installLog | ForEach-Object { Write-Host "INSTALL> $_" }
    }
}

function Invoke-SetupSuccess([string]$Label) {
    $log = Join-Path $PWD "windows-installer-171-$Label.log"
    $p = Start-Process -FilePath $CurrentSetup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',"/LOG=$log") -PassThru
    if (-not $p.WaitForExit($processTimeoutMs)) {
        Stop-Process -Id $p.Id -Force
        throw "${Label}: Setup exceeded the five-minute non-interactive timeout"
    }
    if ($p.ExitCode -ne 0) {
        Publish-SetupDiagnostics -Label $Label -ExitCode $p.ExitCode -InnoLog $log
        throw "${Label}: Setup failed with exit code $($p.ExitCode)"
    }
    return $log
}

function Invoke-SetupExpectedFailure([string]$Label) {
    $log = Join-Path $PWD "windows-installer-171-$Label.log"
    $p = Start-Process -FilePath $CurrentSetup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',"/LOG=$log") -PassThru
    if (-not $p.WaitForExit($processTimeoutMs)) {
        Stop-Process -Id $p.Id -Force
        throw "${Label}: Setup exceeded the five-minute non-interactive timeout"
    }
    $diagLog = Join-Path $PWD "windows-installer-171-$Label-install.log"
    if (Test-Path -LiteralPath $installLog) {
        Copy-Item -LiteralPath $installLog -Destination $diagLog -Force
    }
    if ($p.ExitCode -eq 0) {
        throw "${Label}: Setup unexpectedly succeeded; preflight did not fail closed"
    }
    return $log
}

function Assert-NoCommittedInstallSurface([string]$Label) {
    foreach ($path in @($ownerMarker, $repairExe, $uninstaller, $mainProgramShortcut, $repairProgramShortcut, $desktopShortcut)) {
        if (Test-Path -LiteralPath $path) { throw "${Label}: partial install surface exists: $path" }
    }
    if (Test-Path -LiteralPath $uninstallKey) { throw "${Label}: uninstall registration was committed before preflight completed" }
}

function Invoke-InstalledCleanup {
    if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { return }
    $log = Join-Path $PWD 'windows-installer-171-cleanup-uninstall.log'
    $p = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=$log") -PassThru
    if (-not $p.WaitForExit($processTimeoutMs)) {
        Stop-Process -Id $p.Id -Force
        throw 'cleanup uninstall exceeded the five-minute non-interactive timeout'
    }
    if ($p.ExitCode -ne 0) { throw "cleanup uninstall failed with exit code $($p.ExitCode)" }
}

# ---------------------------------------------------------------------------
# Phase 1: portable recovery-active state -> current installer.
# ---------------------------------------------------------------------------
Remove-OwnedTestSurface
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Copy-Item -LiteralPath $CurrentPortableExe -Destination $installedExe -Force
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$settings = Join-Path $stateRoot 'proxy_settings.json'
$noProxy = Join-Path $stateRoot 'no_proxy.txt'
Set-Content -LiteralPath $settings -Value '{"config_version":1,"local_http_port":18080,"local_socks_port":11080,"local_pac_port":18082,"pac_path":"/proxy.pac","upstream":[{"host":"","port":8000}]}' -Encoding utf8
Set-Content -LiteralPath $noProxy -Value 'issue-171.example' -Encoding utf8
$settingsHash = (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash
$noProxyHash = (Get-FileHash -LiteralPath $noProxy -Algorithm SHA256).Hash
Write-RecoverySnapshots
$ownedRecovery = '"' + $installedExe + '" --start'
New-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -Value $ownedRecovery -PropertyType String -Force | Out-Null

Invoke-SetupSuccess 'portable-transition' | Out-Null
if (Test-Path -LiteralPath $internetBackup) { throw 'portable-transition: WinINET recovery backup remains after installer preflight' }
if (Test-Path -LiteralPath $envBackup) { throw 'portable-transition: environment recovery backup remains after installer preflight' }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'portable-transition: installed manifest is missing' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]$manifest.version -cne $CurrentVersion) { throw 'portable-transition: installed version does not match current RC' }
$expectedHash = ([string]$manifest.application_sha256).ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $installedExe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -cne $expectedHash) { throw 'portable-transition: final EXE SHA256 does not match build manifest' }
if ((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ne $settingsHash) { throw 'portable-transition: persistent proxy settings changed' }
if ((Get-FileHash -LiteralPath $noProxy -Algorithm SHA256).Hash -ne $noProxyHash) { throw 'portable-transition: persistent no-proxy rules changed' }
foreach ($path in @($ownerMarker, $repairExe, $uninstaller)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "portable-transition: committed installer surface missing: $path" }
}
if (-not (Test-Path -LiteralPath $installLog)) { throw 'portable-transition: install.log is missing' }
$installRaw = Get-Content -LiteralPath $installLog -Raw
if ($installRaw -notmatch 'PASS \(preflight REPAIR\)') { throw 'portable-transition: preflight PASS was not recorded' }
if ($installRaw -notmatch 'previous-version network rollback completed') { throw 'portable-transition: synchronous rollback completion was not recorded' }
$evidence.phases.active_portable_to_installer = 'PASS'
$evidence.final_application_sha256 = $actualHash
$evidence.configuration_preserved = $true

Invoke-InstalledCleanup
Remove-OwnedTestSurface

# ---------------------------------------------------------------------------
# Phase 2: unrecoverable maintenance state -> fail before install commit.
# ---------------------------------------------------------------------------
Write-RecoverySnapshots
Invoke-SetupExpectedFailure 'preflight-fail-closed' | Out-Null
Assert-NoCommittedInstallSurface 'preflight-fail-closed'
if (-not (Test-Path -LiteralPath $internetBackup -PathType Leaf)) { throw 'preflight-fail-closed: recovery evidence was unexpectedly deleted' }
if (-not (Test-Path -LiteralPath $envBackup -PathType Leaf)) { throw 'preflight-fail-closed: recovery evidence was unexpectedly deleted' }
if (-not (Test-Path -LiteralPath $installLog -PathType Leaf)) { throw 'preflight-fail-closed: install.log is missing' }
$failureRaw = Get-Content -LiteralPath $installLog -Raw
if ($failureRaw -notmatch 'recovery backups remain but the installed Launcher executable is missing') {
    throw 'preflight-fail-closed: expected recovery preflight failure was not recorded'
}
$evidence.phases.preflight_partial_install_prevention = 'PASS'
$evidence.result = 'PASS'

$evidenceDir = Split-Path -Parent $EvidencePath
if ($evidenceDir) { New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null }
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

# Leave the shared runner clean for the broader RC lifecycle harness.
Remove-OwnedTestSurface
Write-Host "Windows installer blocker #171 regression PASS. Evidence: $EvidencePath"
