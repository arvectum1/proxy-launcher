<#
APL-WIN-012 Windows Release Candidate lifecycle E2E.
Runs on an isolated Windows QA host/runner and proves:
  current fresh install -> smoke -> uninstall,
  synthetic predecessor install -> upgrade -> repair -> uninstall,
  persistent configuration preservation and owned/foreign startup cleanup boundaries.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CurrentSetup,
    [Parameter(Mandatory)] [string]$PredecessorSetup,
    [Parameter(Mandatory)] [string]$CurrentVersion,
    [string]$EvidencePath = 'out\windows-rc-e2e.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'APL-WIN-012 E2E must run on Windows.' }

$CurrentSetup = (Resolve-Path -LiteralPath $CurrentSetup).Path
$PredecessorSetup = (Resolve-Path -LiteralPath $PredecessorSetup).Path
$documents = [Environment]::GetFolderPath('MyDocuments')
$installRoot = Join-Path $documents 'ArvectumProxyLauncher'
$exe = Join-Path $installRoot 'Arvectum Proxy Launcher.exe'
$repair = Join-Path $installRoot 'Arvectum Proxy Launcher Repair.exe'
$stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$installLog = Join-Path $stateRoot 'install.log'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$processTimeoutMs = 300000
$evidence = [ordered]@{
    schema = 'arvectum.proxy.windows-rc-e2e.v1'
    current_version = $CurrentVersion
    current_setup_sha256 = (Get-FileHash -LiteralPath $CurrentSetup -Algorithm SHA256).Hash.ToLowerInvariant()
    predecessor_setup_sha256 = (Get-FileHash -LiteralPath $PredecessorSetup -Algorithm SHA256).Hash.ToLowerInvariant()
    phases = [ordered]@{}
}

function Get-RunValue([string]$Name) {
    $item = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return [string]$property.Value
}

function Invoke-Setup([string]$Path, [string]$Label) {
    $log = Join-Path $PWD "windows-rc-$Label.log"
    $p = Start-Process -FilePath $Path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',"/LOG=$log") -PassThru
    if (-not $p.WaitForExit($processTimeoutMs)) {
        Stop-Process -Id $p.Id -Force
        throw "$Label setup exceeded the five-minute non-interactive timeout"
    }
    if ($p.ExitCode -ne 0) {
        if (Test-Path $log) { Get-Content $log }
        if (Test-Path $installLog) { Get-Content $installLog }
        throw "$Label setup failed with exit code $($p.ExitCode)"
    }
    return $log
}

function Invoke-Status([string]$Label) {
    if (-not (Test-Path -LiteralPath $exe)) { throw "${Label}: installed executable is missing" }
    $p = Start-Process -FilePath $exe -ArgumentList '--status' -PassThru
    if (-not $p.WaitForExit($processTimeoutMs)) {
        Stop-Process -Id $p.Id -Force
        throw "$Label --status exceeded the five-minute non-interactive timeout"
    }
    if ($p.ExitCode -ne 0) { throw "${Label}: --status failed with exit code $($p.ExitCode)" }
}

function Invoke-Uninstall([string]$Label) {
    $uninstaller = Join-Path $installRoot 'unins000.exe'
    if (-not (Test-Path -LiteralPath $uninstaller)) { throw "${Label}: uninstaller is missing" }
    $log = Join-Path $PWD "windows-rc-$Label-uninstall.log"
    $p = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=$log") -PassThru
    if (-not $p.WaitForExit($processTimeoutMs)) {
        Stop-Process -Id $p.Id -Force
        throw "$Label uninstall exceeded the five-minute non-interactive timeout"
    }
    if ($p.ExitCode -ne 0) {
        if (Test-Path $log) { Get-Content $log }
        throw "${Label}: uninstall failed with exit code $($p.ExitCode)"
    }
    if (Test-Path -LiteralPath $exe) { throw "${Label}: uninstall left installed executable" }
    if (Test-Path -LiteralPath $repair) { throw "${Label}: uninstall left cached repair installer" }
}

function Assert-CurrentMetadata {
    $info = (Get-Item -LiteralPath $exe).VersionInfo
    if ([string]$info.CompanyName -cne 'ООО «Арвектум»') { throw "installed CompanyName mismatch: $($info.CompanyName)" }
    if ([string]$info.ProductName -cne 'Arvectum Proxy Launcher') { throw "installed ProductName mismatch: $($info.ProductName)" }
    if ([string]$info.ProductVersion -cne $CurrentVersion) { throw "installed ProductVersion mismatch: $($info.ProductVersion) != $CurrentVersion" }
}

function Assert-InstallMode([string]$Mode) {
    if (-not (Test-Path -LiteralPath $installLog)) { throw "install.log is missing while checking $Mode" }
    $raw = Get-Content -LiteralPath $installLog -Raw
    if ($raw -notmatch [regex]::Escape("PASS ($Mode)")) { throw "install.log does not prove PASS ($Mode)" }
}

# Runner hygiene. This workflow is deliberately destructive only inside the app's owned QA paths.
Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $runPath -Force | Out-Null
Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Phase 1: current RC fresh install + smoke + clean uninstall.
# ---------------------------------------------------------------------------
Invoke-Setup $CurrentSetup 'fresh-current' | Out-Null
if (-not (Test-Path -LiteralPath $repair)) { throw 'fresh-current: cached repair installer is missing' }
Assert-CurrentMetadata
Invoke-Status 'fresh-current'
Assert-InstallMode 'INSTALL'
$evidence.phases.fresh_install_smoke = 'PASS'
Invoke-Uninstall 'fresh-current'
$evidence.phases.fresh_uninstall = 'PASS'

# Isolate the upgrade scenario from state generated by the fresh smoke.
Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Phase 2: predecessor -> current RC upgrade with persistent state preservation.
# ---------------------------------------------------------------------------
Invoke-Setup $PredecessorSetup 'predecessor' | Out-Null
$previousManifestPath = Join-Path $installRoot 'build_manifest.json'
$previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json
if (-not $previousManifest.synthetic_lifecycle_fixture) { throw 'predecessor fixture is not explicitly marked synthetic' }
if ([string]$previousManifest.version -eq $CurrentVersion) { throw 'predecessor fixture version must differ from current version' }
$evidence.predecessor_version = [string]$previousManifest.version

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$settings = Join-Path $stateRoot 'proxy_settings.json'
$noProxy = Join-Path $stateRoot 'no_proxy.txt'
$settingsJson = '{"config_version":1,"local_http_port":18080,"local_socks_port":11080,"local_pac_port":18082,"pac_path":"/proxy.pac","upstream":[{"host":"","port":8000}]}'
Set-Content -LiteralPath $settings -Value $settingsJson -Encoding utf8
Set-Content -LiteralPath $noProxy -Value 'apl-win-012.example' -Encoding utf8
$settingsHash = (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash
$noProxyHash = (Get-FileHash -LiteralPath $noProxy -Algorithm SHA256).Hash

Invoke-Setup $CurrentSetup 'upgrade-current' | Out-Null
Assert-InstallMode 'UPGRADE'
Assert-CurrentMetadata
Invoke-Status 'upgrade-current'
$currentManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json
if ([string]$currentManifest.version -cne $CurrentVersion) { throw 'upgrade did not install the current build manifest' }
if ($currentManifest.synthetic_lifecycle_fixture) { throw 'upgrade left synthetic lifecycle manifest installed' }
if ((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ne $settingsHash) { throw 'upgrade modified persistent proxy settings' }
if ((Get-FileHash -LiteralPath $noProxy -Algorithm SHA256).Hash -ne $noProxyHash) { throw 'upgrade modified persistent no-proxy rules' }
$evidence.phases.upgrade = 'PASS'

# ---------------------------------------------------------------------------
# Phase 3: damage binary + stale owned operational state -> cached repair.
# ---------------------------------------------------------------------------
Set-Content -LiteralPath (Join-Path $stateRoot 'proxy_core.pid') -Value '2147483646' -Encoding ascii
Set-Content -LiteralPath ($exe + '.new') -Value 'stale-new' -Encoding ascii
Set-Content -LiteralPath ($exe + '.old') -Value 'stale-old' -Encoding ascii
$ownedStart = '"' + $exe + '" --start'
New-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -Value $ownedStart -PropertyType String -Force | Out-Null
Set-Content -LiteralPath $exe -Value 'damaged-binary-for-apl-win-012-repair' -Encoding ascii
Invoke-Setup $repair 'repair-current' | Out-Null
Assert-InstallMode 'REPAIR'
Assert-CurrentMetadata
Invoke-Status 'repair-current'
if (Test-Path -LiteralPath ($exe + '.new')) { throw 'repair left stale .new artifact' }
if (Test-Path -LiteralPath ($exe + '.old')) { throw 'repair left stale .old artifact' }
if (Test-Path -LiteralPath (Join-Path $stateRoot 'proxy_core.pid')) { throw 'repair left stale PID file' }
$recoveryAfterRepair = Get-RunValue 'ArvectumProxyLauncherRecovery'
if ($recoveryAfterRepair) { throw 'repair left stale owned recovery autostart value' }
if ((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ne $settingsHash) { throw 'repair modified persistent proxy settings' }
if ((Get-FileHash -LiteralPath $noProxy -Algorithm SHA256).Hash -ne $noProxyHash) { throw 'repair modified persistent no-proxy rules' }
$evidence.phases.repair = 'PASS'

# ---------------------------------------------------------------------------
# Phase 4: uninstall removes owned state, preserves foreign state and user config.
# ---------------------------------------------------------------------------
New-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -Value $ownedStart -PropertyType String -Force | Out-Null
$foreignRecovery = '"' + $env:SystemRoot + '\System32\cmd.exe" /c echo foreign'
New-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -Value $foreignRecovery -PropertyType String -Force | Out-Null
Invoke-Uninstall 'final'
$mainAfter = Get-RunValue 'ArvectumProxyLauncher'
if ($mainAfter) { throw 'uninstall left owned main autostart value' }
$foreignAfter = Get-RunValue 'ArvectumProxyLauncherRecovery'
if ($foreignAfter -ne $foreignRecovery) { throw 'uninstall modified foreign recovery autostart value' }
if ((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ne $settingsHash) { throw 'uninstall modified persistent proxy settings' }
if ((Get-FileHash -LiteralPath $noProxy -Algorithm SHA256).Hash -ne $noProxyHash) { throw 'uninstall modified persistent no-proxy rules' }
$evidence.phases.uninstall = 'PASS'
$evidence.configuration_preserved = $true
$evidence.foreign_startup_preserved = $true
$evidence.result = 'PASS'

Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue
$evidenceDir = Split-Path -Parent $EvidencePath
if ($evidenceDir) { New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null }
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
Write-Host "APL-WIN-012 Windows RC E2E PASS. Evidence: $EvidencePath"
