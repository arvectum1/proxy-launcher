<#
.SYNOPSIS
    Canonical APL-WIN-014 enforced acceptance for the dedicated Windows 11 stand.
.DESCRIPTION
    Proves both required release gates under a real enforced App Control for Business
    base policy:
      1. immutable historical 0.2.2 P0.4 -> exact sealed 0.2.3 cross-version upgrade;
      2. exact sealed 0.2.3 install/start/PAC/rollback/repair/uninstall lifecycle.

    This script does not deploy, remove, weaken, or switch App Control policy. Policy
    cutover is a separate lab-owner action. It consumes already-active exact-hash
    supplemental policies and canonical preverified Russian signing evidence.

    Runtime health is proven from the exact executable path, TCP listener, PAC endpoint,
    and WinINET AutoConfigURL. GUI status stdout is intentionally not an acceptance
    signal because the real packaged GUI executable does not expose reliable stdout.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [Guid]$BaselineSupplementalPolicyId,
    [Parameter(Mandatory = $true)] [string]$BaselineManifestPath,
    [Parameter(Mandatory = $true)] [string]$BaselineTrustPackDirectory,
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production',
    [string]$CurrentTrustPackDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\trust-pack',
    [string]$SigningEvidencePath = '',
    [string]$EvidenceDirectory = 'C:\Arvectum\Evidence\APL-WIN-014',
    [switch]$IsolatedAcceptanceEnvironment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedLegacyCommit = '0ea08d9c815da36d0175f62db153de78f89731fc'
$ExpectedLegacyBlobSha1 = '574d3dc5f90a116555e3a72ff3288c31c19d3dc7'
$ExpectedLegacyBlobSize = 15963815
$ExpectedLegacyApplicationSha256 = '7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0'
$ExpectedLegacyRecoverySchema = 'arvectum.proxy.apl-win-014-baseline-recovery.v1'
$ExpectedLegacyTrustSchema = 'arvectum.proxy.apl-win-014-baseline-trust-pack.v1'
$ExpectedCurrentTrustSchema = 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v1'
$ExpectedVersion = '0.2.3'
$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$ExpectedApplicationSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$PacUrl = 'http://127.0.0.1:8082/proxy.pac'
$AppKeyName = '{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}_is1'
$UserUninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppKeyName"
$LegacyUninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ArvectumProxyLauncher'

$preverifiedHelper = Join-Path $PSScriptRoot 'windows_app_control_preverified_release.ps1'
if (-not (Test-Path -LiteralPath $preverifiedHelper -PathType Leaf)) {
    throw "Required acceptance helper is missing: $preverifiedHelper"
}
. $preverifiedHelper

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim().Trim('{}')
    try { return ([Guid]$text).ToString('D').ToLowerInvariant() } catch { return $text.ToLowerInvariant() }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-AdminAndIsolation {
    if ($env:OS -ne 'Windows_NT') { throw 'APL-WIN-014 enforced acceptance must run on Windows.' }
    if (-not $IsolatedAcceptanceEnvironment) {
        throw 'SAFETY BLOCK: dedicated/isolated Windows 11 acceptance host is required.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Elevated Administrator PowerShell is required.'
    }
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

function Get-AppControlPolicies([string]$CiTool) {
    $raw = & $CiTool -lp -json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "CiTool -lp -json failed: $($raw -join ' ')" }
    $parsed = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    $items = if ($parsed.PSObject.Properties['Policies']) { @($parsed.Policies) } else { @($parsed) }
    foreach ($p in $items) {
        [pscustomobject]@{
            policy_id = Normalize-GuidText $p.PolicyID
            base_policy_id = Normalize-GuidText $p.BasePolicyID
            friendly_name = [string]$p.FriendlyName
            is_enforced = [bool]$p.IsEnforced
            is_on_disk = [bool]$p.IsOnDisk
            is_authorized = $(if ($p.PSObject.Properties['IsAuthorized']) { [bool]$p.IsAuthorized } else { $null })
            policy_options = @($p.PolicyOptions)
        }
    }
}

function Assert-EnforcedPolicyState(
    [object[]]$Policies,
    [Guid]$RequestedBasePolicyId,
    [Guid]$RequestedBaselineSupplementalId,
    [Guid]$RequestedCurrentSupplementalId
) {
    $baseId = Normalize-GuidText $RequestedBasePolicyId
    $baselineId = Normalize-GuidText $RequestedBaselineSupplementalId
    $currentId = Normalize-GuidText $RequestedCurrentSupplementalId

    $base = @($Policies | Where-Object { $_.policy_id -eq $baseId })
    $baseline = @($Policies | Where-Object { $_.policy_id -eq $baselineId })
    $current = @($Policies | Where-Object { $_.policy_id -eq $currentId })

    if ($base.Count -ne 1) { throw "Base policy count is $($base.Count), expected 1." }
    if (-not $base[0].is_enforced -or -not $base[0].is_on_disk) {
        throw 'Base App Control policy is not enforced/on-disk.'
    }
    if (@($base[0].policy_options) -contains 'Enabled:Audit Mode') {
        throw 'Base App Control policy still has Enabled:Audit Mode; real enforced acceptance is blocked.'
    }
    if ($baseline.Count -ne 1 -or -not $baseline[0].is_on_disk) {
        throw 'Baseline supplemental policy is not active/on-disk.'
    }
    if ($current.Count -ne 1 -or -not $current[0].is_on_disk) {
        throw 'Current supplemental policy is not active/on-disk.'
    }
    if ($baseline[0].is_authorized -eq $false) { throw 'Baseline supplemental policy is not authorized.' }
    if ($current[0].is_authorized -eq $false) { throw 'Current supplemental policy is not authorized.' }

    return [pscustomobject]@{
        base = $base[0]
        baseline = $baseline[0]
        current = $current[0]
    }
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

function Get-ExactLauncherProcesses([string]$ExePath) {
    if (-not $ExePath) { return @() }
    $full = [IO.Path]::GetFullPath($ExePath)
    return @(
        Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            ([IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $full)
        }
    )
}

function Stop-ExactLauncherProcesses([string]$ExePath) {
    foreach ($p in @(Get-ExactLauncherProcesses $ExePath)) {
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Assert-CleanAcceptanceState([object]$Installed) {
    $stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
    $processes = @(Get-ExactLauncherProcesses $Installed.exe)
    if ((Test-Path -LiteralPath $Installed.root) -or
        (Test-Path -LiteralPath $stateRoot) -or
        (Test-Path -LiteralPath $UserUninstallKey) -or
        (Test-Path -LiteralPath $LegacyUninstallKey) -or
        $processes.Count -gt 0) {
        throw 'Acceptance requires a clean governed Arvectum test state before the enforced gate starts.'
    }
    $listeners = @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) { throw 'Acceptance requires TCP port 8082 to be free before the enforced gate starts.' }
}

function Invoke-InnoSetup([string]$Path, [string]$LogPath, [string]$Label) {
    $p = Start-Process -FilePath $Path -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',("/LOG=$LogPath")
    ) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "$Label failed with exit code $($p.ExitCode)." }
}

function Invoke-Uninstaller([string]$Path, [string]$LogPath, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label uninstaller is missing." }
    $p = Start-Process -FilePath $Path -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$LogPath")
    ) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "$Label failed with exit code $($p.ExitCode)." }
}

function Wait-ForPacRuntime([object]$Installed, [int]$TimeoutSeconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $listeners = @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)
        foreach ($listener in $listeners) {
            $owner = @(
                Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue
            )
            if ($owner.Count -eq 1 -and $owner[0].ExecutablePath) {
                $ownerPath = [IO.Path]::GetFullPath([string]$owner[0].ExecutablePath)
                if ($ownerPath -ieq [IO.Path]::GetFullPath($Installed.exe)) {
                    try {
                        $pac = Invoke-WebRequest -UseBasicParsing -Uri $PacUrl -TimeoutSec 3
                        $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                        $auto = $inet.PSObject.Properties['AutoConfigURL']
                        if ($pac.StatusCode -eq 200 -and
                            ([string]$pac.Content).Length -gt 100 -and
                            $auto -and
                            [string]$auto.Value -eq $PacUrl) {
                            return [pscustomobject]@{
                                listener_pid = [int]$listener.OwningProcess
                                pac_http_status = [int]$pac.StatusCode
                                pac_body_length = ([string]$pac.Content).Length
                                auto_config_url = [string]$auto.Value
                            }
                        }
                    } catch {}
                }
            }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    throw 'Exact current runtime did not establish the governed listener/PAC/AutoConfigURL before timeout.'
}

function Wait-ForPacStopped([int]$TimeoutSeconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $listeners = @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)
        if ($listeners.Count -eq 0) {
            $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            $auto = $inet.PSObject.Properties['AutoConfigURL']
            if (-not $auto -or [string]$auto.Value -ne $PacUrl) { return }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    throw 'Rollback did not remove the governed PAC listener/AutoConfigURL before timeout.'
}

function Invoke-Rollback([object]$Installed) {
    if (-not (Test-Path -LiteralPath $Installed.exe -PathType Leaf)) { throw 'Rollback launcher is missing.' }
    $p = Start-Process -FilePath $Installed.exe -ArgumentList @('--rollback') -PassThru
    if (-not $p.WaitForExit(20000)) {
        throw 'Launcher --rollback did not return before timeout.'
    }
    if ($p.ExitCode -ne 0) { throw "Launcher --rollback failed with exit code $($p.ExitCode)." }
    Wait-ForPacStopped
}

function Start-ExactRuntime([object]$Installed) {
    if ((Get-Sha256 $Installed.exe) -ne $ExpectedApplicationSha256) {
        throw 'Refusing to start non-sealed current application bytes.'
    }
    $starter = Start-Process -FilePath $Installed.exe -ArgumentList @('--start') -PassThru
    # Intentionally no -Wait. The packaged GUI --start path is long-running on the real stand.
    $runtime = Wait-ForPacRuntime -Installed $Installed
    return [pscustomobject]@{
        starter_pid = [int]$starter.Id
        listener_pid = [int]$runtime.listener_pid
        pac_http_status = [int]$runtime.pac_http_status
        pac_body_length = [int]$runtime.pac_body_length
        auto_config_url = [string]$runtime.auto_config_url
    }
}

function Assert-CurrentInstalledExact([object]$Installed) {
    foreach ($required in @($Installed.exe,$Installed.repair,$Installed.uninstaller)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Expected installed lifecycle component is missing: $required"
        }
    }
    if ((Get-Sha256 $Installed.exe) -ne $ExpectedApplicationSha256) {
        throw 'Installed application is not the exact sealed 0.2.3 EXE.'
    }
    if ((Get-Sha256 $Installed.repair) -ne $ExpectedSetupSha256) {
        throw 'Cached repair Setup is not the exact sealed production installer.'
    }
    if (-not (Test-Path -LiteralPath $UserUninstallKey)) { throw 'Current uninstall registration is missing.' }
    $reg = Get-ItemProperty -LiteralPath $UserUninstallKey
    if ([string]$reg.DisplayName -ne 'Arvectum Proxy Launcher') { throw 'Registered DisplayName mismatch.' }
    if ([string]$reg.DisplayVersion -ne $ExpectedVersion) { throw 'Registered DisplayVersion mismatch.' }
}

function Get-CodeIntegrityRecordId {
    try {
        return [long](Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 1 -ErrorAction Stop).RecordId
    } catch { return [long]0 }
}

function Get-NewCodeIntegrityEvents([long]$After) {
    try {
        return @(
            Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -ErrorAction Stop |
            Where-Object { [long]$_.RecordId -gt $After } |
            Select-Object TimeCreated,Id,RecordId,LevelDisplayName,Message
        )
    } catch { return @() }
}

function Read-LegacyBaseline([Guid]$RequestedBasePolicyId, [Guid]$RequestedSupplementalPolicyId) {
    $manifestPath = (Resolve-Path -LiteralPath $BaselineManifestPath).Path
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.schema -ne $ExpectedLegacyRecoverySchema -or [string]$manifest.result -ne 'PASS') {
        throw 'Legacy baseline recovery manifest is not a PASS record.'
    }
    if ([string]$manifest.source.commit -ne $ExpectedLegacyCommit) { throw 'Legacy baseline source commit mismatch.' }
    if ([string]$manifest.source.git_blob_sha1 -ne $ExpectedLegacyBlobSha1 -or
        [long]$manifest.source.git_blob_size -ne $ExpectedLegacyBlobSize) {
        throw 'Legacy baseline immutable Git blob identity mismatch.'
    }
    if ([string]$manifest.baseline.kind -ne 'LegacyClientZip' -or [string]$manifest.baseline.version -ne '0.2.2') {
        throw 'Legacy baseline kind/version mismatch.'
    }
    if (([string]$manifest.baseline.application_exe_sha256).ToLowerInvariant() -ne $ExpectedLegacyApplicationSha256) {
        throw 'Legacy baseline application hash mismatch.'
    }

    $packageZip = (Resolve-Path -LiteralPath ([string]$manifest.baseline.package_zip)).Path
    $packageDirectory = (Resolve-Path -LiteralPath ([string]$manifest.baseline.package_directory)).Path
    $packageRoot = (Resolve-Path -LiteralPath ([string]$manifest.baseline.package_root)).Path
    if ((Get-Sha256 $packageZip) -ne ([string]$manifest.baseline.package_sha256).ToLowerInvariant()) {
        throw 'Legacy recovered ZIP no longer matches recovery evidence.'
    }
    foreach ($record in @($manifest.files)) {
        $full = Join-Path $packageDirectory ([string]$record.relative_path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or
            (Get-Sha256 $full) -ne ([string]$record.sha256).ToLowerInvariant()) {
            throw "Legacy baseline file inventory mismatch: $($record.relative_path)"
        }
    }

    $trustPath = Join-Path (Resolve-Path -LiteralPath $BaselineTrustPackDirectory).Path 'trust-pack.json'
    if (-not (Test-Path -LiteralPath $trustPath -PathType Leaf)) { throw 'Legacy baseline trust-pack manifest is missing.' }
    $trust = Get-Content -LiteralPath $trustPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$trust.schema -ne $ExpectedLegacyTrustSchema -or
        [string]$trust.result -ne 'PASS' -or
        [string]$trust.mode -ne 'LegacyPackageExactHash') {
        throw 'Legacy baseline trust pack is not an exact-hash PASS record.'
    }
    if ((Normalize-GuidText $trust.base_policy_id) -ne (Normalize-GuidText $RequestedBasePolicyId)) {
        throw 'Legacy baseline trust pack targets another base policy.'
    }
    if ((Normalize-GuidText $trust.supplemental_policy_id) -ne (Normalize-GuidText $RequestedSupplementalPolicyId)) {
        throw 'Legacy baseline supplemental PolicyID mismatch.'
    }

    return [pscustomobject]@{
        manifest_path = $manifestPath
        trust_path = $trustPath
        package_root = $packageRoot
        package_sha256 = ([string]$manifest.baseline.package_sha256).ToLowerInvariant()
    }
}

function Install-LegacyBaseline([object]$Legacy, [object]$Installed) {
    $installBat = Join-Path $Legacy.package_root 'install.bat'
    foreach ($required in @($installBat,(Join-Path $Legacy.package_root 'install.ps1'),(Join-Path $Legacy.package_root 'uninstall.ps1'))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Legacy installer component missing: $required" }
    }

    $env:ARVECTUM_APP_DIR = $Installed.root
    $env:ARVECTUM_NONINTERACTIVE = '1'
    try {
        $p = Start-Process -FilePath $installBat -WorkingDirectory $Legacy.package_root -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Historical 0.2.2 P0.4 install failed with exit code $($p.ExitCode)." }
    }
    finally {
        Remove-Item Env:\ARVECTUM_APP_DIR,Env:\ARVECTUM_NONINTERACTIVE -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $Installed.exe -PathType Leaf)) { throw 'Historical application EXE is missing.' }
    if ((Get-Sha256 $Installed.exe) -ne $ExpectedLegacyApplicationSha256) { throw 'Historical installed EXE SHA256 mismatch.' }
    $version = (Get-Item -LiteralPath $Installed.exe).VersionInfo
    if ([string]$version.ProductVersion -ne '0.2.2' -or [string]$version.FileVersion -ne '0.2.2.0') {
        throw 'Historical installed version metadata mismatch.'
    }

    Start-Sleep -Seconds 2
    $observed = @(Get-ExactLauncherProcesses $Installed.exe)
    if ($observed.Count -lt 1) {
        throw 'Historical 0.2.2 GUI process was not observed under enforced App Control.'
    }
    Stop-ExactLauncherProcesses $Installed.exe
}

function Cleanup-OnlyGovernedAcceptanceState([object]$Installed, [object]$Legacy) {
    try { Stop-ExactLauncherProcesses $Installed.exe } catch {}
    try {
        if (Test-Path -LiteralPath $Installed.uninstaller -PathType Leaf) {
            $p = Start-Process -FilePath $Installed.uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru
            $null = $p.WaitForExit(15000)
        }
        elseif ($Legacy -and (Test-Path -LiteralPath $Installed.root -PathType Container)) {
            $legacyUninstall = Join-Path $Legacy.package_root 'uninstall.ps1'
            if (Test-Path -LiteralPath $legacyUninstall -PathType Leaf) {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $legacyUninstall -AppDir $Installed.root -NonInteractive | Out-Null
            }
        }
    } catch {}
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher') -Recurse -Force -ErrorAction SilentlyContinue
}

$os = Assert-AdminAndIsolation
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$CurrentTrustPackDirectory = (Resolve-Path -LiteralPath $CurrentTrustPackDirectory).Path
$BaselineTrustPackDirectory = (Resolve-Path -LiteralPath $BaselineTrustPackDirectory).Path
$BaselineManifestPath = (Resolve-Path -LiteralPath $BaselineManifestPath).Path
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

if (-not $SigningEvidencePath) {
    $SigningEvidencePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\evidence\WINDOWS_RUSSIAN_PRODUCTION_SIGNING_ACCEPTANCE_2026-08-20.json'
}
$release = Assert-ArvectumPreverifiedRussianRelease -ReleaseDirectory $ReleaseDirectory -SigningEvidencePath $SigningEvidencePath

$currentManifestPath = Join-Path $CurrentTrustPackDirectory 'trust-pack.json'
if (-not (Test-Path -LiteralPath $currentManifestPath -PathType Leaf)) {
    throw 'Current ReferenceFullHash trust-pack manifest is missing.'
}
$currentTrust = Get-Content -LiteralPath $currentManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$currentTrust.schema -ne $ExpectedCurrentTrustSchema -or
    [string]$currentTrust.result -ne 'PASS' -or
    [string]$currentTrust.mode -ne 'ReferenceFullHash') {
    throw 'Current trust pack is not a ReferenceFullHash PASS record.'
}
if ((Normalize-GuidText $currentTrust.base_policy_id) -ne (Normalize-GuidText $BasePolicyId)) {
    throw 'Current trust pack targets another base policy.'
}
if (([string]$currentTrust.release.installer_sha256).ToLowerInvariant() -ne $ExpectedSetupSha256 -or
    ([string]$currentTrust.release.application_exe_sha256).ToLowerInvariant() -ne $ExpectedApplicationSha256) {
    throw 'Current trust pack does not bind the exact sealed 0.2.3 release.'
}
$currentSupplementalPolicyId = [Guid]([string]$currentTrust.supplemental_policy_id)

$legacy = Read-LegacyBaseline -RequestedBasePolicyId $BasePolicyId -RequestedSupplementalPolicyId $BaselineSupplementalPolicyId
$ciTool = Get-CiToolPath
$policies = @(Get-AppControlPolicies -CiTool $ciTool)
$policyState = Assert-EnforcedPolicyState -Policies $policies `
    -RequestedBasePolicyId $BasePolicyId `
    -RequestedBaselineSupplementalId $BaselineSupplementalPolicyId `
    -RequestedCurrentSupplementalId $currentSupplementalPolicyId

$installed = Get-InstallInfo
Assert-CleanAcceptanceState -Installed $installed

$stateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$evidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-enforced-acceptance.v3'
    task = 'APL-WIN-014'
    host = $env:COMPUTERNAME
    os = "$($os.Caption) $($os.Version)"
    base_policy_id = $BasePolicyId.ToString('B')
    baseline_supplemental_policy_id = $BaselineSupplementalPolicyId.ToString('B')
    current_supplemental_policy_id = $currentSupplementalPolicyId.ToString('B')
    release_verification = $release.verification
    signing_evidence_path = $release.signing_evidence_path
    signing_evidence_sha256 = $release.signing_evidence_sha256
    historical_commit = $ExpectedLegacyCommit
    historical_git_blob_sha1 = $ExpectedLegacyBlobSha1
    historical_package_sha256 = $legacy.package_sha256
    current_setup_sha256 = $ExpectedSetupSha256
    current_application_sha256 = $ExpectedApplicationSha256
    started_utc = [DateTime]::UtcNow.ToString('o')
    result = 'BLOCK'
    upgrade_gate = 'NOT_RUN'
    current_release_gate = 'NOT_RUN'
    phases = [ordered]@{}
}

$ciStart = Get-CodeIntegrityRecordId
$acceptanceError = $null
try {
    Write-Host '=== APL-WIN-014 ENFORCED GATE: HISTORICAL CROSS-VERSION ==='
    Install-LegacyBaseline -Legacy $legacy -Installed $installed
    $evidence.phases.baseline_exact_historical_bytes = 'PASS'
    $evidence.phases.baseline_gui_execution_under_enforcement = 'PASS'

    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $marker = Join-Path $stateRoot 'apl-win-014-upgrade-marker.txt'
    Set-Content -LiteralPath $marker -Value 'preserve-across-upgrade' -Encoding ASCII

    Invoke-InnoSetup -Path $release.setup -LogPath (Join-Path $EvidenceDirectory 'upgrade-to-0.2.3.log') -Label '0.2.3 cross-version upgrade'
    Assert-CurrentInstalledExact -Installed $installed
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'preserve-across-upgrade') {
        throw 'Per-user marker was not preserved across the real cross-version upgrade.'
    }
    $upgradeRuntime = Start-ExactRuntime -Installed $installed
    $evidence.phases.real_cross_version_upgrade = 'PASS'
    $evidence.phases.state_preserved = 'PASS'
    $evidence.phases.post_upgrade_exact_bytes = 'PASS'
    $evidence.phases.post_upgrade_runtime_listener_pac = 'PASS'
    Invoke-Rollback -Installed $installed
    Stop-ExactLauncherProcesses $installed.exe
    $evidence.phases.post_upgrade_rollback = 'PASS'

    Invoke-Uninstaller -Path $installed.uninstaller -LogPath (Join-Path $EvidenceDirectory 'upgrade-uninstall.log') -Label 'post-upgrade uninstall'
    if (Test-Path -LiteralPath $installed.exe) { throw 'Post-upgrade uninstall left the application EXE behind.' }
    $evidence.phases.post_upgrade_uninstall = 'PASS'
    Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue

    $policiesAfterUpgrade = @(Get-AppControlPolicies -CiTool $ciTool)
    $null = Assert-EnforcedPolicyState -Policies $policiesAfterUpgrade `
        -RequestedBasePolicyId $BasePolicyId `
        -RequestedBaselineSupplementalId $BaselineSupplementalPolicyId `
        -RequestedCurrentSupplementalId $currentSupplementalPolicyId
    $evidence.phases.app_control_enforced_after_upgrade = 'PASS'
    $evidence.upgrade_gate = 'PASS'

    Write-Host '=== APL-WIN-014 ENFORCED GATE: EXACT CURRENT LIFECYCLE ==='
    if (Test-Path -LiteralPath $installed.root -PathType Container) {
        $remaining = @(Get-ChildItem -LiteralPath $installed.root -Force -ErrorAction Stop)
        if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $installed.root -Force }
    }
    Assert-CleanAcceptanceState -Installed $installed

    Invoke-InnoSetup -Path $release.setup -LogPath (Join-Path $EvidenceDirectory 'current-clean-install.log') -Label 'exact current clean install'
    Assert-CurrentInstalledExact -Installed $installed
    $evidence.phases.current_clean_install_exact = 'PASS'

    $currentRuntime = Start-ExactRuntime -Installed $installed
    $evidence.phases.current_start_exact_process = 'PASS'
    $evidence.phases.current_pac_http = 'PASS'
    $evidence.phases.current_wininet_autoconfig = 'PASS'

    Invoke-Rollback -Installed $installed
    Stop-ExactLauncherProcesses $installed.exe
    $evidence.phases.current_rollback = 'PASS'

    $corruptBackup = Join-Path $EvidenceDirectory 'current-app-pre-repair.bin'
    Copy-Item -LiteralPath $installed.exe -Destination $corruptBackup -Force
    Remove-Item -LiteralPath $installed.exe -Force
    if (Test-Path -LiteralPath $installed.exe) { throw 'Acceptance corruption step failed to remove the application EXE.' }

    Invoke-InnoSetup -Path $installed.repair -LogPath (Join-Path $EvidenceDirectory 'current-repair.log') -Label 'exact cached repair Setup'
    Assert-CurrentInstalledExact -Installed $installed
    if ((Get-Sha256 $installed.exe) -ne $ExpectedApplicationSha256) {
        throw 'Repair did not restore exact sealed application bytes.'
    }
    $evidence.phases.current_repair_from_missing_exe = 'PASS'
    Remove-Item -LiteralPath $corruptBackup -Force -ErrorAction SilentlyContinue

    Invoke-Uninstaller -Path $installed.uninstaller -LogPath (Join-Path $EvidenceDirectory 'current-uninstall.log') -Label 'current exact uninstall'
    if (Test-Path -LiteralPath $installed.exe) { throw 'Current uninstall left the application EXE behind.' }
    $evidence.phases.current_uninstall = 'PASS'
    Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue

    $policiesAfterCurrent = @(Get-AppControlPolicies -CiTool $ciTool)
    $null = Assert-EnforcedPolicyState -Policies $policiesAfterCurrent `
        -RequestedBasePolicyId $BasePolicyId `
        -RequestedBaselineSupplementalId $BaselineSupplementalPolicyId `
        -RequestedCurrentSupplementalId $currentSupplementalPolicyId
    $evidence.phases.app_control_remained_enforced = 'PASS'

    $events = @(Get-NewCodeIntegrityEvents -After $ciStart)
    $eventsPath = Join-Path $EvidenceDirectory 'apl-win-014-code-integrity-events.json'
    $events | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $eventsPath -Encoding UTF8
    $blocks = @($events | Where-Object { [int]$_.Id -eq 3077 -and [string]$_.Message -match '(?i)Arvectum' })
    $evidence.code_integrity_events = $eventsPath
    $evidence.arvectum_3077_block_events = $blocks.Count
    if ($blocks.Count -gt 0) {
        throw "Code Integrity recorded $($blocks.Count) Arvectum 3077 enforcement block event(s)."
    }
    $evidence.phases.no_arvectum_enforcement_blocks = 'PASS'

    $evidence.current_release_gate = 'PASS'
    $evidence.result = 'PASS'
}
catch {
    $acceptanceError = $_
}
finally {
    if ($evidence.result -ne 'PASS') {
        Cleanup-OnlyGovernedAcceptanceState -Installed $installed -Legacy $legacy
        try {
            $events = @(Get-NewCodeIntegrityEvents -After $ciStart)
            $eventsPath = Join-Path $EvidenceDirectory 'apl-win-014-code-integrity-events.json'
            $events | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $eventsPath -Encoding UTF8
            $blocks = @($events | Where-Object { [int]$_.Id -eq 3077 -and [string]$_.Message -match '(?i)Arvectum' })
            $evidence.code_integrity_events = $eventsPath
            $evidence.arvectum_3077_block_events = $blocks.Count
        } catch {}
        if ($acceptanceError) { $evidence.block_reason = [string]$acceptanceError.Exception.Message }
    }
    $evidence.finished_utc = [DateTime]::UtcNow.ToString('o')
    $resultPath = Join-Path $EvidenceDirectory 'apl-win-014-enforced-result.json'
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host "Evidence: $resultPath"
}

if ($evidence.result -ne 'PASS') {
    if ($acceptanceError) { throw $acceptanceError }
    throw 'APL-WIN-014 real App Control for Business enforced acceptance: BLOCK'
}

Write-Host 'APL-WIN-014 real App Control for Business local gate: PASS'
Write-Host 'Cross-version upgrade: PASS'
Write-Host 'Historical 0.2.2 P0.4 -> exact 0.2.3 cross-version upgrade: PASS'
Write-Host 'Exact current 0.2.3 lifecycle: PASS'
Write-Host 'Windows App Control remained enforced: PASS'
