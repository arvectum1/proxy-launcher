param(
    [string]$AppDir = $PSScriptRoot,
    [switch]$NonInteractive,
    [switch]$Install,
    [string]$SourceDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$taskName = 'ArvectumProxyLauncher'
$shortcut = Join-Path (Get-FolderPath 'Desktop') 'Arvectum Proxy Launcher.lnk'
$startMenuShortcut = Join-Path (Get-FolderPath 'Programs') 'Arvectum Proxy Launcher.lnk'
$arpKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ArvectumProxyLauncher'
$exe = Join-Path $AppDir 'Arvectum Proxy Launcher.exe'
$stateDir = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$internetBackup = Join-Path $stateDir 'proxy_internet_backup.json'
$envBackup = Join-Path $stateDir 'proxy_env_backup.json'
$ownerMarker = Join-Path $AppDir '.arvectum-install-owner'
$ownerMarkerValue = 'ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER'
$legacyOwnerMarkerValue = 'ARVECTUM_PROXY_LAUNCHER_WINDOWS_RC2_1'
$installLog = Join-Path $stateDir 'install.log'

function Get-FolderPath([string]$Folder) {
    switch ($Folder) {
        'Desktop' { return Join-Path $env:USERPROFILE 'Desktop' }
        'Programs' { return Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' }
        'MyDocuments' { return Join-Path $env:USERPROFILE 'Documents' }
        default { return $Folder }
    }
}

function Write-InstallLog([string]$message) {
    try {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        Add-Content -LiteralPath $installLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" -Encoding UTF8
    } catch {}
}

function Get-Sha256([string]$path) {
    $CertUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
    if (-not (Test-Path -LiteralPath $CertUtil -PathType Leaf)) { throw 'certutil.exe not found in System32' }
    $output = & $CertUtil -hashfile $path SHA256
    if ($LASTEXITCODE -ne 0) { throw "certutil SHA256 failed for $path" }
    $hash = @()
    foreach ($line in $output) {
        $stripped = $line -replace '^\s+|\s+$'
        if ($stripped -match '^[0-9A-Fa-f]{64}$') { $hash += $stripped }
    }
    if ($hash.Count -eq 0) { throw "certutil SHA256 produced no hash candidate for $path" }
    if ($hash.Count -gt 1) { throw "certutil SHA256 produced multiple hash candidates for $path" }
    return $hash[0]
}

function Test-ExactPath([string]$left, [string]$right) {
    if (-not $left -or -not $right) { return $false }
    try {
        $resolvedLeft = (Resolve-Path -LiteralPath $left -ErrorAction Stop).Path -replace '\\+$'
    } catch { return $false }
    try {
        $resolvedRight = (Resolve-Path -LiteralPath $right -ErrorAction Stop).Path -replace '\\+$'
    } catch { return $false }
    return $resolvedLeft -ieq $resolvedRight
}

function Get-PathLeaf([string]$Path) {
    if (-not $Path) { return '' }
    $parts = $Path -split '\\'
    return $parts[-1]
}

function Get-PathParent([string]$Path) {
    if (-not $Path) { return '' }
    $parts = $Path -split '\\'
    if ($parts.Count -le 1) { return '' }
    return ($parts[0..($parts.Count - 2)] -join '\')
}

function Normalize-Path([string]$Path) {
    if (-not $Path) { return '' }
    return ($Path -replace '\\+$')
}

function Close-OwnedLauncher([string]$path) {
    $closed = 0
    Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and (Test-ExactPath $_.ExecutablePath $path) } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
            $closed++
        }
    Write-InstallLog "exact-owned GUI processes closed: $closed"
    return $closed
}

function Test-FileUnlocked([string]$path) {
    try {
        $null = Get-Content -LiteralPath $path -ReadCount 0 -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-QuotedCommandTarget([string]$command) {
    if ($command -match '^\s*"([^"]+)"(?:\s+(.*))?\s*$') {
        $commandArgs = if ($matches.Count -gt 2) { $matches[2] } else { '' }
        return [pscustomobject]@{ path = (Normalize-Path $matches[1]); args = ($commandArgs -replace '^\s+|\s+$') }
    }
    return $null
}

function Get-RecoveryRunClassification([string]$command, [string]$canonicalExe) {
    if (-not $command) { return 'NONE' }
    $parsed = Get-QuotedCommandTarget $command
    if (-not $parsed) { return 'FOREIGN_OR_UNKNOWN' }
    if (Test-ExactPath $parsed.path $canonicalExe) {
        if ((Get-PathLeaf $parsed.path) -ieq 'Arvectum Proxy Launcher.exe' -and $parsed.args -ieq '--start') {
            return 'CANONICAL_ARVECTUM'
        }
        return 'FOREIGN_OR_UNKNOWN'
    }
    $leaf = Get-PathLeaf $parsed.path
    $folder = Get-PathParent $parsed.path
    $documents = Join-Path $env:USERPROFILE 'Documents\ArvectumProxyLauncher'
    $oldLocal = Join-Path $env:LOCALAPPDATA 'ArvectumProxyLauncher'
    $stable = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
    $knownFolder = @($documents, $oldLocal, $stable) | Where-Object { Test-ExactPath $_ $folder }
    $tempZip = $parsed.path -match '(?i)\\temp\\[^\\]*arvectum-proxy-launcher-windows-(?:rc2(?:\.1(?:\.1)?)?|0\.2\.1(?:-p0(?:\.\d+)?)?)(?:-client)?\.zip(?:\.[^\\]+)?\\'
    if ($leaf -ieq 'Arvectum Proxy Launcher.exe' -and $parsed.args -ieq '--start' -and ($knownFolder -or $tempZip)) { return 'LEGACY_ARVECTUM' }
    if ($leaf -ieq 'restore_network.bat' -and -not $parsed.args -and $knownFolder) { return 'LEGACY_ARVECTUM' }
    return 'FOREIGN_OR_UNKNOWN'
}

function Test-LegacyArvectumCommand([string]$command, [string]$canonicalExe) {
    return (Get-RecoveryRunClassification $command $canonicalExe) -eq 'LEGACY_ARVECTUM'
}

function Get-LegacyOwnedProcesses([string]$command) {
    $parsed = Get-QuotedCommandTarget $command
    if (-not $parsed) { return @() }
    return @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue | Where-Object {
        if (-not $_.ExecutablePath -or -not (Test-ExactPath $_.ExecutablePath $parsed.path)) { return $false }
        $processCommand = Get-QuotedCommandTarget $_.CommandLine
        return $processCommand -and (Test-ExactPath $processCommand.path $parsed.path) -and $processCommand.args -ieq '--start'
    })
}

function Test-LegacyRecoveryBackupsRemain([string]$legacyExe) {
    $legacyDir = Get-PathParent $legacyExe
    $oldLocal = Join-Path $env:LOCALAPPDATA 'ArvectumProxyLauncher'
    $documents = Join-Path $env:USERPROFILE 'Documents\ArvectumProxyLauncher'
    $backupNames = @('proxy_internet_backup.json', 'proxy_env_backup.json')
    foreach ($dir in @($legacyDir, $oldLocal, $documents, $stateDir) | Select-Object -Unique) {
        foreach ($name in $backupNames) {
            if (Test-Path -LiteralPath (Join-Path $dir $name)) { return $true }
        }
    }
    return $false
}

function Stop-LegacyRecoveryProcess([string]$command, [string]$canonicalExe) {
    $classification = Get-RecoveryRunClassification $command $canonicalExe
    Write-InstallLog "legacy recovery Run classification: $classification; command: $command"
    if ($classification -eq 'FOREIGN_OR_UNKNOWN') {
        throw 'INSTALL FAILED: conflicting recovery autostart is not owned by Arvectum.'
    }
    if ($classification -ne 'LEGACY_ARVECTUM') { return $classification }

    $parsed = Get-QuotedCommandTarget $command
    $processes = @(Get-LegacyOwnedProcesses $command)
    foreach ($process in $processes) {
        Write-InstallLog "legacy recovery process PID/path: $($process.ProcessId) $($process.ExecutablePath)"
    }
    if ($processes.Count -eq 0) {
        Write-InstallLog 'stale legacy Arvectum recovery autostart removed'
        return 'STALE_LEGACY_ARVECTUM'
    }
    if (-not (Test-Path -LiteralPath $parsed.path -PathType Leaf)) {
        Write-InstallLog 'UPDATE BLOCKED: active legacy recovery process has no executable available for graceful stop'
        throw 'UPDATE BLOCKED: active legacy Arvectum recovery process cannot be safely stopped.'
    }

    & $parsed.path --stop
    $stopResult = $LASTEXITCODE
    Write-InstallLog "legacy recovery --stop result: $stopResult"
    if ($null -ne $stopResult -and $stopResult -ne 0) {
        throw 'UPDATE BLOCKED: legacy Arvectum recovery stop failed.'
    }
    $deadline = (Get-Date).AddSeconds(10)
    while (@(Get-LegacyOwnedProcesses $command).Count -gt 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (@(Get-LegacyOwnedProcesses $command).Count -gt 0) {
        Write-InstallLog 'UPDATE BLOCKED: exact legacy recovery process is still active after --stop'
        throw 'UPDATE BLOCKED: legacy Arvectum recovery process did not exit.'
    }
    if (Test-LegacyRecoveryBackupsRemain $parsed.path) {
        Write-InstallLog 'UPDATE BLOCKED: legacy recovery backups remain after --stop'
        throw 'UPDATE BLOCKED: legacy Arvectum recovery is incomplete.'
    }
    Write-InstallLog 'legacy recovery process exited and network recovery completed'
    return 'STOPPED_LEGACY_ARVECTUM'
}

function Migrate-LegacyRunValues([string]$canonicalExe) {
    $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $recovery = (Get-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue).ArvectumProxyLauncherRecovery
    $recoveryResult = Stop-LegacyRecoveryProcess $recovery $canonicalExe
    if ($recovery -and $recoveryResult -in @('STALE_LEGACY_ARVECTUM', 'STOPPED_LEGACY_ARVECTUM')) {
        Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction Stop
        Write-InstallLog 'legacy recovery Run value removed after successful shutdown or stale cleanup'
    }
    $autostart = (Get-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -ErrorAction SilentlyContinue).ArvectumProxyLauncher
    if ($autostart -and (Test-LegacyArvectumCommand $autostart $canonicalExe)) {
        Set-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -Value ('"' + $canonicalExe + '" --start') -ErrorAction Stop
        Write-InstallLog 'legacy user autostart migrated to canonical installation'
    }
}

if ($Install) {
    $sourceDirFull = Normalize-Path $SourceDir
    $sourceExe = Join-Path $sourceDirFull 'Arvectum Proxy Launcher.exe'
    $exeForInstall = Join-Path $AppDir 'Arvectum Proxy Launcher.exe'
    if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) { throw "INSTALL FAILED: release executable is missing: '$sourceExe'." }
    $releaseFiles = @('install.bat', 'install.ps1', 'uninstall.bat', 'uninstall.ps1', 'restore_network.bat', 'INSTALL.txt', 'THIRD_PARTY_NOTICES.txt', 'RELEASE_NOTES_0.2.2_P0.4.md')
    foreach ($name in $releaseFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDirFull $name) -PathType Leaf)) {
            throw "INSTALL FAILED: required release file is missing: '$name'."
        }
    }
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    $sourceHash = Get-Sha256 $sourceExe
    $stagedExe = $exeForInstall + '.new'
    $oldExe = $exeForInstall + '.old'
    Copy-Item -LiteralPath $sourceExe -Destination $stagedExe -Force
    $stagedHash = Get-Sha256 $stagedExe
    Write-InstallLog "source EXE hash: $sourceHash; staged EXE hash: $stagedHash"
    if ($sourceHash -ne $stagedHash) { Remove-Item $stagedExe -Force -ErrorAction SilentlyContinue; throw 'INSTALL FAILED: staged EXE hash does not match source.' }
    if (Test-Path -LiteralPath $exeForInstall -PathType Leaf) {
        Write-InstallLog "previous installed EXE hash: $(Get-Sha256 $exeForInstall)"
        & $exeForInstall --stop
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'UPDATE BLOCKED: previous version could not safely stop and roll back network settings.' }
    }
    Migrate-LegacyRunValues $exeForInstall
    if ((Test-Path -LiteralPath $internetBackup) -or (Test-Path -LiteralPath $envBackup)) {
        throw 'UPDATE BLOCKED: recovery backups remain after stopping the previous version.'
    }
    if (Test-Path -LiteralPath $exeForInstall) {
        Close-OwnedLauncher $exeForInstall | Out-Null
        $deadline = (Get-Date).AddSeconds(5)
        while (-not (Test-FileUnlocked $exeForInstall) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
        if (-not (Test-FileUnlocked $exeForInstall)) { throw 'INSTALL FAILED: previous Launcher is still running.' }
    }
    try {
        if (Test-Path -LiteralPath $oldExe) { Remove-Item $oldExe -Force }
        if (Test-Path -LiteralPath $exeForInstall) { Move-Item -LiteralPath $exeForInstall -Destination $oldExe -Force }
        Move-Item -LiteralPath $stagedExe -Destination $exeForInstall -Force
        $installedHash = Get-Sha256 $exeForInstall
        if ($installedHash -ne $sourceHash) { throw 'installed EXE hash mismatch' }
    } catch {
        Remove-Item $exeForInstall -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $oldExe) { Move-Item -LiteralPath $oldExe -Destination $exeForInstall -Force -ErrorAction SilentlyContinue }
        Remove-Item $stagedExe -Force -ErrorAction SilentlyContinue
        Write-InstallLog "INSTALL FAILED: replacement rolled back: $($_.Exception.Message)"
        throw 'INSTALL FAILED: previous Launcher was restored; see install.log.'
    }
    Remove-Item $oldExe -Force -ErrorAction SilentlyContinue
    Write-InstallLog "final installed EXE hash: $installedHash"
    foreach ($name in $releaseFiles) {
        $sourceFile = Join-Path $sourceDirFull $name
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $AppDir $name) -Force
    }
    $shortcut = Join-Path (Get-FolderPath 'Desktop') 'Arvectum Proxy Launcher.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($shortcut)
    $lnk.TargetPath = $exeForInstall
    $lnk.WorkingDirectory = $AppDir
    $lnk.IconLocation = "$exeForInstall,0"
    $lnk.Save()
    if (-not (Test-Path -LiteralPath $shortcut -PathType Leaf)) {
        throw "Installer finalization failed: desktop shortcut was not created: '$shortcut'."
    }
    $savedShortcut = $shell.CreateShortcut($shortcut)
    if (-not (Test-ExactPath $savedShortcut.TargetPath $exeForInstall) -or -not (Test-ExactPath $savedShortcut.WorkingDirectory $AppDir)) {
        throw 'INSTALL FAILED: desktop shortcut verification failed.'
    }
    Write-InstallLog "desktop shortcut target: $($savedShortcut.TargetPath)"
    Set-Content -LiteralPath $ownerMarker -Value $ownerMarkerValue -Encoding Ascii -NoNewline
    if (-not (Test-Path -LiteralPath $ownerMarker -PathType Leaf)) {
        throw 'Installer finalization failed: ownership marker was not created.'
    }
    Write-InstallLog 'INSTALL SUCCESS'
    Start-Process -FilePath $exeForInstall
    exit 0
}

$fullAppDir = Normalize-Path $AppDir
$protectedPaths = @(
    Normalize-Path $env:USERPROFILE,
    Normalize-Path (Get-FolderPath 'MyDocuments')
)
if ((Get-PathLeaf $fullAppDir) -ne 'ArvectumProxyLauncher') {
    throw "Refusing uninstall: unexpected application directory '$fullAppDir'."
}
if ($protectedPaths -contains $fullAppDir) {
    throw "Refusing uninstall: protected directory '$fullAppDir'."
}
if (-not (Test-Path -LiteralPath $fullAppDir -PathType Container)) {
    throw "Application directory does not exist: '$fullAppDir'."
}
$appDirItem = Get-Item -LiteralPath $fullAppDir -Force
if (($appDirItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Refusing uninstall from a reparse-point application directory.'
}
if (-not (Test-Path -LiteralPath $ownerMarker -PathType Leaf)) {
    throw 'Refusing uninstall: Arvectum ownership marker is missing.'
}
$markerValue = (Get-Content -LiteralPath $ownerMarker -Raw) -replace '^\s+|\s+$'
if ($markerValue -notin @($ownerMarkerValue, $legacyOwnerMarkerValue)) {
    throw 'Refusing uninstall: Arvectum ownership marker is invalid.'
}

Write-Host '============================================'
Write-Host '  Arvectum Proxy Launcher - uninstall'
Write-Host '============================================'
Write-Host ''

Write-Host '[1/3] Restoring network settings...'
if ((Test-Path -LiteralPath $internetBackup) -or (Test-Path -LiteralPath $envBackup)) {
    if (-not (Test-Path -LiteralPath $exe)) {
        throw 'Recovery files exist but the application executable is missing.'
    }
    & $exe --rollback
    if ($LASTEXITCODE -ne 0) { throw 'Network restore is incomplete.' }
}

if ((Test-Path -LiteralPath $internetBackup) -or (Test-Path -LiteralPath $envBackup)) {
    throw 'Network restore is incomplete: recovery files were kept for retry.'
}
Write-Host '       Done.'

Write-Host '[2/3] Removing autostart...'
$taskXml = cmd /c "schtasks /Query /TN $taskName /XML 2>nul"
if ($LASTEXITCODE -eq 0 -and $taskXml -match [regex]::Escape($exe)) {
    schtasks /Delete /F /TN $taskName *> $null
}
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValue = (Get-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue).ArvectumProxyLauncherRecovery
if ($runValue -and $runValue -match [regex]::Escape($exe)) {
    Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncherRecovery' -ErrorAction SilentlyContinue
}
$userAutostart = (Get-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -ErrorAction SilentlyContinue).ArvectumProxyLauncher
if ($userAutostart -and $userAutostart -match [regex]::Escape($exe)) {
    Remove-ItemProperty -Path $runPath -Name 'ArvectumProxyLauncher' -ErrorAction SilentlyContinue
}
Write-Host '       Done.'

Write-Host '[3/3] Removing files and shortcut...'
$ownedProcesses = Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ExecutablePath -and (Test-ExactPath $_.ExecutablePath $exe)
    }
foreach ($process in $ownedProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
}
if ($ownedProcesses) {
    Start-Sleep -Milliseconds 500
}
Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $startMenuShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $arpKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $fullAppDir -Recurse -Force
if (Test-Path -LiteralPath $fullAppDir) { throw "Could not remove application folder: $fullAppDir" }
Write-Host '       Done.'
Write-Host ''
Write-Host 'Application removed. Network settings restored.'

if (-not $NonInteractive) {
    Read-Host 'Press Enter to close'
}