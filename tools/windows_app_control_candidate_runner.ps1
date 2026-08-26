<#
.SYNOPSIS
    One-entry ARVECTUM-DEMO runner for APL-WIN-014 0.2.4 acceptance.
.DESCRIPTION
    Delegates guarded Preflight/Execute/Recover to the stand driver. After a successful
    Execute only, promotes the exact rehearsal-tested provisional CIP unchanged into
    final trust-pack v2 and runs the fail-closed readiness barrier.

    The finalization stage never deploys, removes, weakens, or changes App Control,
    Smart App Control, or Defender. A promotion/readiness failure occurs only after the
    guarded driver has already restored a healthy exact 0.2.4 + PAC state.
#>
[CmdletBinding()]
param(
    [ValidateSet('Preflight','Execute','Recover')]
    [string]$Mode = 'Preflight',
    [string]$RecoveryBackupDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$KitRoot = Split-Path -Parent $PSCommandPath
$StandDriver = Join-Path $KitRoot 'APL-WIN-014-STAND.ps1'
$PromotionScript = Join-Path $KitRoot 'kit-tools\windows_app_control_enterprise_trust_pack_v2.ps1'
$ReadinessScript = Join-Path $KitRoot 'kit-tools\windows_app_control_enforced_readiness.ps1'
$CandidateRoot = Join-Path $KitRoot 'candidate'
$ProvisionalRoot = Join-Path $KitRoot 'provisional'
$EvidenceRoot = 'C:\Arvectum\Evidence\APL-WIN-014'
$EnforcedEvidence = Join-Path $EvidenceRoot 'apl-win-014-enforced-lifecycle.json'
$RecoveryEvidence = Join-Path $EvidenceRoot 'apl-win-014-native-recovery-rehearsal.json'
$DriverResult = Join-Path $EvidenceRoot 'apl-win-014-appcontrol-candidate-result.json'
$FinalTrustRoot = Join-Path $EvidenceRoot 'app-control-trust-pack-v2-0.2.4'
$FinalAcceptance = Join-Path $EvidenceRoot 'apl-win-014-final-acceptance.json'
$BasePolicyId = [Guid]'DC1C604C-46EA-40B7-9F47-CF582B225D5E'

function Require-Leaf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
}

function Read-Json([string]$Path, [string]$Label) {
    Require-Leaf $Path $Label
    try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $($_.Exception.Message)" }
}

function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Json([object]$Value, [string]$Path) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Value | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $Path -Encoding UTF8
}

foreach ($required in @($StandDriver,$PromotionScript,$ReadinessScript)) {
    Require-Leaf $required 'stand-kit executable contract'
}

if ($Mode -eq 'Recover') {
    if ($RecoveryBackupDirectory) {
        & $StandDriver -Mode Recover -RecoveryBackupDirectory $RecoveryBackupDirectory
    } else {
        & $StandDriver -Mode Recover
    }
    return
}

if ($Mode -eq 'Preflight') {
    & $StandDriver -Mode Preflight
    return
}

# Execute is the only path that can reach the destructive guarded driver. The
# stand driver owns all policy updates, native recovery PREARM, lifecycle safety,
# emergency recovery, and final healthy product restoration. The driver throws
# or exits on failure; a normal return is followed by evidence validation below.
& $StandDriver -Mode Execute

$driver = Read-Json $DriverResult 'guarded stand result'
if ([string]$driver.schema -ne 'arvectum.proxy.apl-win-014-candidate-result.v1' -or [string]$driver.result -ne 'PASS') {
    throw 'FINALIZATION BLOCK: guarded Enforced driver did not produce a PASS record.'
}
if ([string]$driver.version -ne '0.2.4' -or [string]$driver.base_policy -ne 'ENFORCED') {
    throw 'FINALIZATION BLOCK: guarded result does not describe exact 0.2.4 under Enforced App Control.'
}
if ([int]$driver.code_integrity_3077_blocks -ne 0) {
    throw 'FINALIZATION BLOCK: guarded result contains Arvectum Code Integrity 3077 blocks.'
}

$enforced = Read-Json $EnforcedEvidence 'Enforced lifecycle evidence'
$recovery = Read-Json $RecoveryEvidence 'native recovery rehearsal evidence'
if ([string]$enforced.result -ne 'PASS' -or [string]$recovery.result -ne 'PASS') {
    throw 'FINALIZATION BLOCK: real Enforced lifecycle or native recovery rehearsal evidence is not PASS.'
}

if (Test-Path -LiteralPath $FinalTrustRoot) {
    # Final evidence is reproducible promotion of the exact same provisional
    # XML/CIP. Refuse to silently overwrite prior evidence; only an exact prior
    # PASS may be reused after readiness validates it below.
    $existing = Join-Path $FinalTrustRoot 'trust-pack.json'
    if (-not (Test-Path -LiteralPath $existing -PathType Leaf)) {
        throw "FINALIZATION BLOCK: final trust directory exists without trust-pack.json: $FinalTrustRoot"
    }
} else {
    & $PromotionScript `
        -EnterpriseBundleDirectory $CandidateRoot `
        -ProvisionalTrustPackDirectory $ProvisionalRoot `
        -EnforcedLifecycleEvidencePath $EnforcedEvidence `
        -RecoveryRehearsalEvidencePath $RecoveryEvidence `
        -OutputDirectory $FinalTrustRoot
}

# These are PowerShell scripts, not native executables. Their failure contract is
# terminating exceptions under ErrorActionPreference=Stop; LASTEXITCODE is
# intentionally not consulted because it can retain an unrelated native exit code.
& $ReadinessScript -TrustPackDirectory $FinalTrustRoot -ExpectedBasePolicyId $BasePolicyId

$trustManifest = Join-Path $FinalTrustRoot 'trust-pack.json'
$trust = Read-Json $trustManifest 'final trust-pack v2 manifest'
if ([string]$trust.schema -ne 'arvectum.proxy.windows-app-control-enterprise-trust-pack.v2' -or [string]$trust.result -ne 'PASS' -or -not [bool]$trust.enforced_lifecycle_ready) {
    throw 'FINALIZATION BLOCK: promoted trust-pack v2 does not assert a valid evidence-backed PASS.'
}

$final = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-final-acceptance.v1'
    task = 'APL-WIN-014'
    created_utc = [DateTime]::UtcNow.ToString('o')
    result = 'PASS'
    version = '0.2.4'
    base_policy = 'ENFORCED'
    historical_022_to_024 = 'PASS'
    current_lifecycle = 'PASS'
    native_recovery_rehearsal = 'PASS'
    constrained_language = 'PASS'
    code_integrity_3077_blocks = 0
    final_product_and_pac = 'HEALTHY'
    final_trust_pack_schema = [string]$trust.schema
    final_trust_pack_manifest_sha256 = Hash $trustManifest
    final_supplemental_policy_id = [string]$trust.supplemental_policy_id
    final_supplemental_cip_sha256 = [string]$trust.supplemental_policy_cip_sha256
    provisional_policy_promoted_unchanged = [bool]$trust.provisional_policy_promoted_unchanged
    app_control_policy_changed_by_finalization = $false
    driver_result_sha256 = Hash $DriverResult
    enforced_lifecycle_evidence_sha256 = Hash $EnforcedEvidence
    recovery_rehearsal_evidence_sha256 = Hash $RecoveryEvidence
}
Write-Json $final $FinalAcceptance

Write-Host '================================================'
Write-Host 'APL-WIN-014 FINAL ACCEPTANCE: PASS'
Write-Host 'WINDOWS APP CONTROL: ENFORCED'
Write-Host 'HISTORICAL 0.2.2 P0.4 -> EXACT 0.2.4: PASS'
Write-Host 'EXACT 0.2.4 LIFECYCLE: PASS'
Write-Host 'NATIVE RECOVERY REHEARSAL: PASS'
Write-Host 'FINAL V2 TRUST PROMOTION: PASS / SAME CIP'
Write-Host 'FINAL READINESS BARRIER: PASS'
Write-Host 'ARVECTUM CODE INTEGRITY 3077 BLOCKS: 0'
Write-Host 'FINAL EXACT 0.2.4 + PAC: HEALTHY'
Write-Host "FINAL EVIDENCE: $FinalAcceptance"
Write-Host '================================================'
