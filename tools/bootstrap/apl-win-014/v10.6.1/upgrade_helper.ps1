[CmdletBinding()]
param([Parameter(Mandatory)] [string]$PayloadRoot, [Parameter(Mandatory)] [string]$InstallRoot, [switch]$PreflightOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$StateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$LogPath = Join-Path $StateRoot 'install.log'
$RunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RecoveryRunName = 'ArvectumProxyLauncherRecovery'
$RollbackConvergenceMaxAttempts = 32
$RollbackConvergenceIntervalMilliseconds = 250
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Write-InstallLog([string]$Message) {
  Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format o) $Message" -Encoding utf8
}

function Get-Sha256([string]$Path) {
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [IO.File]::ReadAllBytes($Path)
    ([BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
  } finally {
    $sha256.Dispose()
  }
}

function Test-ExactPath([string]$Candidate, [string]$Expected) {
  if (-not $Candidate -or -not $Expected) { return $false }
  try { return [IO.Path]::GetFullPath($Candidate) -ieq [IO.Path]::GetFullPath($Expected) } catch { return $false }
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

function Assert-RecoveryOwnership([string]$ExpectedExe) {
  $recovery = Get-RunValue $RecoveryRunName
  if ($recovery -and -not (Test-OwnedStartCommand $recovery $ExpectedExe)) {
    throw 'conflicting recovery autostart is not owned'
  }
}

function Remove-StalePid([string]$ExpectedExe) {
  $pidPath = Join-Path $StateRoot 'proxy_core.pid'
  if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return }
  $raw = (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue).Trim()
  $parsedPid = 0
  $validPid = [int]::TryParse($raw, [ref]$parsedPid)
  if (-not $validPid) {
    try {
      $record = $raw | ConvertFrom-Json -ErrorAction Stop
      $validPid = [int]::TryParse([string]$record.pid, [ref]$parsedPid)
    } catch { $validPid = $false }
  }
  $process = $null
  if ($validPid -and $parsedPid -gt 0) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$parsedPid" -ErrorAction SilentlyContinue
  }
  if ($process -and $process.ExecutablePath -and (Test-ExactPath $process.ExecutablePath $ExpectedExe)) {
    Write-InstallLog "runtime PID remains live and owned: $parsedPid"
    return
  }
  if (-not $process -or -not $process.ExecutablePath -or -not (Test-ExactPath $process.ExecutablePath $ExpectedExe)) {
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction Stop
    Write-InstallLog "stale runtime PID removed after liveness/ownership check: $parsedPid"
  }
}

function Get-OwnedPacListeners([string]$ExpectedExe) {
  try {
    # On some Windows builds a restrictive CIM query throws ObjectNotFound when
    # zero rows match. Query the provider first so an empty listener set remains
    # a valid convergence result while provider failures still fail closed.
    $connections = @(Get-NetTCPConnection -ErrorAction Stop)
  } catch {
    throw "could not inspect localhost PAC listener ownership: $($_.Exception.Message)"
  }
  $listeners = @($connections | Where-Object {
    $_.LocalAddress -eq '127.0.0.1' -and $_.LocalPort -eq 8082 -and $_.State -eq 'Listen'
  })
  @($listeners | ForEach-Object {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
    if ($process -and $process.ExecutablePath -and (Test-ExactPath $process.ExecutablePath $ExpectedExe)) {
      [string]$_.OwningProcess
    }
  })
}

function Stop-OwnedReplacementBlockers([string]$ExpectedExe) {
  $listenerPids = @(Get-OwnedPacListeners $ExpectedExe)
  $blockers = @(Get-OwnedProcesses $ExpectedExe | Where-Object { $listenerPids -notcontains [string]$_.ProcessId })
  foreach ($process in $blockers) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    Write-InstallLog "exact owned non-listener process stopped for replacement: $($process.ProcessId)"
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

function Get-RollbackState([string]$ExpectedExe) {
  $ownedProcesses = @(Get-OwnedProcesses $ExpectedExe | ForEach-Object { [string]$_.ProcessId })
  $ownedListeners = @(Get-OwnedPacListeners $ExpectedExe)
  $backups = @((Get-RecoveryBackups | ForEach-Object { Split-Path -Leaf $_ }))
  $pidPath = Join-Path $StateRoot 'proxy_core.pid'
  $recoveryRun = Get-RunValue $RecoveryRunName
  return [pscustomobject]@{
    owned_process_ids = $ownedProcesses
    owned_listener_ids = $ownedListeners
    recovery_backups = $backups
    pid_file_present = Test-Path -LiteralPath $pidPath -PathType Leaf
    recovery_run_present = [bool]$recoveryRun
  }
}

function Test-RollbackConverged([string]$ExpectedExe) {
  Remove-StalePid $ExpectedExe
  Remove-StaleRecoveryRun $ExpectedExe
  Assert-RecoveryOwnership $ExpectedExe
  $state = Get-RollbackState $ExpectedExe
  return $state.owned_process_ids.Count -eq 0 -and
    $state.owned_listener_ids.Count -eq 0 -and
    $state.recovery_backups.Count -eq 0 -and
    -not $state.pid_file_present -and
    -not $state.recovery_run_present
}

function Wait-ForPreviousRollbackConvergence([string]$ExpectedExe) {
  $started = Get-Date
  Write-InstallLog "waiting for previous-version rollback convergence (max attempts: $RollbackConvergenceMaxAttempts, interval ms: $RollbackConvergenceIntervalMilliseconds)"
  for ($attempt = 1; $attempt -le $RollbackConvergenceMaxAttempts; $attempt++) {
    if (Test-RollbackConverged $ExpectedExe) {
      $elapsed = [int]((Get-Date) - $started).TotalMilliseconds
      Write-InstallLog "previous-version rollback convergence confirmed (attempt: $attempt, elapsed ms: $elapsed)"
      return
    }
    $remaining = Get-RollbackState $ExpectedExe | ConvertTo-Json -Compress
    Write-InstallLog "rollback convergence attempt $attempt/$RollbackConvergenceMaxAttempts remaining: $remaining"
    if ($attempt -lt $RollbackConvergenceMaxAttempts) {
      Start-Sleep -Milliseconds $RollbackConvergenceIntervalMilliseconds
    }
  }
  $remaining = Get-RollbackState $ExpectedExe | ConvertTo-Json -Compress
  Write-InstallLog "previous-version rollback convergence timed out: $remaining"
  throw "previous-version rollback did not converge within $RollbackConvergenceMaxAttempts attempts: $remaining"
}

function Invoke-PreviousRollback([string]$ExistingExe) {
  $backups = @(Get-RecoveryBackups)
  if ($backups.Count -gt 0) {
    if (-not (Test-Path -LiteralPath $ExistingExe -PathType Leaf)) {
      throw 'recovery backups remain but the installed Launcher executable is missing; repair is blocked until network recovery can be proven'
    }
    $existingHash = Get-Sha256 $ExistingExe
    Write-InstallLog "invoke-previous-rollback: EXE=$ExistingExe SHA256=$existingHash"
    Write-InstallLog "invoke-previous-rollback: recovery_backups=$($backups -join ',')"
    Write-InstallLog "invoke-previous-rollback: pre-stop registry check"
    try {
      $preStopACU = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'AutoConfigURL' -ErrorAction SilentlyContinue).AutoConfigURL
      $preStopPE = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'ProxyEnable' -ErrorAction SilentlyContinue).ProxyEnable
      Write-InstallLog "invoke-previous-rollback: pre-stop AutoConfigURL=$preStopACU ProxyEnable=$preStopPE"
    } catch {
      Write-InstallLog "invoke-previous-rollback: pre-stop registry read error: $($_.Exception.Message)"
    }
    $global:LASTEXITCODE = 0
    Write-InstallLog "invoke-previous-rollback: calling --stop on $ExistingExe"
    & $ExistingExe --stop
    $stopExit = $LASTEXITCODE
    Write-InstallLog "invoke-previous-rollback: --stop exit code=$stopExit"
    try {
      $postStopACU = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'AutoConfigURL' -ErrorAction SilentlyContinue).AutoConfigURL
      $postStopPE = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'ProxyEnable' -ErrorAction SilentlyContinue).ProxyEnable
      Write-InstallLog "invoke-previous-rollback: post-stop AutoConfigURL=$postStopACU ProxyEnable=$postStopPE"
    } catch {
      Write-InstallLog "invoke-previous-rollback: post-stop registry read error: $($_.Exception.Message)"
    }
    if ($stopExit -ne 0) { throw 'previous version did not complete network rollback' }
    # --stop intentionally leaves the interactive GUI alive. It cannot remain
    # while this helper transactionally replaces the exact same executable.
    Stop-OwnedReplacementBlockers $ExistingExe
    Wait-ForPreviousRollbackConvergence $ExistingExe
    try {
      $finalACU = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'AutoConfigURL' -ErrorAction SilentlyContinue).AutoConfigURL
      $finalPE = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name 'ProxyEnable' -ErrorAction SilentlyContinue).ProxyEnable
      $finalBackups = @(Get-RecoveryBackups)
      Write-InstallLog "invoke-previous-rollback: post-convergence AutoConfigURL=$finalACU ProxyEnable=$finalPE backup_count=$($finalBackups.Count)"
    } catch {
      Write-InstallLog "invoke-previous-rollback: post-convergence registry read error: $($_.Exception.Message)"
    }
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
  if ($embeddedHash -ne $manifest.application_sha256) { throw 'embedded application SHA256 verification failed' }
  $selfHash = Get-Sha256 (Join-Path $PayloadRoot 'upgrade_helper.ps1')
  if ($selfHash -ne $manifest.upgrade_helper_sha256) { throw 'upgrade helper SHA256 verification failed' }

  $existingExe = Join-Path $InstallRoot 'Arvectum Proxy Launcher.exe'
  $ownerMarker = Join-Path $InstallRoot '.arvectum-install-owner'
  $maintenanceKind = Get-MaintenanceKind $existingExe $ownerMarker $manifest
  Write-InstallLog "maintenance mode: $maintenanceKind"
  Write-InstallLog "incoming version: $($manifest.version)"
  Write-InstallLog "final EXE: $existingExe"

  Invoke-PreviousRollback $existingExe
  Remove-StaleRecoveryRun $existingExe
  Assert-RecoveryOwnership $existingExe
  if ($PreflightOnly) {
    Write-InstallLog "=== INSTALL SESSION END: PASS (preflight $maintenanceKind)"
    exit 0
  }

  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  $staged = "$existingExe.new"
  $old = "$existingExe.old"
  Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $payloadExe -Destination $staged -Force
  if ((Get-Sha256 $staged) -ne $manifest.application_sha256) { throw 'staged application SHA256 verification failed' }

  try {
    Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $existingExe) { Move-Item -LiteralPath $existingExe -Destination $old -Force }
    Move-Item -LiteralPath $staged -Destination $existingExe -Force
    if ((Get-Sha256 $existingExe) -ne $manifest.application_sha256) { throw 'final application SHA256 verification failed' }
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
