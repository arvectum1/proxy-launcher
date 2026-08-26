<#
.SYNOPSIS
    Promote an exact rehearsal-tested provisional supplemental into final APL-WIN-014 trust-pack v2.
.DESCRIPTION
    Final v2 trust is evidence promotion, not a second policy build. The exact same
    provisional CIP that was deployed for the real Enforced lifecycle and native
    recovery rehearsal is copied unchanged into the final pack.

    This removes the former circular dependency where final trust generation required
    Enforced evidence before a supplemental existed. Ordinary CI may build the
    provisional pack, but only real Enforced + recovery evidence bound to that exact
    provisional manifest can produce enforced_lifecycle_ready=true.

    This script never deploys/removes/changes App Control policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$EnterpriseBundleDirectory,
    [Parameter(Mandatory = $true)] [string]$ProvisionalTrustPackDirectory,
    [Parameter(Mandatory = $true)] [string]$EnforcedLifecycleEvidencePath,
    [Parameter(Mandatory = $true)] [string]$RecoveryRehearsalEvidencePath,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
function GuidText([object]$Value) { ([Guid](([string]$Value).Trim().Trim('{}'))).ToString('D').ToLowerInvariant() }
function Require-Pass([object]$Value, [string]$Label) {
    if ([string]$Value -ne 'PASS') { throw "SAFETY BLOCK: $Label did not PASS." }
}

$EnterpriseBundleDirectory = Resolve-Directory $EnterpriseBundleDirectory 'enterprise bundle directory'
$ProvisionalTrustPackDirectory = Resolve-Directory $ProvisionalTrustPackDirectory 'provisional trust pack directory'
$EnforcedLifecycleEvidencePath = Resolve-Leaf $EnforcedLifecycleEvidencePath 'Enforced lifecycle evidence'
$RecoveryRehearsalEvidencePath = Resolve-Leaf $RecoveryRehearsalEvidencePath 'native recovery rehearsal evidence'

$bundleManifestPath = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'enterprise-bundle.json') 'enterprise bundle manifest'
$bundleManifestHash = Hash $bundleManifestPath
$bundle = Read-Json $bundleManifestPath 'enterprise bundle manifest'
if ([string]$bundle.schema -ne 'arvectum.proxy.windows-app-control-enterprise-bundle.v1' -or [string]$bundle.result -ne 'PASS') {
    throw 'SAFETY BLOCK: unsupported/non-PASS enterprise bundle.'
}
if (-not [bool]$bundle.static_runtime -or [bool]$bundle.pyinstaller_onefile) { throw 'SAFETY BLOCK: final v2 requires static runtime and prohibits onefile.' }
if ([string]$bundle.setup_loader -ne 'disabled' -or [bool]$bundle.setup_runs_from_temp) { throw 'SAFETY BLOCK: final v2 requires UseSetupLdr=no.' }

$provisionalManifestPath = Resolve-Leaf (Join-Path $ProvisionalTrustPackDirectory 'provisional-trust-pack.json') 'provisional trust manifest'
$provisionalManifestHash = Hash $provisionalManifestPath
$provisional = Read-Json $provisionalManifestPath 'provisional trust manifest'
if ([string]$provisional.schema -ne 'arvectum.proxy.windows-app-control-provisional-trust-pack.v1') { throw 'SAFETY BLOCK: unsupported provisional trust schema.' }
Require-Pass $provisional.result 'provisional trust build'
if ([string]$provisional.purpose -ne 'rehearsal-only' -or [bool]$provisional.final_acceptance_evidence -or [bool]$provisional.enforced_lifecycle_ready) {
    throw 'SAFETY BLOCK: provisional manifest incorrectly claims final acceptance/readiness.'
}
if ([string]$provisional.enterprise_bundle_manifest_sha256 -ne $bundleManifestHash) { throw 'SAFETY BLOCK: provisional trust targets another enterprise bundle.' }
if ([string]$provisional.candidate_label -ne [string]$bundle.candidate_label) { throw 'SAFETY BLOCK: provisional candidate label differs.' }
if ([string]$provisional.packaging_layout -ne 'static-runtime' -or [bool]$provisional.pyinstaller_onefile) { throw 'SAFETY BLOCK: provisional trust is not static-runtime hash trust.' }
if ([string]$provisional.setup_loader -ne 'disabled' -or [bool]$provisional.setup_runs_from_temp) { throw 'SAFETY BLOCK: provisional trust does not bind UseSetupLdr=no.' }
if ([string]$provisional.normal_uninstaller_determinism -ne 'PASS') { throw 'SAFETY BLOCK: deterministic generated uninstaller was not proven before rehearsal.' }

$provisionalXml = Resolve-Leaf (Join-Path $ProvisionalTrustPackDirectory ([string]$provisional.supplemental_policy_xml)) 'provisional supplemental XML'
$provisionalCip = Resolve-Leaf (Join-Path $ProvisionalTrustPackDirectory ([string]$provisional.supplemental_policy_cip)) 'provisional supplemental CIP'
if ((Hash $provisionalCip) -ne ([string]$provisional.supplemental_policy_cip_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: provisional CIP hash mismatch.' }
if (Select-String -LiteralPath $provisionalXml -Pattern 'Enabled:Audit Mode' -Quiet) { throw 'SAFETY BLOCK: provisional supplemental XML contains Audit Mode.' }

$baseId = GuidText $provisional.base_policy_id
$supplementalId = GuidText $provisional.supplemental_policy_id
$rescueManifestPath = Resolve-Leaf (Join-Path $EnterpriseBundleDirectory 'rescue-runtime\static-runtime.json') 'rescue runtime manifest'
$rescue = Read-Json $rescueManifestPath 'rescue runtime manifest'
$runtimeEntryHash = ([string]$rescue.entry_sha256).ToLowerInvariant()
if ($runtimeEntryHash -notmatch '^[0-9a-f]{64}$') { throw 'SAFETY BLOCK: rescue runtime entry SHA256 is invalid.' }

$enforced = Read-Json $EnforcedLifecycleEvidencePath 'Enforced lifecycle evidence'
if ([string]$enforced.schema -ne 'arvectum.proxy.windows-app-control-enforced-lifecycle.v1') { throw 'SAFETY BLOCK: unsupported Enforced lifecycle evidence schema.' }
Require-Pass $enforced.result 'real Enforced lifecycle'
if ([string]$enforced.environment -ne 'Enforced') { throw 'SAFETY BLOCK: lifecycle evidence was not collected under Enforced App Control.' }
if ((GuidText $enforced.base_policy_id) -ne $baseId) { throw 'SAFETY BLOCK: Enforced lifecycle targets another base policy.' }
if ((GuidText $enforced.supplemental_policy_id) -ne $supplementalId) { throw 'SAFETY BLOCK: Enforced lifecycle did not use this exact provisional supplemental.' }
if ([string]$enforced.enterprise_bundle_manifest_sha256 -ne $bundleManifestHash) { throw 'SAFETY BLOCK: Enforced lifecycle targets another bundle.' }
if ([string]$enforced.provisional_trust_pack_manifest_sha256 -ne $provisionalManifestHash) { throw 'SAFETY BLOCK: Enforced lifecycle is not bound to this provisional manifest.' }
if ([string]$enforced.provisional_cip_sha256 -ne (Hash $provisionalCip)) { throw 'SAFETY BLOCK: Enforced lifecycle is not bound to this exact provisional CIP.' }
if ([string]$enforced.runtime_entry_sha256 -ne $runtimeEntryHash) { throw 'SAFETY BLOCK: Enforced lifecycle observed another runtime entry.' }
if ([string]$enforced.uninstaller_sha256 -ne ([string]$provisional.reference_uninstaller_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: Enforced lifecycle observed another uninstaller.' }
foreach ($gate in @('fresh_install','repair','upgrade','uninstall')) { Require-Pass $enforced.$gate "Enforced lifecycle gate $gate" }
if (-not [bool]$enforced.base_remained_enforced) { throw 'SAFETY BLOCK: base did not remain Enforced.' }
if (-not [bool]$enforced.supplemental_remained_active) { throw 'SAFETY BLOCK: provisional supplemental did not remain active.' }
if ([int]$enforced.code_integrity_3077_blocks -ne 0) { throw 'SAFETY BLOCK: Enforced lifecycle contains Code Integrity 3077 blocks.' }

$recovery = Read-Json $RecoveryRehearsalEvidencePath 'native recovery rehearsal evidence'
if ([string]$recovery.schema -ne 'arvectum.proxy.apl-win-014-native-recovery-rehearsal.v1') { throw 'SAFETY BLOCK: unsupported recovery rehearsal schema.' }
Require-Pass $recovery.result 'native recovery rehearsal'
if ([string]$recovery.environment -ne 'Enforced/ConstrainedLanguage') { throw 'SAFETY BLOCK: recovery was not rehearsed with Enforced/ConstrainedLanguage proven.' }
if ((GuidText $recovery.base_policy_id) -ne $baseId) { throw 'SAFETY BLOCK: recovery rehearsal targets another base policy.' }
if ((GuidText $recovery.supplemental_policy_id) -ne $supplementalId) { throw 'SAFETY BLOCK: recovery rehearsal did not use this provisional supplemental.' }
if ([string]$recovery.enterprise_bundle_manifest_sha256 -ne $bundleManifestHash) { throw 'SAFETY BLOCK: recovery rehearsal targets another bundle.' }
if ([string]$recovery.provisional_trust_pack_manifest_sha256 -ne $provisionalManifestHash) { throw 'SAFETY BLOCK: recovery rehearsal is not bound to this provisional manifest.' }
if ([string]$recovery.provisional_cip_sha256 -ne (Hash $provisionalCip)) { throw 'SAFETY BLOCK: recovery rehearsal is not bound to this provisional CIP.' }
if ([string]$recovery.native_recovery_sha256 -ne ([string]$bundle.native_recovery_sha256).ToLowerInvariant()) { throw 'SAFETY BLOCK: recovery used another native recovery executable.' }
if ([string]$recovery.runtime_entry_sha256 -ne $runtimeEntryHash) { throw 'SAFETY BLOCK: recovery restored another runtime entry.' }
if (-not [bool]$recovery.restores_exact_current_release) { throw 'SAFETY BLOCK: recovery did not restore exact current bytes.' }
if (-not [bool]$recovery.restores_pac_connectivity) { throw 'SAFETY BLOCK: recovery did not restore PAC connectivity.' }
if (-not [bool]$recovery.base_remained_enforced) { throw 'SAFETY BLOCK: recovery did not keep base Enforced.' }
if (-not [bool]$recovery.supplemental_remained_active) { throw 'SAFETY BLOCK: recovery did not keep supplemental active.' }
if ([bool]$recovery.changes_base_to_audit) { throw 'SAFETY BLOCK: recovery changes base to Audit.' }
if ([int]$recovery.code_integrity_3077_blocks -ne 0) { throw 'SAFETY BLOCK: recovery rehearsal contains Code Integrity 3077 blocks.' }

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PWD ("out\app-control-trust-pack-v2-" + [string]$bundle.version) }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output directory already exists; refusing overwrite: $OutputDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$xmlName = [IO.Path]::GetFileName($provisionalXml)
$cipName = [IO.Path]::GetFileName($provisionalCip)
Copy-Item -LiteralPath $provisionalXml -Destination (Join-Path $OutputDirectory $xmlName) -Force
Copy-Item -LiteralPath $provisionalCip -Destination (Join-Path $OutputDirectory $cipName) -Force
Copy-Item -LiteralPath $provisionalManifestPath -Destination (Join-Path $OutputDirectory 'provisional-trust-pack.json') -Force
Copy-Item -LiteralPath $EnforcedLifecycleEvidencePath -Destination (Join-Path $OutputDirectory 'enforced-lifecycle.json') -Force
Copy-Item -LiteralPath $RecoveryRehearsalEvidencePath -Destination (Join-Path $OutputDirectory 'native-recovery-rehearsal.json') -Force

$manifest = [ordered]@{
    schema = 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v2'
    task = 'APL-WIN-014'
    created_utc = [DateTime]::UtcNow.ToString('o')
    result = 'PASS'
    version = [string]$bundle.version
    candidate_label = [string]$bundle.candidate_label
    mode = 'StaticRuntimeLifecycleHash'
    base_policy_id = [string]$provisional.base_policy_id
    supplemental_policy_id = [string]$provisional.supplemental_policy_id
    supplemental_policy_xml = $xmlName
    supplemental_policy_cip = $cipName
    supplemental_policy_cip_sha256 = Hash (Join-Path $OutputDirectory $cipName)
    packaging_layout = 'static-runtime'
    pyinstaller_onefile = $false
    runtime_complete = $true
    installer_lifecycle_complete = $true
    enforced_lifecycle_ready = $true
    enterprise_bundle_manifest_sha256 = $bundleManifestHash
    provisional_trust_pack_manifest_sha256 = $provisionalManifestHash
    setup_exe_sha256 = [string]$provisional.setup_exe_sha256
    native_recovery_sha256 = [string]$provisional.native_recovery_sha256
    runtime_entry_sha256 = $runtimeEntryHash
    reference_uninstaller_sha256 = [string]$provisional.reference_uninstaller_sha256
    reference_executables = $provisional.reference_executables
    normal_lifecycle_evidence_sha256 = [string]$provisional.normal_lifecycle_evidence_sha256
    enforced_lifecycle_evidence_sha256 = Hash $EnforcedLifecycleEvidencePath
    recovery_rehearsal_evidence_sha256 = Hash $RecoveryRehearsalEvidencePath
    recovery_rehearsal = [ordered]@{
        environment = [string]$recovery.environment
        result = [string]$recovery.result
        restores_exact_current_release = [bool]$recovery.restores_exact_current_release
        restores_pac_connectivity = [bool]$recovery.restores_pac_connectivity
        changes_base_to_audit = [bool]$recovery.changes_base_to_audit
        base_remained_enforced = [bool]$recovery.base_remained_enforced
        supplemental_remained_active = [bool]$recovery.supplemental_remained_active
        code_integrity_3077_blocks = [int]$recovery.code_integrity_3077_blocks
    }
    promotion_invariants = @(
        'the exact rehearsal-tested provisional XML/CIP is copied unchanged',
        'ordinary CI cannot manufacture final readiness',
        'real Enforced lifecycle evidence is mandatory and hash-bound',
        'real native recovery rehearsal evidence is mandatory and hash-bound',
        'base remains Enforced; no Audit rollback is permitted',
        'promotion script never deploys/removes/changes App Control policy'
    )
}
$manifestPath = Join-Path $OutputDirectory 'trust-pack.json'
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host 'APL-WIN-014 enterprise trust pack v2 promotion: PASS'
Write-Host "Supplemental PolicyID: $([string]$provisional.supplemental_policy_id)"
Write-Host 'Exact rehearsal-tested provisional CIP preserved: PASS'
Write-Host 'Real Enforced lifecycle: PASS'
Write-Host 'Native recovery rehearsal: PASS'
Write-Host 'Enforced lifecycle readiness: TRUE'
Write-Host 'App Control policy mutation: NONE'
Write-Host "Output: $OutputDirectory"
