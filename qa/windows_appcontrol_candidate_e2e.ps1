<#
.SYNOPSIS
    Normal-Windows lifecycle E2E for the App Control enterprise installer candidate.
.DESCRIPTION
    Exercises the new multi-file/static-runtime packaging before any real Enforced
    device is touched. This is NOT App Control acceptance and never changes policy.

    Gates:
      - fresh install;
      - repair after deleting one exact runtime DLL/PYD;
      - generated Inno uninstaller EXE is byte-identical across fresh/repair/migration;
      - uninstall;
      - migration from the synthetic predecessor onefile layout;
      - final uninstall and legacy top-level payload retirement.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$CandidateSetup,
    [Parameter(Mandatory = $true)] [string]$PredecessorSetup,
    [Parameter(Mandatory = $true)] [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows App Control candidate E2E must run on Windows.' }

$CandidateSetup = (Resolve-Path -LiteralPath $CandidateSetup).Path
$PredecessorSetup = (Resolve-Path -LiteralPath $PredecessorSetup).Path
$EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
$setupDir = Split-Path -Parent $CandidateSetup
$dataFiles = @(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.bin')
if ($dataFiles.Count -lt 1) { throw 'Candidate Setup sibling .bin payload is missing.' }

$root = Join-Path $env:RUNNER_TEMP ("apl-appcontrol-candidate-e2e-" + [guid]::NewGuid().ToString('N'))
$freshRoot = Join-Path $root 'fresh'
$upgradeRoot = Join-Path $root 'upgrade'
$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null

$result = [ordered]@{
    schema = 'arvectum.proxy.windows-app-control-candidate-e2e.v1'
    task = 'APL-WIN-014'
    started_utc = [DateTime]::UtcNow.ToString('o')
    result = 'BLOCK'
    app_control_policy_changed = $false
    fresh_install = 'NOT_RUN'
    repair = 'NOT_RUN'
    uninstaller_deterministic = 'NOT_RUN'
    fresh_uninstaller_sha256 = ''
    repaired_uninstaller_sha256 = ''
    migrated_uninstaller_sha256 = ''
    fresh_uninstall = 'NOT_RUN'
    predecessor_install = 'NOT_RUN'
    migration = 'NOT_RUN'
    migration_uninstall = 'NOT_RUN'
}

function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-Uninstaller([string]$Dir) {
    $candidates = @(Get-ChildItem -LiteralPath $Dir -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one generated Inno uninstaller under $Dir; found $($candidates.Count)."
    }
    $candidates[0].FullName
}

function Invoke-Setup([string]$Setup, [string]$Dir, [string]$Log, [string]$Label) {
    $working = Split-Path -Parent $Setup
    $p = Start-Process -FilePath $Setup -WorkingDirectory $working -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',
        "/DIR=$Dir", "/LOG=$Log"
    ) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "$Label failed with exit code $($p.ExitCode)." }
}

function Invoke-Uninstall([string]$Dir, [string]$Log, [string]$Label) {
    $uninstaller = Resolve-Uninstaller $Dir
    $p = Start-Process -FilePath $uninstaller -WorkingDirectory $Dir -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=$Log"
    ) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "$Label failed with exit code $($p.ExitCode)." }
}

function Read-CandidateInstall([string]$Dir) {
    $manifestPath = Join-Path $Dir 'appcontrol_installer_manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Candidate installer manifest is missing after install.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.result -ne 'PASS' -or [string]$manifest.packaging_layout -ne 'static-runtime') {
        throw 'Installed candidate manifest is invalid.'
    }
    $runtimeDir = Join-Path $Dir ("runtime\" + [string]$manifest.runtime_label)
    $runtimeManifestPath = Join-Path $runtimeDir 'static-runtime.json'
    $entry = Join-Path $runtimeDir 'Arvectum Proxy Launcher.exe'
    $owner = Join-Path $Dir '.arvectum-install-owner'
    foreach ($required in @($runtimeDir,$runtimeManifestPath,$entry,$owner)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Candidate installed component is missing: $required" }
    }
    if ((Get-Content -LiteralPath $owner -Raw -Encoding ASCII).Trim() -ne 'ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER') {
        throw 'Candidate install-owner marker mismatch.'
    }
    $runtime = Get-Content -LiteralPath $runtimeManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$runtime.result -ne 'PASS' -or [bool]$runtime.pyinstaller_onefile) {
        throw 'Installed static-runtime manifest is invalid.'
    }
    if ((Hash $entry) -ne ([string]$runtime.entry_sha256).ToLowerInvariant()) {
        throw 'Installed static runtime entry SHA256 mismatch.'
    }
    [pscustomobject]@{
        manifest = $manifest
        runtime = $runtime
        runtime_dir = $runtimeDir
        entry = $entry
        owner = $owner
        uninstaller = Resolve-Uninstaller $Dir
    }
}

function Assert-NoLegacyTopLevelPayload([string]$Dir) {
    foreach ($name in @(
        'Arvectum Proxy Launcher.exe',
        'Arvectum Proxy Launcher.exe.new',
        'Arvectum Proxy Launcher.exe.old',
        'Arvectum Proxy Launcher Repair.exe',
        'upgrade_helper.ps1',
        'uninstall_helper.ps1',
        'build_manifest.json'
    )) {
        $path = Join-Path $Dir $name
        if (Test-Path -LiteralPath $path) { throw "Legacy onefile payload survived candidate migration/repair: $path" }
    }
}

function Cleanup([string]$Dir) {
    try {
        if (Test-Path -LiteralPath $Dir -PathType Container) {
            $u = @(Get-ChildItem -LiteralPath $Dir -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($u.Count -eq 1) {
                $p = Start-Process -FilePath $u[0].FullName -WorkingDirectory $Dir -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru -Wait
            }
        }
    } catch { }
    try { Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

try {
    Write-Host '=== App Control candidate fresh install ==='
    Invoke-Setup $CandidateSetup $freshRoot (Join-Path $logs 'fresh-install.log') 'fresh install'
    $fresh = Read-CandidateInstall $freshRoot
    Assert-NoLegacyTopLevelPayload $freshRoot
    $result.fresh_uninstaller_sha256 = Hash $fresh.uninstaller
    $result.fresh_install = 'PASS'

    Write-Host '=== App Control candidate repair ==='
    $repairFile = @(
        $fresh.runtime.files |
        Where-Object {
            [bool]$_.executable -and
            [string]$_.relative_path -ne 'Arvectum Proxy Launcher.exe' -and
            ([string]$_.relative_path).ToLowerInvariant().EndsWith('.dll')
        }
    ) | Select-Object -First 1
    if (-not $repairFile) {
        $repairFile = @($fresh.runtime.files | Where-Object { [bool]$_.executable -and [string]$_.relative_path -ne 'Arvectum Proxy Launcher.exe' }) | Select-Object -First 1
    }
    if (-not $repairFile) { throw 'No secondary executable runtime artifact is available for repair injection.' }
    $repairPath = Join-Path $fresh.runtime_dir ([string]$repairFile.relative_path)
    if (-not (Test-Path -LiteralPath $repairPath -PathType Leaf)) { throw 'Repair injection target is missing before deletion.' }
    Remove-Item -LiteralPath $repairPath -Force
    if (Test-Path -LiteralPath $repairPath) { throw 'Repair injection deletion failed.' }
    Invoke-Setup $CandidateSetup $freshRoot (Join-Path $logs 'repair.log') 'repair'
    $repaired = Read-CandidateInstall $freshRoot
    $repairedPath = Join-Path $repaired.runtime_dir ([string]$repairFile.relative_path)
    if (-not (Test-Path -LiteralPath $repairedPath -PathType Leaf)) { throw 'Repair did not restore the deleted runtime artifact.' }
    if ((Hash $repairedPath) -ne ([string]$repairFile.sha256).ToLowerInvariant()) { throw 'Repair restored wrong runtime bytes.' }
    $result.repaired_uninstaller_sha256 = Hash $repaired.uninstaller
    if ([string]$result.repaired_uninstaller_sha256 -ne [string]$result.fresh_uninstaller_sha256) {
        throw 'Generated Inno uninstaller changed bytes during same-candidate repair; hash trust is not deterministic.'
    }
    $result.repair = 'PASS'

    Write-Host '=== App Control candidate fresh uninstall ==='
    Invoke-Uninstall $freshRoot (Join-Path $logs 'fresh-uninstall.log') 'fresh uninstall'
    if (Test-Path -LiteralPath (Join-Path $freshRoot 'runtime')) { throw 'Fresh uninstall left static runtime behind.' }
    if (Test-Path -LiteralPath (Join-Path $freshRoot '.arvectum-install-owner')) { throw 'Fresh uninstall left owner marker behind.' }
    $result.fresh_uninstall = 'PASS'

    Write-Host '=== Synthetic predecessor install ==='
    Invoke-Setup $PredecessorSetup $upgradeRoot (Join-Path $logs 'predecessor-install.log') 'predecessor install'
    $legacyExe = Join-Path $upgradeRoot 'Arvectum Proxy Launcher.exe'
    if (-not (Test-Path -LiteralPath $legacyExe -PathType Leaf)) { throw 'Synthetic predecessor did not produce the legacy top-level Launcher.' }
    $result.predecessor_install = 'PASS'

    Write-Host '=== Synthetic predecessor -> static runtime migration ==='
    Invoke-Setup $CandidateSetup $upgradeRoot (Join-Path $logs 'migration.log') 'candidate migration'
    $migrated = Read-CandidateInstall $upgradeRoot
    Assert-NoLegacyTopLevelPayload $upgradeRoot
    $result.migrated_uninstaller_sha256 = Hash $migrated.uninstaller
    if ([string]$result.migrated_uninstaller_sha256 -ne [string]$result.fresh_uninstaller_sha256) {
        throw 'Generated Inno uninstaller differs between fresh and migrated installs; hash trust is not deterministic.'
    }
    $result.uninstaller_deterministic = 'PASS'
    $result.migration = 'PASS'

    Write-Host '=== Migrated candidate uninstall ==='
    Invoke-Uninstall $upgradeRoot (Join-Path $logs 'migration-uninstall.log') 'migration uninstall'
    if (Test-Path -LiteralPath (Join-Path $upgradeRoot 'runtime')) { throw 'Migration uninstall left static runtime behind.' }
    if (Test-Path -LiteralPath (Join-Path $upgradeRoot '.arvectum-install-owner')) { throw 'Migration uninstall left owner marker behind.' }
    $result.migration_uninstall = 'PASS'

    $result.result = 'PASS'
}
catch {
    $result.block_reason = [string]$_.Exception.Message
    throw
}
finally {
    $result.finished_utc = [DateTime]::UtcNow.ToString('o')
    $evidenceDir = Split-Path -Parent $EvidencePath
    if ($evidenceDir) { New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
    if ($result.result -ne 'PASS') {
        Cleanup $freshRoot
        Cleanup $upgradeRoot
    }
}

Write-Host 'APL-WIN-014 App Control candidate normal-Windows lifecycle: PASS'
Write-Host 'Fresh install: PASS'
Write-Host 'Repair injected runtime loss: PASS'
Write-Host 'Generated Inno uninstaller deterministic hash: PASS'
Write-Host 'Fresh uninstall: PASS'
Write-Host 'Synthetic predecessor migration: PASS'
Write-Host 'Migration uninstall: PASS'
Write-Host 'App Control policy mutation: NONE'
Write-Host "Evidence: $EvidencePath"
