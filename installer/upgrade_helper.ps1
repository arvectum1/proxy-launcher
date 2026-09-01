[CmdletBinding()]
param([Parameter(Mandatory)] [string]$PayloadRoot, [Parameter(Mandatory)] [string]$InstallRoot, [switch]$PreflightOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$StateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$LogPath = Join-Path $StateRoot 'install.log'
$RunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RecoveryRunName = 'ArvectumProxyLauncherRecovery'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -Encoding utf8
}

function Get-Sha256([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Test-ExactPath([string]$Candidate, [string]$Expected) {
  if (-not $Candidate -or -not $Expected) { return $false }
  try {
    $c = $Candidate -replace '\\+$'
    $e = $Expected -replace '\\+$'
    return $c -ieq $e
  } catch { return $false }
}

function Get-RecoveryBackups {
  @('proxy_internet_backup.json','proxy_env_backup.json') |
    ForEach-Object { Join-Path $StateRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}

function Get-OwnedProcesses([string]$Exe) {
  @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and (Test-ExactPath $_.ExecutablePath $Exe) })
}

function Stop-OwnedProcess([string]$Exe) {
  foreach ($process in @(Get-OwnedProcesses $Exe)) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
  }
}

function Test-OwnedStartCommand([string]$Command, [string]$ExpectedExe) {
  if (-not $Command) { return $false }
  if ($Command -notmatch '^\s*"([^"]+)"\s+--start\s*$') { return $false }
  return Test-ExactPath $matches[1] $ExpectedExe
}

function Get-RunValue([string]$Name) {
  try {
    $item = Get-ItemProperty -Path $RunPath -ErrorAction Stop
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $null
  }
  $property = $item.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return [string]$property.Value
}

function Remove-StaleRecoveryRun([string]$ExpectedExe) {
  if (@(Get-RecoveryBackups).Count -ne 0) { return }
  $value = Get-RunValue $RecoveryRunName
  if (-not $value) { return }
  if (Test-OwnedStartCommand $value $ExpectedExe) {
    Remove-ItemProperty -Path $RunPath -Name $RecoveryRunName -ErrorAction Stop
    Write-InstallLog 'stale owned recovery Run value removed'
  }
}

function Assert-RecoverySafe([string]$ExpectedExe) {
  $backups = @(Get-RecoveryBackups)
  if ($backups.Count -ne 0) { throw 'recovery backups remain after stopping the previous version' }
  $recovery = Get-RunValue $RecoveryRunName
  if ($recovery -and -not (Test-OwnedStartCommand $recovery $ExpectedExe)) {
    throw 'conflicting recovery autostart is not owned'
  }
}

function Remove-StalePid([string]$ExpectedExe) {
  $pidPath = Join-Path $StateRoot 'proxy_core.pid'
  if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return }
  $raw = (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue) -replace '^\s+|\s+$'
  $parsedPid = 0
  $validPid = $false
  if ($raw -match '^\d+$') {
    try { $parsedPid = [int]$Matches[0]; $validPid = $true } catch { $validPid = $false }
  }
  $process = $null
  if ($validPid -and $parsedPid -gt 0) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$parsedPid" -ErrorAction SilentlyContinue
  }
  if (-not $process -or -not $process.ExecutablePath -or -not (Test-ExactPath $process.ExecutablePath $ExpectedExe)) {
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction Stop
    Write-InstallLog 'stale runtime PID removed'
  }
}

function Clear-StaleMaintenanceState([string]$ExpectedExe) {
  if (@(Get-RecoveryBackups).Count -ne 0) {
    throw 'refusing stale-state cleanup while recovery backups exist'
  }
  Remove-StaleRecoveryRun $ExpectedExe
  Remove-StalePid $ExpectedExe
  foreach ($suffix in @('.new','.old')) {
    $candidate = "$ExpectedExe$suffix"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      Remove-Item -LiteralPath $candidate -Force -ErrorAction Stop
      Write-InstallLog "stale transactional artifact removed: $suffix"
    }
  }
}

function Invoke-PreviousRollback([string]$ExistingExe) {
  $backups = @(Get-RecoveryBackups)
  if ($backups.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $ExistingExe -PathType Leaf)) {
      throw 'recovery backups remain but the installed Launcher executable is missing; repair is blocked until network recovery can be proven'
    }
    Write-InstallLog 'waiting for previous-version network rollback'
    $rollback = Start-Process -FilePath $ExistingExe -ArgumentList '--stop' -Wait -PassThru
    if ($rollback.ExitCode -ne 0) { throw 'previous version did not complete network rollback' }
    if (@(Get-RecoveryBackups).Count -gt 0) { throw 'recovery backups remain after previous-version rollback' }
    Write-InstallLog 'previous-version network rollback completed'
  }
  Stop-OwnedProcess $ExistingExe
}

function Get-MaintenanceKind([string]$ExistingExe, [string]$OwnerMarker, $IncomingManifest) {
  if (-not (Test-Path -LiteralPath $ExistingExe) -and -not (Test-Path -LiteralPath $OwnerMarker)) {
    return 'INSTALL'
  }
  $installedManifestPath = Join-Path $InstallRoot 'build_manifest.json'
  if (Test-Path -LiteralPath $installedManifestPath -PathType Leaf) {
    try {
      $installedManifest = Get-Content -LiteralPath $installedManifestPath -Raw | ConvertFrom-Json
      $installedVersion = [string]$installedManifest.version
      $incomingVersion = [string]$IncomingManifest.version
      if ($installedVersion -and $incomingVersion -and $installedVersion -ne $incomingVersion) {
        return 'UPGRADE'
      }
    } catch {
      Write-InstallLog "installed manifest could not be classified: $($_.Exception.Message)"
    }
  }
  return 'REPAIR'
}

try {
  Write-InstallLog '=== INSTALL SESSION START'
  Write-InstallLog "PayloadRoot: $PayloadRoot"
  Write-InstallLog "InstallRoot: $InstallRoot"
  $manifest = Get-Content -LiteralPath (Join-Path $PayloadRoot 'build_manifest.json') -Raw | ConvertFrom-Json
  $payloadExe = Join-Path $PayloadRoot 'Arvectum Proxy Launcher.exe'
  Write-InstallLog "payload EXE: $payloadExe"
  $embeddedHash = Get-Sha256 $payloadExe
  Write-InstallLog "embedded application expected SHA256: $($manifest.application_sha256)"
  if ($embeddedHash -ine $manifest.application_sha256) { throw 'embedded application SHA256 verification failed' }
  $selfHash = Get-Sha256 (Join-Path $PayloadRoot 'upgrade_helper.ps1')
  if ($selfHash -ine $manifest.upgrade_helper_sha256) { throw 'upgrade helper SHA256 verification failed' }

  $existingExe = Join-Path $InstallRoot 'Arvectum Proxy Launcher.exe'
  $ownerMarker = Join-Path $InstallRoot '.arvectum-install-owner'
  $maintenanceKind = Get-MaintenanceKind $existingExe $ownerMarker $manifest
  Write-InstallLog "maintenance mode: $maintenanceKind"
  Write-InstallLog "incoming version: $($manifest.version)"
  Write-InstallLog "final EXE: $existingExe"

  Invoke-PreviousRollback $existingExe
  Remove-StaleRecoveryRun $existingExe
  Assert-RecoverySafe $existingExe
  if ($PreflightOnly) {
    Write-InstallLog "=== INSTALL SESSION END: PASS (preflight $maintenanceKind)"
    exit 0
  }

  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $staged = "$existingExe.new"
  $old = "$existingExe.old"
  Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $payloadExe -Destination $staged -Force
  if ((Get-Sha256 $staged) -ine $manifest.application_sha256) { throw 'staged application SHA256 verification failed' }

  try {
    Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $existingExe) { Move-Item -LiteralPath $existingExe -Destination $old -Force }
    Move-Item -LiteralPath $staged -Destination $existingExe -Force
    if ((Get-Sha256 $existingExe) -ine $manifest.application_sha256) { throw 'final application SHA256 verification failed' }
    Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    Write-InstallLog 'transactional replacement committed'
  } catch {
    Remove-Item -LiteralPath $existingExe -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination $existingExe -Force }
    Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
    Write-InstallLog 'transactional replacement rolled back'
    throw
  }

  Clear-StaleMaintenanceState $existingExe
  $releaseFolder = 'arvectum-proxy-launcher-windows'
  Write-InstallLog "=== INSTALL SESSION END: PASS ($maintenanceKind)"
} catch {
  Write-InstallLog "ERROR TYPE: $($_.Exception.GetType().Name)"
  Write-InstallLog "ERROR MESSAGE: $($_.Exception.Message)"
  exit 1
}