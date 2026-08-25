<#
.SYNOPSIS
    Real cross-version upgrade sub-gate for APL-WIN-014.
.DESCRIPTION
    Installs a separately sealed previous Windows build under active App Control,
    upgrades it in-place to the exact 0.2.3 Russian production release, verifies
    state preservation and exact post-upgrade bytes, then uninstalls cleanly.

    The canonical baseline is the immutable historical 0.2.2 P0.4 customer package
    recovered from Git history by windows_app_control_recover_0_2_2_baseline.ps1.
    A legacy package is accepted only with its exact recovery manifest and exact-hash
    supplemental trust pack. The older InnoSetup baseline parameter set is retained
    only for compatibility with a future separately governed predecessor installer.

    This is acceptance tooling for a dedicated/isolated Windows 11 host. It never
    deploys/removes App Control policies and never weakens Windows protection.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [Guid]$BaselineSupplementalPolicyId,
    [ValidateSet('LegacyClientZip','InnoSetup')] [string]$BaselineKind = 'LegacyClientZip',
    [string]$BaselineManifestPath = '',
    [string]$BaselineTrustPackDirectory = '',
    [string]$BaselineSetupPath = '',
    [string]$BaselineSetupSha256 = '',
    [string]$BaselineApplicationSha256 = '',
    [string]$BaselineVersion = '0.2.2',
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$CurrentTrustPackDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack',
    [string]$EvidenceDirectory = 'C:\Arvectum\Evidence\APL-WIN-014',
    [switch]$IsolatedAcceptanceEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedVersion = '0.2.3'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedApplicationSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$ExpectedLegacyCommit = '0ea08d9c815da36d0175f62db153de78f89731fc'
$ExpectedLegacyBlobSha1 = '574d3dc5f90a116555e3a72ff3288c31c19d3dc7'
$ExpectedLegacyBlobSize = 15963815
$ExpectedLegacyApplicationSha256 = '7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0'
$ExpectedLegacyRecoverySchema = 'arvectum.proxy.apl-win-014-baseline-recovery.v1'
$ExpectedLegacyTrustSchema = 'arvectum.proxy.apl-win-014-baseline-trust-pack.v1'
$AppKeyName = '{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1'
$UserUninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppKeyName"
$LegacyUninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ArvectumProxyLauncher'

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim().Trim('{}')
    try { return ([Guid]$text).ToString('D').ToLowerInvariant() } catch { return $text.ToLowerInvariant() }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-AdminAndIsolation {
    if ($env:OS -ne 'Windows_NT') { throw 'Upgrade acceptance must run on Windows.' }
    if (-not $IsolatedAcceptanceEnvironment) { throw 'SAFETY BLOCK: dedicated/isolated Windows 11 acceptance host is required.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated Administrator PowerShell is required.' }
    $os = Get-CimInstance Win32_OperatingSystem
    $version = [Version]([string]$os.Version)
    if ($version.Build -lt 22000) { throw "Windows 11 is required. Detected: $($os.Caption) $($os.Version)" }
    return $os
}

function Get-CiToolPath {
    $path = Join-Path $env:SystemRoot 'System32\CiTool.exe'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'CiTool.exe is required.' }
    return $path
}

function Get-Policies([string]$CiTool) {
    $raw = & $CiTool -lp -json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "CiTool -lp -json failed: $($raw -join ' ')" }
    $parsed = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    $items = if ($parsed.PSObject.Properties['Policies']) { @($parsed.Policies) } else { @($parsed) }
    foreach ($p in $items) {
        [pscustomobject]@{
            policy_id = Normalize-GuidText $p.PolicyID
            base_policy_id = Normalize-GuidText $p.BasePolicyID
            is_enforced = [bool]$p.IsEnforced
            is_on_disk = [bool]$p.IsOnDisk
            friendly_name = [string]$p.FriendlyName
        }
    }
}

function Assert-CleanState {
    $installRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher'
    $stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue)
    if ((Test-Path -LiteralPath $installRoot) -or (Test-Path -LiteralPath $stateRoot) -or (Test-Path -LiteralPath $UserUninstallKey) -or (Test-Path -LiteralPath $LegacyUninstallKey) -or $processes.Count -gt 0) {
        throw 'Upgrade acceptance requires a clean dedicated-host test state. Clean only governed Arvectum acceptance residue before retrying.'
    }
}

function Invoke-InnoSetup([string]$Path, [string]$LogPath, [string]$Label) {
    $p = Start-Process -FilePath $Path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$LogPath")) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "$Label failed with exit code $($p.ExitCode)." }
}

function Get-InstallInfo {
    $root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher'
    return [pscustomobject]@{
        root = $root
        exe = Join-Path $root 'Arvectum Proxy Launcher.exe'
        repair = Join-Path $root 'Arvectum Proxy Launcher Repair.exe'
        uninstaller = Join-Path $root 'unins000.exe'
    }
}

function Assert-RegisteredVersion([string]$Expected) {
    if (-not (Test-Path -LiteralPath $UserUninstallKey)) { throw 'Expected current per-user uninstall registration is missing.' }
    $reg = Get-ItemProperty -LiteralPath $UserUninstallKey
    if ([string]$reg.DisplayName -ne 'Arvectum Proxy Launcher') { throw 'Unexpected registered DisplayName.' }
    if ([string]$reg.DisplayVersion -ne $Expected) { throw "Registered version mismatch. Expected=$Expected actual=$($reg.DisplayVersion)" }
}

function Get-CodeIntegrityRecordId {
    try { return [long](Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 1 -ErrorAction Stop).RecordId } catch { return [long]0 }
}

function Get-NewCodeIntegrityEvents([long]$After) {
    try { return @(Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -ErrorAction Stop | Where-Object { [long]$_.RecordId -gt $After } | Select-Object TimeCreated, Id, RecordId, LevelDisplayName, Message) } catch { return @() }
}

function Resolve-ExactCurrentSetup([string]$Directory) {
    $candidates = @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.exe' | Where-Object { (Get-Sha256 $_.FullName) -eq $ExpectedSetupSha256 })
    if ($candidates.Count -ne 1) { throw "Expected exactly one sealed 0.2.3 Setup with SHA256 $ExpectedSetupSha256 in $Directory; found $($candidates.Count)." }
    return $candidates[0].FullName
}

function Read-LegacyBaseline([Guid]$RequestedBasePolicyId, [Guid]$RequestedSupplementalPolicyId) {
    if (-not $BaselineManifestPath) { throw 'LegacyClientZip baseline requires -BaselineManifestPath.' }
    if (-not $BaselineTrustPackDirectory) { throw 'LegacyClientZip baseline requires -BaselineTrustPackDirectory.' }
    $manifestPath = (Resolve-Path -LiteralPath $BaselineManifestPath).Path
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.schema -ne $ExpectedLegacyRecoverySchema -or [string]$manifest.result -ne 'PASS') { throw 'Legacy baseline recovery manifest is not a PASS record.' }
    if ([string]$manifest.source.commit -ne $ExpectedLegacyCommit) { throw 'Legacy baseline source commit mismatch.' }
    if ([string]$manifest.source.git_blob_sha1 -ne $ExpectedLegacyBlobSha1 -or [long]$manifest.source.git_blob_size -ne $ExpectedLegacyBlobSize) { throw 'Legacy baseline immutable Git blob identity mismatch.' }
    if ([string]$manifest.baseline.kind -ne 'LegacyClientZip' -or [string]$manifest.baseline.version -ne '0.2.2') { throw 'Legacy baseline kind/version mismatch.' }
    if (([string]$manifest.baseline.application_exe_sha256).ToLowerInvariant() -ne $ExpectedLegacyApplicationSha256) { throw 'Legacy baseline application hash mismatch.' }

    $packageZip = (Resolve-Path -LiteralPath ([string]$manifest.baseline.package_zip)).Path
    $packageDirectory = (Resolve-Path -LiteralPath ([string]$manifest.baseline.package_directory)).Path
    $packageRoot = (Resolve-Path -LiteralPath ([string]$manifest.baseline.package_root)).Path
    if ((Get-Sha256 $packageZip) -ne ([string]$manifest.baseline.package_sha256).ToLowerInvariant()) { throw 'Legacy baseline recovered ZIP no longer matches recovery evidence.' }
    foreach ($record in @($manifest.files)) {
        $full = Join-Path $packageDirectory ([string]$record.relative_path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Sha256 $full) -ne ([string]$record.sha256).ToLowerInvariant()) { throw "Legacy baseline file inventory mismatch: $($record.relative_path)" }
    }

    $trustPath = Join-Path (Resolve-Path -LiteralPath $BaselineTrustPackDirectory).Path 'trust-pack.json'
    if (-not (Test-Path -LiteralPath $trustPath -PathType Leaf)) { throw 'Legacy baseline trust-pack manifest is missing.' }
    $trust = Get-Content -LiteralPath $trustPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$trust.schema -ne $ExpectedLegacyTrustSchema -or [string]$trust.result -ne 'PASS' -or [string]$trust.mode -ne 'LegacyPackageExactHash') { throw 'Legacy baseline trust pack is not an exact-hash PASS record.' }
    if ((Normalize-GuidText $trust.base_policy_id) -ne (Normalize-GuidText $RequestedBasePolicyId)) { throw 'Legacy baseline trust pack targets another base policy.' }
    if ((Normalize-GuidText $trust.supplemental_policy_id) -ne (Normalize-GuidText $RequestedSupplementalPolicyId)) { throw 'Legacy baseline trust pack policy ID differs from the requested active supplemental policy.' }
    if ([string]$trust.baseline.source_commit -ne $ExpectedLegacyCommit -or [string]$trust.baseline.git_blob_sha1 -ne $ExpectedLegacyBlobSha1) { throw 'Legacy baseline trust pack is not bound to the governed historical package.' }
    if (([string]$trust.baseline.application_exe_sha256).ToLowerInvariant() -ne $ExpectedLegacyApplicationSha256) { throw 'Legacy baseline trust pack application hash mismatch.' }
    if (([string]$trust.baseline.package_sha256).ToLowerInvariant() -ne ([string]$manifest.baseline.package_sha256).ToLowerInvariant()) { throw 'Legacy baseline trust pack and recovery manifest disagree on package SHA256.' }

    foreach ($required in @('install.bat','install.ps1','uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $required) -PathType Leaf)) { throw "Legacy baseline required installer component is missing: $required" }
    }
    return [pscustomobject]@{
        manifest_path = $manifestPath
        manifest = $manifest
        trust_path = $trustPath
        trust = $trust
        package_root = $packageRoot
        package_sha256 = ([string]$manifest.baseline.package_sha256).ToLowerInvariant()
        app_sha256 = $ExpectedLegacyApplicationSha256
    }
}

function Install-LegacyBaseline([object]$Legacy, [object]$Installed) {
    $installBat = Join-Path $Legacy.package_root 'install.bat'
    $env:ARVECTUM_APP_DIR = $Installed.root
    $env:ARVECTUM_NONINTERACTIVE = '1'
    try {
        $p = Start-Process -FilePath $installBat -WorkingDirectory $Legacy.package_root -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Historical 0.2.2 P0.4 install.bat failed with exit code $($p.ExitCode)." }
    }
    finally {
        Remove-Item Env:\ARVECTUM_APP_DIR,Env:\ARVECTUM_NONINTERACTIVE -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $Installed.exe -PathType Leaf)) { throw 'Historical 0.2.2 application EXE is missing after installation.' }
    if ((Get-Sha256 $Installed.exe) -ne $ExpectedLegacyApplicationSha256) { throw 'Installed historical baseline application SHA256 mismatch.' }
    $version = (Get-Item -LiteralPath $Installed.exe).VersionInfo
    if ([string]$version.ProductVersion -ne '0.2.2' -or [string]$version.FileVersion -ne '0.2.2.0') { throw 'Installed historical baseline version metadata mismatch.' }

    # P0.4 intentionally launches its GUI after install. Observing and closing only the
    # exact installed path proves that the real historical EXE executed under App Control.
    Start-Sleep -Seconds 2
    $owned = @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and ([IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq [IO.Path]::GetFullPath($Installed.exe))
    })
    if ($owned.Count -lt 1) { throw 'Historical 0.2.2 GUI process was not observed after installation under App Control.' }
    foreach ($process in $owned) { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop }

    $status = (& $Installed.exe --status 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $status -notmatch 'STOPPED') { throw "Historical baseline status smoke failed: $status" }
}

function Cleanup-LegacyBaseline([object]$Legacy, [object]$Installed) {
    if (-not $Legacy) { return }
    if (-not (Test-Path -LiteralPath $Installed.root -PathType Container)) { return }
    if (Test-Path -LiteralPath $Installed.uninstaller -PathType Leaf) { return }
    $legacyUninstall = Join-Path $Legacy.package_root 'uninstall.ps1'
    if (-not (Test-Path -LiteralPath $legacyUninstall -PathType Leaf)) { return }
    try {
        & powershell.exe -NoProfile -File $legacyUninstall -AppDir $Installed.root -NonInteractive
    } catch {}
}

$os = Assert-AdminAndIsolation
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
Assert-CleanState
if ($BaselineVersion -eq $ExpectedVersion) { throw 'Upgrade baseline must be a distinct previous version; same-version repair is not accepted as upgrade evidence.' }

$currentSetup = Resolve-ExactCurrentSetup $ReleaseDirectory
$currentManifestPath = Join-Path $CurrentTrustPackDirectory 'trust-pack.json'
if (-not (Test-Path -LiteralPath $currentManifestPath -PathType Leaf)) { throw 'Current ReferenceFullHash trust-pack manifest is missing.' }
$currentManifest = Get-Content -LiteralPath $currentManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$currentManifest.mode -ne 'ReferenceFullHash') { throw 'Current release must use ReferenceFullHash trust.' }
if ((Normalize-GuidText $currentManifest.base_policy_id) -ne (Normalize-GuidText $BasePolicyId)) { throw 'Current trust pack targets another base policy.' }
if (([string]$currentManifest.release.installer_sha256).ToLowerInvariant() -ne $ExpectedSetupSha256 -or ([string]$currentManifest.release.application_exe_sha256).ToLowerInvariant() -ne $ExpectedApplicationSha256) { throw 'Current trust pack does not bind the exact sealed 0.2.3 release.' }
$currentSupplementalId = Normalize-GuidText $currentManifest.supplemental_policy_id

$legacy = $null
$effectiveBaselineAppSha256 = ''
$effectiveBaselinePackageSha256 = $null
if ($BaselineKind -eq 'LegacyClientZip') {
    if ($BaselineVersion -ne '0.2.2') { throw 'The governed LegacyClientZip baseline version is exactly 0.2.2.' }
    $legacy = Read-LegacyBaseline -RequestedBasePolicyId $BasePolicyId -RequestedSupplementalPolicyId $BaselineSupplementalPolicyId
    $effectiveBaselineAppSha256 = $legacy.app_sha256
    $effectiveBaselinePackageSha256 = $legacy.package_sha256
    if ($BaselineApplicationSha256 -and $BaselineApplicationSha256.ToLowerInvariant() -ne $effectiveBaselineAppSha256) { throw 'Caller-provided BaselineApplicationSha256 disagrees with governed legacy evidence.' }
}
else {
    if (-not $BaselineSetupPath -or -not $BaselineSetupSha256 -or -not $BaselineApplicationSha256) { throw 'InnoSetup baseline requires BaselineSetupPath, BaselineSetupSha256 and BaselineApplicationSha256.' }
    $BaselineSetupPath = (Resolve-Path -LiteralPath $BaselineSetupPath).Path
    $baselineSetupHash = Get-Sha256 $BaselineSetupPath
    if ($baselineSetupHash -ne $BaselineSetupSha256.ToLowerInvariant()) { throw 'Baseline Setup SHA256 mismatch.' }
    if ($BaselineApplicationSha256.Length -ne 64 -or $BaselineApplicationSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'BaselineApplicationSha256 must be a full SHA256.' }
    $effectiveBaselineAppSha256 = $BaselineApplicationSha256.ToLowerInvariant()
}

$ciTool = Get-CiToolPath
$policies = @(Get-Policies -CiTool $ciTool)
$baseId = Normalize-GuidText $BasePolicyId
$baselinePolicyId = Normalize-GuidText $BaselineSupplementalPolicyId
$base = @($policies | Where-Object { $_.policy_id -eq $baseId })
$baselinePolicy = @($policies | Where-Object { $_.policy_id -eq $baselinePolicyId })
$currentPolicy = @($policies | Where-Object { $_.policy_id -eq $currentSupplementalId })
if ($base.Count -ne 1 -or -not $base[0].is_enforced -or -not $base[0].is_on_disk) { throw 'Base App Control policy is not enforced/on-disk.' }
if ($baselinePolicy.Count -ne 1 -or -not $baselinePolicy[0].is_on_disk) { throw 'Baseline supplemental policy is not active/on-disk.' }
if ($currentPolicy.Count -ne 1 -or -not $currentPolicy[0].is_on_disk) { throw 'Current supplemental policy is not active/on-disk.' }

$evidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-upgrade-gate.v2'
    task = 'APL-WIN-014'
    host = $env:COMPUTERNAME
    os = "$($os.Caption) $($os.Version)"
    base_policy_id = $BasePolicyId.ToString('B')
    baseline_supplemental_policy_id = $BaselineSupplementalPolicyId.ToString('B')
    current_supplemental_policy_id = [string]$currentManifest.supplemental_policy_id
    baseline_kind = $BaselineKind
    baseline_version = $BaselineVersion
    current_version = $ExpectedVersion
    baseline_application_sha256 = $effectiveBaselineAppSha256
    baseline_package_sha256 = $effectiveBaselinePackageSha256
    current_setup_sha256 = $ExpectedSetupSha256
    current_application_sha256 = $ExpectedApplicationSha256
    started_utc = [DateTime]::UtcNow.ToString('o')
    result = 'BLOCK'
    phases = [ordered]@{}
}
if ($legacy) {
    $evidence.baseline_source_commit = $ExpectedLegacyCommit
    $evidence.baseline_git_blob_sha1 = $ExpectedLegacyBlobSha1
    $evidence.baseline_recovery_manifest = $legacy.manifest_path
    $evidence.baseline_trust_manifest = $legacy.trust_path
}

$installed = Get-InstallInfo
$stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$ciStart = Get-CodeIntegrityRecordId
try {
    if ($BaselineKind -eq 'LegacyClientZip') {
        Install-LegacyBaseline -Legacy $legacy -Installed $installed
        $evidence.phases.baseline_install_under_enforcement = 'PASS'
        $evidence.phases.baseline_exact_historical_bytes = 'PASS'
        $evidence.phases.baseline_gui_execution_under_enforcement = 'PASS'
    }
    else {
        Invoke-InnoSetup -Path $BaselineSetupPath -LogPath (Join-Path $EvidenceDirectory 'upgrade-baseline-install.log') -Label 'baseline Setup'
        if (-not (Test-Path -LiteralPath $installed.exe -PathType Leaf)) { throw 'Baseline application EXE is missing.' }
        if ((Get-Sha256 $installed.exe) -ne $effectiveBaselineAppSha256) { throw 'Installed baseline application SHA256 mismatch.' }
        $evidence.phases.baseline_install_under_enforcement = 'PASS'
    }

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $marker = Join-Path $stateRoot 'apl-win-014-upgrade-marker.txt'
    Set-Content -LiteralPath $marker -Value 'preserve-across-upgrade' -Encoding ASCII

    Invoke-InnoSetup -Path $currentSetup -LogPath (Join-Path $EvidenceDirectory 'upgrade-to-0.2.3.log') -Label '0.2.3 upgrade Setup'
    Assert-RegisteredVersion -Expected $ExpectedVersion
    if ((Get-Sha256 $installed.exe) -ne $ExpectedApplicationSha256) { throw 'Post-upgrade application is not the exact sealed 0.2.3 EXE.' }
    if ((Get-Sha256 $installed.repair) -ne $ExpectedSetupSha256) { throw 'Post-upgrade cached repair installer is not the exact sealed 0.2.3 Setup.' }
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'preserve-across-upgrade') { throw 'Per-user state marker was not preserved across upgrade.' }
    $status = (& $installed.exe --status 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $status -notmatch 'STOPPED') { throw "Post-upgrade status smoke failed: $status" }
    $evidence.phases.real_cross_version_upgrade = 'PASS'
    $evidence.phases.state_preserved = 'PASS'
    $evidence.phases.post_upgrade_exact_bytes = 'PASS'

    if (-not (Test-Path -LiteralPath $installed.uninstaller -PathType Leaf)) { throw 'Post-upgrade uninstaller is missing.' }
    $un = Start-Process -FilePath $installed.uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=" + (Join-Path $EvidenceDirectory 'upgrade-uninstall.log'))) -PassThru -Wait
    if ($un.ExitCode -ne 0) { throw "Post-upgrade uninstall failed with exit code $($un.ExitCode)." }
    if (Test-Path -LiteralPath $installed.exe) { throw 'Post-upgrade uninstall left the application EXE behind.' }
    $evidence.phases.post_upgrade_uninstall = 'PASS'

    $events = @(Get-NewCodeIntegrityEvents -After $ciStart)
    $eventsPath = Join-Path $EvidenceDirectory 'upgrade-code-integrity-events.json'
    $events | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $eventsPath -Encoding UTF8
    $blocks = @($events | Where-Object { [int]$_.Id -eq 3077 -and [string]$_.Message -match '(?i)Arvectum' })
    $evidence.code_integrity_events = $eventsPath
    $evidence.arvectum_3077_block_events = $blocks.Count
    if ($blocks.Count -gt 0) { throw "Code Integrity recorded $($blocks.Count) Arvectum 3077 block event(s) during upgrade." }
    $evidence.phases.no_upgrade_enforcement_blocks = 'PASS'

    $policiesAfter = @(Get-Policies -CiTool $ciTool)
    $baseAfter = @($policiesAfter | Where-Object { $_.policy_id -eq $baseId })
    if ($baseAfter.Count -ne 1 -or -not $baseAfter[0].is_enforced) { throw 'Base App Control enforcement changed during upgrade acceptance.' }
    $evidence.phases.app_control_remained_enforced = 'PASS'
    $evidence.result = 'PASS'
}
finally {
    try { if (Test-Path -LiteralPath $installed.exe) { & $installed.exe --rollback | Out-Null } } catch {}
    try {
        if (Test-Path -LiteralPath $installed.uninstaller -PathType Leaf) {
            Start-Process -FilePath $installed.uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -Wait | Out-Null
        }
        elseif ($BaselineKind -eq 'LegacyClientZip') {
            Cleanup-LegacyBaseline -Legacy $legacy -Installed $installed
        }
    } catch {}
    Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
    $evidence.finished_utc = [DateTime]::UtcNow.ToString('o')
    $path = Join-Path $EvidenceDirectory 'apl-win-014-upgrade-result.json'
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "Evidence: $path"
}

if ($evidence.result -ne 'PASS') { throw 'APL-WIN-014 real cross-version upgrade sub-gate: BLOCK' }
Write-Host 'APL-WIN-014 real cross-version upgrade under App Control: PASS'
