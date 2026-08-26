<#
.SYNOPSIS
    Generate the post-incident APL-WIN-014 App Control trust pack v2.
.DESCRIPTION
    v2 is intentionally impossible to generate from build/normal-Windows CI alone.
    It requires evidence from a real Enforced lifecycle run and a native recovery
    rehearsal performed in Enforced/ConstrainedLanguage, both bound to the exact
    enterprise bundle being trusted.

    The generator scans exact executable artifacts at Hash level, sanitizes Audit
    Mode from the supplemental XML, and never deploys/removes/changes App Control.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$EnterpriseBundleDirectory,
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [string]$NormalLifecycleEvidencePath,
    [Parameter(Mandatory = $true)] [string]$EnforcedLifecycleEvidencePath,
    [Parameter(Mandatory = $true)] [string]$RecoveryRehearsalEvidencePath,
    [Parameter(Mandatory = $true)] [string]$ReferenceInstalledRoot,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'App Control trust pack v2 generation must run on Windows.' }

function Resolve-Leaf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}
function Resolve-Directory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}
function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Json([string]$Path, [string]$Label) {
    try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$Label is not valid JSON: $($_.Exception.Message)" }
}
function GuidText([object]$Value) {
    ([Guid](([string]$Value).Trim().Trim('{}'))).ToString('D').ToLowerInvariant()
}
function Require-Pass([object]$Value, [string]$Label) {
    if ([string]$Value -ne 'PASS') { throw "SAFETY BLOCK: $Label did not PASS." }
}

$EnterpriseBundleDirectory = Resolve-Directory $EnterpriseBundleDirectory 'enterprise bundle directory'
$NormalLifecycleEvidencePath = Resolve-Leaf $NormalLifecycleEvidencePath 'normal-Windows lifecycle evidence'
$EnforcedLifecycleEvidencePath = Resolve-Leaf $EnforcedLifecycleEvidencePath 'Enforced lifecycle evidence'
$RecoveryRehearsalEvidencePath = Resolve-Leaf $RecoveryRehearsalEvidencePath 'native recovery rehearsal evidence'
$ReferenceInstalledRoot = Resolve-Directory $ReferenceInstalledRoot 'reference installed root'

$bundleManifestPath = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'enterprise-bundle.json') 'enterprise bundle manifest'
$bundleManifestHash = Hash $bundleManifestPath
$bundle = Read-Json $bundleManifestPath 'enterprise bundle manifest'
if ([string]$bundle.schema -ne 'arvectum.proxy.windows-app-control-enterprise-bundle.v1' -or [string]$bundle.result -ne 'PASS') {
    throw 'SAFETY BLOCK: unsupported or non-PASS enterprise bundle manifest.'
}
if (-not [bool]$bundle.static_runtime -or [bool]$bundle.pyinstaller_onefile) {
    throw 'SAFETY BLOCK: trust pack v2 requires static runtime and prohibits PyInstaller onefile.'
}
if ([string]$bundle.setup_loader -ne 'disabled' -or [bool]$bundle.setup_runs_from_temp) {
    throw 'SAFETY BLOCK: trust pack v2 requires UseSetupLdr=no / no Setup TEMP self-copy.'
}
if (-not [bool]$bundle.native_recovery_included -or -not [bool]$bundle.rescue_runtime_included) {
    throw 'SAFETY BLOCK: enterprise bundle lacks native recovery/rescue runtime.'
}

$normal = Read-Json $NormalLifecycleEvidencePath 'normal-Windows lifecycle evidence'
if ([string]$normal.schema -ne 'arvectum.proxy.windows-app-control-candidate-e2e.v1') {
    throw 'SAFETY BLOCK: unsupported normal-Windows lifecycle evidence schema.'
}
Require-Pass $normal.result 'normal-Windows candidate lifecycle'
foreach ($gate in @('fresh_install','repair','fresh_uninstall','predecessor_install','migration','migration_uninstall')) {
    Require-Pass $normal.$gate "normal-Windows lifecycle gate $gate"
}
if ([bool]$normal.app_control_policy_changed) { throw 'SAFETY BLOCK: normal lifecycle evidence reports App Control policy mutation.' }

$enforced = Read-Json $EnforcedLifecycleEvidencePath 'Enforced lifecycle evidence'
if ([string]$enforced.schema -ne 'arvectum.proxy.windows-app-control-enforced-lifecycle.v1') {
    throw 'SAFETY BLOCK: unsupported Enforced lifecycle evidence schema.'
}
Require-Pass $enforced.result 'real Enforced lifecycle'
if ([string]$enforced.environment -ne 'Enforced') { throw 'SAFETY BLOCK: lifecycle evidence was not collected under Enforced App Control.' }
if ((GuidText $enforced.base_policy_id) -ne $BasePolicyId.ToString('D').ToLowerInvariant()) {
    throw 'SAFETY BLOCK: Enforced lifecycle evidence targets another base policy.'
}
if ([string]$enforced.enterprise_bundle_manifest_sha256 -ne $bundleManifestHash) {
    throw 'SAFETY BLOCK: Enforced lifecycle evidence is not bound to this exact enterprise bundle.'
}
foreach ($gate in @('fresh_install','repair','upgrade','uninstall')) {
    Require-Pass $enforced.$gate "Enforced lifecycle gate $gate"
}
if (-not [bool]$enforced.base_remained_enforced) { throw 'SAFETY BLOCK: base policy did not remain Enforced throughout lifecycle evidence.' }
if (-not [bool]$enforced.supplemental_remained_active) { throw 'SAFETY BLOCK: supplemental policy did not remain active throughout lifecycle evidence.' }
if ([int]$enforced.code_integrity_3077_blocks -ne 0) { throw 'SAFETY BLOCK: Enforced lifecycle evidence contains Code Integrity 3077 blocks.' }

$recovery = Read-Json $RecoveryRehearsalEvidencePath 'native recovery rehearsal evidence'
if ([string]$recovery.schema -ne 'arvectum.proxy.apl-win-014-native-recovery-rehearsal.v1') {
    throw 'SAFETY BLOCK: unsupported native recovery rehearsal evidence schema.'
}
Require-Pass $recovery.result 'native recovery rehearsal'
if ([string]$recovery.environment -ne 'Enforced/ConstrainedLanguage') {
    throw 'SAFETY BLOCK: native recovery was not rehearsed in Enforced/ConstrainedLanguage.'
}
if ([string]$recovery.enterprise_bundle_manifest_sha256 -ne $bundleManifestHash) {
    throw 'SAFETY BLOCK: recovery rehearsal is not bound to this exact enterprise bundle.'
}
if ([string]$recovery.native_recovery_sha256 -ne ([string]$bundle.native_recovery_sha256).ToLowerInvariant()) {
    throw 'SAFETY BLOCK: recovery rehearsal used another native recovery executable.'
}
if (-not [bool]$recovery.restores_exact_current_release) { throw 'SAFETY BLOCK: recovery rehearsal did not restore exact current bytes.' }
if (-not [bool]$recovery.restores_pac_connectivity) { throw 'SAFETY BLOCK: recovery rehearsal did not restore PAC connectivity.' }
if (-not [bool]$recovery.base_remained_enforced) { throw 'SAFETY BLOCK: recovery rehearsal did not keep base Enforced.' }
if ([bool]$recovery.changes_base_to_audit) { throw 'SAFETY BLOCK: recovery rehearsal changes base policy to Audit.' }

$installedManifestPath = Resolve-Leaf (Join-Path $ReferenceInstalledRoot 'appcontrol_installer_manifest.json') 'reference install manifest'
$installed = Read-Json $installedManifestPath 'reference install manifest'
if ([string]$installed.schema -ne 'arvectum.proxy.windows-app-control-installer-candidate.v1' -or [string]$installed.result -ne 'PASS') {
    throw 'SAFETY BLOCK: reference installation is not the App Control candidate.'
}
if ([string]$installed.candidate_label -ne [string]$bundle.candidate_label) {
    throw 'SAFETY BLOCK: reference installation candidate label differs from enterprise bundle.'
}
$installedRuntime = Join-Path $ReferenceInstalledRoot ("runtime\" + [string]$installed.runtime_label)
$installedRuntimeManifest = Resolve-Leaf (Join-Path $installedRuntime 'static-runtime.json') 'installed static-runtime manifest'
$installedRuntimeEntry = Resolve-Leaf (Join-Path $installedRuntime 'Arvectum Proxy Launcher.exe') 'installed static runtime entry'
$rescueRuntimeManifest = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'rescue-runtime\static-runtime.json') 'bundle rescue static-runtime manifest'
$rescueEntry = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'rescue-runtime\Arvectum Proxy Launcher.exe') 'bundle rescue runtime entry'
if ((Hash $installedRuntimeManifest) -ne (Hash $rescueRuntimeManifest)) { throw 'SAFETY BLOCK: installed and rescue static-runtime manifests differ.' }
if ((Hash $installedRuntimeEntry) -ne (Hash $rescueEntry)) { throw 'SAFETY BLOCK: installed and rescue static-runtime entry bytes differ.' }
if (Test-Path -LiteralPath (Join-Path $ReferenceInstalledRoot 'Arvectum Proxy Launcher.exe')) {
    throw 'SAFETY BLOCK: legacy top-level onefile executable survives in reference installation.'
}
$uninstallers = @(Get-ChildItem -LiteralPath $ReferenceInstalledRoot -File -Filter 'unins*.exe')
if ($uninstallers.Count -ne 1) { throw "SAFETY BLOCK: reference installation must contain exactly one generated Inno uninstaller; found $($uninstallers.Count)." }

$setupDir = Resolve-Directory (Join-Path $EnterpriseBundleDirectory 'setup') 'bundle setup directory'
$setupExe = @(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.exe')
if ($setupExe.Count -ne 1) { throw "SAFETY BLOCK: enterprise bundle must contain exactly one Setup EXE; found $($setupExe.Count)." }
if (@(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.bin').Count -lt 1) { throw 'SAFETY BLOCK: UseSetupLdr=no sibling BIN is missing.' }
$recoveryExe = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'recovery\Arvectum Proxy Launcher Recovery.exe') 'native recovery executable'
if ((Hash $recoveryExe) -ne ([string]$bundle.native_recovery_sha256).ToLowerInvariant()) {
    throw 'SAFETY BLOCK: native recovery executable bytes differ from enterprise bundle manifest.'
}

foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','Set-RuleOption','ConvertFrom-CIPolicy')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required ConfigCI command is unavailable: $command" }
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PWD ("out\app-control-trust-pack-v2-" + [string]$bundle.version)
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory already exists; refusing overwrite: $OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ("ArvectumAppControlPackV2-" + [guid]::NewGuid().ToString('N'))
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null
try {
    Copy-Item -LiteralPath $setupExe[0].FullName -Destination (Join-Path $scanRoot $setupExe[0].Name) -Force
    Copy-Item -LiteralPath (Join-Path $EnterpriseBundleDirectory 'rescue-runtime') -Destination (Join-Path $scanRoot 'rescue-runtime') -Recurse -Force
    Copy-Item -LiteralPath $recoveryExe -Destination (Join-Path $scanRoot 'Arvectum Proxy Launcher Recovery.exe') -Force
    Copy-Item -LiteralPath $ReferenceInstalledRoot -Destination (Join-Path $scanRoot 'reference-installed') -Recurse -Force

    $xml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-AppControl-Supplemental-v2.xml'
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoScript -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
    Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName ("Arvectum Proxy Launcher " + [string]$bundle.version + " Static Runtime Lifecycle") -SupplementsBasePolicyID $BasePolicyId | Out-Null
    # Supplemental policies must never carry rule option 3; base enforcement state is authoritative.
    Set-RuleOption -FilePath $xml -Option 3 -Delete
    if (Select-String -LiteralPath $xml -Pattern 'Enabled:Audit Mode' -Quiet) { throw 'SAFETY BLOCK: generated supplemental still contains Audit Mode.' }
    Set-CIPolicyVersion -FilePath $xml -Version '2.0.0.0'

    $xmlText = Get-Content -LiteralPath $xml -Raw -Encoding UTF8
    $idMatch = [regex]::Match($xmlText, '<PolicyID>\s*([^<]+)\s*</PolicyID>', 'IgnoreCase')
    if (-not $idMatch.Success) { throw 'Generated v2 supplemental has no PolicyID.' }
    $policyId = $idMatch.Groups[1].Value.Trim()
    $cip = Join-Path $OutputDirectory (($policyId.Trim('{}')) + '.cip')
    ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip
    if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not create the v2 supplemental CIP.' }

    $referenceExecutables = @(
        Get-ChildItem -LiteralPath $ReferenceInstalledRoot -File -Recurse -Force |
        Where-Object { @('.exe','.dll','.pyd','.ocx','.sys') -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                relative_path = $_.FullName.Substring($ReferenceInstalledRoot.Length).TrimStart('\')
                sha256 = Hash $_.FullName
                size = [long]$_.Length
            }
        }
    )

    $manifest = [ordered]@{
        schema = 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v2'
        task = 'APL-WIN-014'
        created_utc = [DateTime]::UtcNow.ToString('o')
        result = 'PASS'
        version = [string]$bundle.version
        candidate_label = [string]$bundle.candidate_label
        mode = 'StaticRuntimeLifecycleHash'
        base_policy_id = $BasePolicyId.ToString('B')
        supplemental_policy_id = $policyId
        supplemental_policy_xml = [IO.Path]::GetFileName($xml)
        supplemental_policy_cip = [IO.Path]::GetFileName($cip)
        packaging_layout = 'static-runtime'
        pyinstaller_onefile = $false
        runtime_complete = $true
        installer_lifecycle_complete = $true
        enforced_lifecycle_ready = $true
        enterprise_bundle_manifest_sha256 = $bundleManifestHash
        setup_exe_sha256 = Hash $setupExe[0].FullName
        native_recovery_sha256 = Hash $recoveryExe
        reference_uninstaller_sha256 = Hash $uninstallers[0].FullName
        reference_executables = $referenceExecutables
        normal_lifecycle_evidence_sha256 = Hash $NormalLifecycleEvidencePath
        enforced_lifecycle_evidence_sha256 = Hash $EnforcedLifecycleEvidencePath
        recovery_rehearsal_evidence_sha256 = Hash $RecoveryRehearsalEvidencePath
        recovery_rehearsal = [ordered]@{
            environment = [string]$recovery.environment
            result = [string]$recovery.result
            restores_exact_current_release = [bool]$recovery.restores_exact_current_release
            restores_pac_connectivity = [bool]$recovery.restores_pac_connectivity
            changes_base_to_audit = [bool]$recovery.changes_base_to_audit
            base_remained_enforced = [bool]$recovery.base_remained_enforced
        }
        deployment_invariants = @(
            'generator never deploys or removes App Control policy',
            'base policy remains Enforced and authoritative',
            'supplemental contains no Enabled:Audit Mode option',
            'trust is exact-byte and release-specific',
            'real Enforced lifecycle evidence is mandatory',
            'real native recovery rehearsal evidence is mandatory'
        )
    }
    $manifest | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'trust-pack.json') -Encoding UTF8

    $sums = Get-ChildItem -LiteralPath $OutputDirectory -File | Sort-Object Name | ForEach-Object { "$(Hash $_.FullName)  $($_.Name)" }
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $sums -Encoding ASCII

    Write-Host 'APL-WIN-014 enterprise trust pack v2: PASS'
    Write-Host "Policy ID: $policyId"
    Write-Host 'Static runtime coverage: PASS'
    Write-Host 'Installer lifecycle evidence: REAL ENFORCED PASS'
    Write-Host 'Native recovery rehearsal: REAL ENFORCED PASS'
    Write-Host 'Audit Mode in supplemental: ABSENT'
    Write-Host 'Deployment: NOT PERFORMED'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
