<#
.SYNOPSIS
    Build a non-promoted supplemental policy for APL-WIN-014 Enforced rehearsal.
.DESCRIPTION
    Breaks the trust/evidence circular dependency safely: exact candidate bytes are
    admitted for a real Enforced rehearsal first, but this provisional pack can never
    satisfy final readiness. Only the post-rehearsal v2 promotion step may set
    enforced_lifecycle_ready=true.

    The builder installs the exact static-runtime candidate once on ordinary Windows
    to capture the deterministic generated Inno uninstaller. It also admits the exact
    immutable historical 0.2.2 onefile outer EXE plus its OFFLINE-extracted native
    PyInstaller CArchive members. This prevents the historical leg from repeating the
    _MEI DLL/PYD denial discovered on ARVECTUM-DEMO.

    This script never deploys/removes/changes App Control policy and never executes the
    historical onefile input while building trust evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$EnterpriseBundleDirectory,
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [string]$NormalLifecycleEvidencePath,
    [Parameter(Mandatory = $true)] [string]$HistoricalPackageDirectory,
    [Parameter(Mandatory = $true)] [string]$HistoricalRuntimeDirectory,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Provisional App Control trust pack must be built on Windows.' }

$ExpectedHistoricalAppSha256 = '7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0'

function Resolve-Leaf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}
function Resolve-Directory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Read-Json([string]$Path, [string]$Label) {
    try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$Label is not valid JSON: $($_.Exception.Message)" }
}
function Require-Pass([object]$Value, [string]$Label) {
    if ([string]$Value -ne 'PASS') { throw "SAFETY BLOCK: $Label did not PASS." }
}
function Resolve-Uninstaller([string]$Root) {
    $items = @(Get-ChildItem -LiteralPath $Root -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
    if ($items.Count -ne 1) { throw "SAFETY BLOCK: reference install must contain exactly one Inno uninstaller; found $($items.Count)." }
    $items[0].FullName
}
function Invoke-Setup([string]$Setup, [string]$Root, [string]$Log) {
    $p = Start-Process -FilePath $Setup -WorkingDirectory (Split-Path -Parent $Setup) -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',"/DIR=$Root","/LOG=$Log"
    ) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "SAFETY BLOCK: reference candidate install failed with exit code $($p.ExitCode)." }
}
function Invoke-Uninstall([string]$Root, [string]$Log) {
    $uninstaller = Resolve-Uninstaller $Root
    $p = Start-Process -FilePath $uninstaller -WorkingDirectory $Root -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=$Log"
    ) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "Reference candidate uninstall failed with exit code $($p.ExitCode)." }
}

$EnterpriseBundleDirectory = Resolve-Directory $EnterpriseBundleDirectory 'enterprise bundle directory'
$NormalLifecycleEvidencePath = Resolve-Leaf $NormalLifecycleEvidencePath 'normal-Windows lifecycle evidence'
$HistoricalPackageDirectory = Resolve-Directory $HistoricalPackageDirectory 'historical package directory'
$HistoricalRuntimeDirectory = Resolve-Directory $HistoricalRuntimeDirectory 'historical onefile runtime directory'

$bundleManifestPath = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'enterprise-bundle.json') 'enterprise bundle manifest'
$bundle = Read-Json $bundleManifestPath 'enterprise bundle manifest'
if ([string]$bundle.schema -ne 'arvectum.proxy.windows-app-control-enterprise-bundle.v1' -or [string]$bundle.result -ne 'PASS') {
    throw 'SAFETY BLOCK: unsupported/non-PASS enterprise bundle.'
}
if (-not [bool]$bundle.static_runtime -or [bool]$bundle.pyinstaller_onefile) { throw 'SAFETY BLOCK: provisional trust requires static runtime and prohibits current onefile.' }
if ([string]$bundle.setup_loader -ne 'disabled' -or [bool]$bundle.setup_runs_from_temp) { throw 'SAFETY BLOCK: UseSetupLdr=no candidate is required.' }
if (-not [bool]$bundle.native_recovery_included -or -not [bool]$bundle.rescue_runtime_included) { throw 'SAFETY BLOCK: native recovery/rescue runtime missing.' }

$normal = Read-Json $NormalLifecycleEvidencePath 'normal-Windows lifecycle evidence'
if ([string]$normal.schema -ne 'arvectum.proxy.windows-app-control-candidate-e2e.v1') { throw 'SAFETY BLOCK: unsupported normal lifecycle evidence.' }
Require-Pass $normal.result 'normal candidate lifecycle'
foreach ($gate in @('fresh_install','repair','uninstaller_deterministic','fresh_uninstall','predecessor_install','migration','migration_uninstall')) {
    Require-Pass $normal.$gate "normal lifecycle gate $gate"
}
if ([bool]$normal.app_control_policy_changed) { throw 'SAFETY BLOCK: normal lifecycle evidence reports App Control mutation.' }
$expectedUninstallerHash = ([string]$normal.fresh_uninstaller_sha256).ToLowerInvariant()
if ($expectedUninstallerHash -notmatch '^[0-9a-f]{64}$') { throw 'SAFETY BLOCK: normal lifecycle has no valid deterministic uninstaller SHA256.' }
foreach ($field in @('repaired_uninstaller_sha256','migrated_uninstaller_sha256')) {
    if (([string]$normal.$field).ToLowerInvariant() -ne $expectedUninstallerHash) { throw "SAFETY BLOCK: normal lifecycle uninstaller hash field $field differs." }
}

$historicalExe = Resolve-Leaf (Join-Path $HistoricalPackageDirectory 'Arvectum Proxy Launcher.exe') 'historical 0.2.2 launcher'
if ((Hash $historicalExe) -ne $ExpectedHistoricalAppSha256) { throw 'SAFETY BLOCK: historical 0.2.2 outer EXE hash mismatch.' }
foreach ($name in @('install.bat','install.ps1','uninstall.ps1','uninstall.bat','restore_network.bat')) {
    $null = Resolve-Leaf (Join-Path $HistoricalPackageDirectory $name) "historical package $name"
}
$historicalRuntimeManifestPath = Resolve-Leaf (Join-Path $HistoricalRuntimeDirectory 'onefile-runtime.json') 'historical onefile runtime inventory'
$historicalRuntime = Read-Json $historicalRuntimeManifestPath 'historical onefile runtime inventory'
if ([string]$historicalRuntime.schema -ne 'arvectum.proxy.pyinstaller-onefile-runtime-inventory.v1' -or [string]$historicalRuntime.result -ne 'PASS') {
    throw 'SAFETY BLOCK: historical onefile runtime inventory is unsupported/non-PASS.'
}
if ([bool]$historicalRuntime.executed_input) { throw 'SAFETY BLOCK: historical onefile extraction evidence claims the input was executed.' }
if ([string]$historicalRuntime.input_sha256 -ne $ExpectedHistoricalAppSha256) { throw 'SAFETY BLOCK: historical onefile inventory targets another EXE.' }
if ([int]$historicalRuntime.executable_member_count -lt 2) { throw 'SAFETY BLOCK: historical onefile native runtime inventory is unexpectedly empty.' }
$historicalNative = @($historicalRuntime.members | Where-Object { [bool]$_.executable })
if ($historicalNative.Count -ne [int]$historicalRuntime.executable_member_count) { throw 'SAFETY BLOCK: historical executable member count mismatch.' }
foreach ($member in $historicalNative) {
    $path = Join-Path $HistoricalRuntimeDirectory ([string]$member.relative_path)
    $path = Resolve-Leaf $path "historical onefile native member $([string]$member.relative_path)"
    if ((Hash $path) -ne ([string]$member.sha256).ToLowerInvariant()) { throw "SAFETY BLOCK: historical onefile native member hash mismatch: $path" }
}

$setupDir = Resolve-Directory (Join-Path $EnterpriseBundleDirectory 'setup') 'bundle setup directory'
$setupExe = @(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.exe')
if ($setupExe.Count -ne 1) { throw "SAFETY BLOCK: bundle must contain exactly one Setup EXE; found $($setupExe.Count)." }
if (@(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.bin').Count -lt 1) { throw 'SAFETY BLOCK: UseSetupLdr=no sibling BIN payload is missing.' }
$rescueRoot = Resolve-Directory (Join-Path $EnterpriseBundleDirectory 'rescue-runtime') 'rescue runtime'
$rescueManifestPath = Resolve-Leaf (Join-Path $rescueRoot 'static-runtime.json') 'rescue runtime manifest'
$rescueManifest = Read-Json $rescueManifestPath 'rescue runtime manifest'
if ([string]$rescueManifest.result -ne 'PASS' -or [bool]$rescueManifest.pyinstaller_onefile -or -not [bool]$rescueManifest.runtime_complete) {
    throw 'SAFETY BLOCK: rescue static runtime is incomplete or onefile.'
}
$rescueEntry = Resolve-Leaf (Join-Path $rescueRoot 'Arvectum Proxy Launcher.exe') 'rescue runtime entry'
if ((Hash $rescueEntry) -ne ([string]$rescueManifest.entry_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: rescue runtime entry hash mismatch.' }
$recoveryExe = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'recovery\Arvectum Proxy Launcher Recovery.exe') 'native recovery executable'
if ((Hash $recoveryExe) -ne ([string]$bundle.native_recovery_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: native recovery hash mismatch.' }

foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','Set-RuleOption','ConvertFrom-CIPolicy')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required ConfigCI command unavailable: $command" }
}

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PWD ("out\app-control-provisional-trust-" + [string]$bundle.version) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { Remove-Item -LiteralPath $OutputDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ("ArvectumAppControlProvisional-" + [guid]::NewGuid().ToString('N'))
$referenceRoot = Join-Path $tempRoot 'reference-installed'
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null
$installed = $false
try {
    Invoke-Setup $setupExe[0].FullName $referenceRoot (Join-Path $tempRoot 'reference-install.log')
    $installed = $true

    $installedManifestPath = Resolve-Leaf (Join-Path $referenceRoot 'appcontrol_installer_manifest.json') 'reference install manifest'
    $installedManifest = Read-Json $installedManifestPath 'reference install manifest'
    if ([string]$installedManifest.schema -ne 'arvectum.proxy.windows-app-control-installer-candidate.v1' -or [string]$installedManifest.result -ne 'PASS') {
        throw 'SAFETY BLOCK: reference installation is not the exact App Control candidate.'
    }
    if ([string]$installedManifest.candidate_label -ne [string]$bundle.candidate_label) { throw 'SAFETY BLOCK: reference candidate label mismatch.' }
    $installedRuntime = Resolve-Directory (Join-Path $referenceRoot ("runtime\" + [string]$installedManifest.runtime_label)) 'installed runtime'
    if ((Hash (Resolve-Leaf (Join-Path $installedRuntime 'static-runtime.json') 'installed runtime manifest')) -ne (Hash $rescueManifestPath)) { throw 'SAFETY BLOCK: installed/rescue runtime manifests differ.' }
    if ((Hash (Resolve-Leaf (Join-Path $installedRuntime 'Arvectum Proxy Launcher.exe') 'installed runtime entry')) -ne (Hash $rescueEntry)) { throw 'SAFETY BLOCK: installed/rescue entry bytes differ.' }
    if (Test-Path -LiteralPath (Join-Path $referenceRoot 'Arvectum Proxy Launcher.exe')) { throw 'SAFETY BLOCK: legacy top-level onefile survived reference install.' }

    $referenceUninstaller = Resolve-Uninstaller $referenceRoot
    $referenceUninstallerHash = Hash $referenceUninstaller
    if ($referenceUninstallerHash -ne $expectedUninstallerHash) { throw 'SAFETY BLOCK: newly generated reference uninstaller differs from normal lifecycle deterministic hash.' }

    Copy-Item -LiteralPath $setupExe[0].FullName -Destination (Join-Path $scanRoot $setupExe[0].Name) -Force
    Copy-Item -LiteralPath $rescueRoot -Destination (Join-Path $scanRoot 'rescue-runtime') -Recurse -Force
    Copy-Item -LiteralPath $recoveryExe -Destination (Join-Path $scanRoot 'Arvectum Proxy Launcher Recovery.exe') -Force
    Copy-Item -LiteralPath $referenceRoot -Destination (Join-Path $scanRoot 'reference-installed') -Recurse -Force
    $historicalScan = Join-Path $scanRoot 'historical-0.2.2'
    New-Item -ItemType Directory -Path $historicalScan -Force | Out-Null
    Copy-Item -LiteralPath $historicalExe -Destination (Join-Path $historicalScan 'Arvectum Proxy Launcher.exe') -Force
    Copy-Item -LiteralPath $HistoricalRuntimeDirectory -Destination (Join-Path $historicalScan 'onefile-runtime') -Recurse -Force

    $xml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-AppControl-Provisional.xml'
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoScript -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
    Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName ("Arvectum Proxy Launcher " + [string]$bundle.version + " Provisional Rehearsal Trust") -SupplementsBasePolicyID $BasePolicyId | Out-Null
    Set-RuleOption -FilePath $xml -Option 3 -Delete
    if (Select-String -LiteralPath $xml -Pattern 'Enabled:Audit Mode' -Quiet) { throw 'SAFETY BLOCK: provisional supplemental contains Audit Mode.' }
    Set-CIPolicyVersion -FilePath $xml -Version '1.0.0.0'
    $xmlText = Get-Content -LiteralPath $xml -Raw -Encoding UTF8
    $idMatch = [regex]::Match($xmlText, '<PolicyID>\s*([^<]+)\s*</PolicyID>', 'IgnoreCase')
    if (-not $idMatch.Success) { throw 'Generated provisional supplemental has no PolicyID.' }
    $policyId = $idMatch.Groups[1].Value.Trim()
    $cip = Join-Path $OutputDirectory (($policyId.Trim('{}')) + '.cip')
    ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip
    if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not create provisional CIP.' }

    $referenceExecutables = @(
        Get-ChildItem -LiteralPath $referenceRoot -File -Recurse -Force |
        Where-Object { @('.exe','.dll','.pyd','.ocx','.sys') -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                relative_path = $_.FullName.Substring($referenceRoot.Length).TrimStart('\')
                sha256 = Hash $_.FullName
                size = [long]$_.Length
            }
        }
    )
    $historicalNativeEvidence = @(
        $historicalNative | Sort-Object { [string]$_.relative_path } | ForEach-Object {
            [ordered]@{
                relative_path = [string]$_.relative_path
                sha256 = ([string]$_.sha256).ToLowerInvariant()
                size = [long]$_.size
            }
        }
    )

    Copy-Item -LiteralPath $historicalRuntimeManifestPath -Destination (Join-Path $OutputDirectory 'historical-onefile-runtime.json') -Force

    $manifest = [ordered]@{
        schema = 'arvectum.proxy.windows-app-control-provisional-trust-pack.v1'
        task = 'APL-WIN-014'
        created_utc = [DateTime]::UtcNow.ToString('o')
        result = 'PASS'
        purpose = 'rehearsal-only'
        promoted_release = $false
        final_acceptance_evidence = $false
        enforced_lifecycle_ready = $false
        version = [string]$bundle.version
        candidate_label = [string]$bundle.candidate_label
        mode = 'StaticRuntimeLifecycleHash-Provisional'
        base_policy_id = $BasePolicyId.ToString('B')
        supplemental_policy_id = $policyId
        supplemental_policy_xml = [IO.Path]::GetFileName($xml)
        supplemental_policy_cip = [IO.Path]::GetFileName($cip)
        supplemental_policy_cip_sha256 = Hash $cip
        packaging_layout = 'static-runtime'
        pyinstaller_onefile = $false
        runtime_complete = $true
        setup_loader = 'disabled'
        setup_runs_from_temp = $false
        enterprise_bundle_manifest_sha256 = Hash $bundleManifestPath
        setup_exe_sha256 = Hash $setupExe[0].FullName
        native_recovery_sha256 = Hash $recoveryExe
        reference_uninstaller_sha256 = $referenceUninstallerHash
        reference_executables = $referenceExecutables
        historical_package_version = '0.2.2-P0.4'
        historical_outer_exe_sha256 = $ExpectedHistoricalAppSha256
        historical_onefile_runtime_inventory_sha256 = Hash $historicalRuntimeManifestPath
        historical_onefile_runtime_executable_count = $historicalNativeEvidence.Count
        historical_onefile_runtime_executables = $historicalNativeEvidence
        historical_onefile_input_executed_during_trust_build = $false
        normal_lifecycle_evidence_sha256 = Hash $NormalLifecycleEvidencePath
        normal_uninstaller_determinism = 'PASS'
        deployment_invariants = @(
            'rehearsal-only supplemental; never final acceptance evidence',
            'builder never deploys/removes/changes App Control policy',
            'base policy remains authoritative',
            'supplemental contains no Enabled:Audit Mode',
            'exact-byte release-specific hash trust',
            'immutable 0.2.2 onefile native CArchive members are admitted without executing the input',
            'final v2 readiness requires real Enforced lifecycle and native recovery rehearsal against this exact provisional policy'
        )
    }
    $manifestPath = Join-Path $OutputDirectory 'provisional-trust-pack.json'
    $manifest | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host 'APL-WIN-014 provisional App Control trust pack: PASS'
    Write-Host "Supplemental PolicyID: $policyId"
    Write-Host "CIP SHA256: $(Hash $cip)"
    Write-Host "Reference uninstaller SHA256: $referenceUninstallerHash"
    Write-Host "Historical onefile native members trusted: $($historicalNativeEvidence.Count)"
    Write-Host 'Historical onefile execution during trust build: NO'
    Write-Host 'Purpose: REHEARSAL ONLY'
    Write-Host 'Enforced lifecycle readiness: FALSE'
    Write-Host 'App Control policy mutation: NONE'
    Write-Host "Output: $OutputDirectory"
}
finally {
    if ($installed -and (Test-Path -LiteralPath $referenceRoot -PathType Container)) {
        try { Invoke-Uninstall $referenceRoot (Join-Path $tempRoot 'reference-uninstall.log') } catch { Write-Warning $_.Exception.Message }
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
