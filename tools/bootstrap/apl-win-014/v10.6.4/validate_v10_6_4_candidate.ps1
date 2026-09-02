<# Validates only the immutable V10.6.4 candidate payload; it never builds or deploys. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CandidateRoot,
    [Parameter(Mandatory)] [string]$ObservedRunId,
    [Parameter(Mandatory)] [string]$ObservedRunAttempt,
    [Parameter(Mandatory)] [string]$ObservedArtifactId,
    [Parameter(Mandatory)] [string]$ObservedArtifactName,
    [Parameter(Mandatory)] [string]$ObservedArtifactDigest,
    [Parameter(Mandatory)] [string]$ObservedSourceCommit,
    [string]$ExpectedHashesPath = (Join-Path $PSScriptRoot 'expected_hashes.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Require-Equal([string]$Actual, [string]$Expected, [string]$Name) {
    if ($Actual -cne $Expected) { throw "$Name mismatch: expected $Expected, got $Actual" }
}
function Require-Pass([object]$Value, [string]$Name) {
    if ($Value -ne 'PASS') { throw "$Name did not report PASS." }
}

$CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path
$expected = Get-Content -LiteralPath $ExpectedHashesPath -Raw | ConvertFrom-Json
# Outer GitHub artifact identity is independent from the nested candidate files.
Require-Equal $ObservedRunId ([string]$expected.candidate_run_id) 'observed GitHub run ID'
Require-Equal $ObservedRunAttempt ([string]$expected.candidate_run_attempt) 'observed GitHub run attempt'
Require-Equal $ObservedArtifactId ([string]$expected.candidate_artifact_id) 'observed GitHub artifact ID'
Require-Equal $ObservedArtifactName ([string]$expected.candidate_artifact_name) 'observed GitHub artifact name'
Require-Equal $ObservedArtifactDigest ([string]$expected.candidate_artifact_digest) 'observed GitHub artifact digest'
Require-Equal $ObservedSourceCommit ([string]$expected.candidate_source_commit) 'observed GitHub source commit'
foreach ($property in @('setup','application','build_manifest','upgrade_helper','uninstall_helper','candidate_evidence')) {
    $record = $expected.files.$property
    $path = Join-Path $CandidateRoot $record.filename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing sealed candidate file: $($record.filename)" }
    $sizeProperty = $record.PSObject.Properties['size']
    if ($null -ne $sizeProperty -and (Get-Item -LiteralPath $path).Length -ne [long]$sizeProperty.Value) { throw "Size mismatch for $($record.filename)" }
    Require-Equal (Get-Sha256 $path) ([string]$record.sha256) $record.filename
}

$sums = Join-Path $CandidateRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $sums -PathType Leaf)) { throw 'Candidate SHA256SUMS.txt is missing.' }
$sumFiles = @{}
foreach ($line in Get-Content -LiteralPath $sums) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Malformed candidate checksum record: $line" }
    if ($sumFiles.ContainsKey($matches[2])) { throw "Duplicate candidate checksum record: $($matches[2])" }
    $sumFiles[$matches[2]] = $matches[1]
}
foreach ($name in $sumFiles.Keys) {
    $path = Join-Path $CandidateRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "SHA256SUMS references missing file: $name" }
    Require-Equal (Get-Sha256 $path) $sumFiles[$name] "SHA256SUMS $name"
}

$evidence = Get-Content -LiteralPath (Join-Path $CandidateRoot $expected.files.candidate_evidence.filename) -Raw | ConvertFrom-Json
Require-Equal ([string]$evidence.schema) 'arvectum.proxy.apl-win-014-v10.6.4-candidate.v1' 'candidate evidence schema'
Require-Equal ([string]$evidence.task) 'APL-WIN-014' 'candidate evidence task'
Require-Equal ([string]$evidence.harness_version) 'V10.6.4' 'candidate evidence harness'
Require-Equal ([string]$evidence.product_version) ([string]$expected.candidate_version) 'candidate evidence product version'
Require-Equal ([string]$evidence.candidate_source_commit) ([string]$expected.candidate_source_commit) 'candidate evidence source commit'
Require-Equal ([string]$evidence.github_run_id) ([string]$expected.candidate_run_id) 'candidate evidence run ID'
Require-Equal ([string]$evidence.github_run_attempt) ([string]$expected.candidate_run_attempt) 'candidate evidence run attempt'
if ($evidence.checks.application_equals_installed_application -ne $true) { throw 'Candidate installed application identity is not true.' }
if ($evidence.checks.manifest_application_equals_application -ne $true) { throw 'Candidate manifest application identity is not true.' }
foreach ($check in @('setup_e2e','portable_transition','fresh_install','upgrade','repair','uninstall','rollback_recovery','product_clm','ci_headless_initialization')) { Require-Pass $evidence.checks.$check "candidate $check" }
Require-Equal ([string]$evidence.checks.real_stand_help_probe) 'PENDING' 'real-stand help probe'
Require-Equal ([string]$evidence.application.sha256) ([string]$expected.files.application.sha256) 'candidate evidence application hash'
Require-Equal ([string]$evidence.setup.sha256) ([string]$expected.files.setup.sha256) 'candidate evidence setup hash'
Require-Equal ([string]$evidence.installed_application.sha256) ([string]$expected.files.application.sha256) 'candidate installed application hash'

$manifest = Get-Content -LiteralPath (Join-Path $CandidateRoot $expected.files.build_manifest.filename) -Raw | ConvertFrom-Json
foreach ($pair in @(
    @('version',$expected.candidate_version), @('canonical_version',$expected.candidate_version), @('source_commit',$expected.candidate_source_commit),
    @('application_sha256',$expected.files.application.sha256), @('upgrade_helper_sha256',$expected.files.upgrade_helper.sha256),
    @('uninstall_helper_sha256',$expected.files.uninstall_helper.sha256), @('inno_setup_version','6.7.1')
)) { Require-Equal ([string]$manifest.($pair[0])) ([string]$pair[1]) "build manifest $($pair[0])" }

[ordered]@{ result='PASS'; candidate_source_commit=$expected.candidate_source_commit; candidate_run_id=$expected.candidate_run_id; candidate_artifact_id=$expected.candidate_artifact_id } | ConvertTo-Json -Compress
