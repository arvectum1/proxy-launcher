<# Read-only capture of the sealed V10.6.4 candidate installation for V10.7 authoring. #>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot = '', [string]$BootstrapPolicyId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Join-Path $env:USERPROFILE 'Documents\ArvectumProxyLauncher' }
if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { throw "Installation directory not found: $InstallRoot" }
if ([string]::IsNullOrWhiteSpace($BootstrapPolicyId)) { throw 'BootstrapPolicyId is required; this script never prompts.' }
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
$basePolicyIdText = $seal.base_policy_id
$friendlyName = $seal.bootstrap_policy_friendly_name
if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
$policies = (& CiTool.exe -lp -json 2>$null | ConvertFrom-Json)
$base = @($policies.Policies | Where-Object { $_.PolicyID -eq $basePolicyIdText -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq 'Arvectum APL-WIN-014 Lab Base' -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
$bootstrap = @($policies.Policies | Where-Object { $_.PolicyID -eq $BootstrapPolicyId -and $_.BasePolicyID -eq $basePolicyIdText -and $_.FriendlyName -eq $friendlyName -and $_.IsOnDisk -eq $true -and $_.IsEnforced -eq $true -and $_.IsAuthorized -eq $true })
if ($policies.OperationResult -ne 0 -or $base.Count -ne 1 -or @($base[0].PolicyOptions | Where-Object { $_ -eq 'Enabled:Allow Supplemental Policies' }).Count -ne 1) { throw 'Canonical Lab Base validation failed closed.' }
if ($bootstrap.Count -ne 1) { throw 'The exact V10.6.4 BootstrapPolicyId is not uniquely active, enforced, and authorized.' }
$app = Join-Path $InstallRoot $seal.files.application.filename
$repair = Join-Path $InstallRoot $seal.repair_cache_filename
foreach ($entry in @($seal.files.application, $seal.files.build_manifest, $seal.files.upgrade_helper, $seal.files.uninstall_helper)) {
    $path = Join-Path $InstallRoot $entry.filename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installed sealed file is missing: $($entry.filename)" }
    if ((Get-Sha256 $path) -ine $entry.sha256) { throw "Installed sealed file hash does not match the V10.6.4 seal: $($entry.filename)" }
}
if (-not (Test-Path -LiteralPath $repair -PathType Leaf)) { throw "Mandatory cached repair setup is missing: $($seal.repair_cache_filename)" }
if ((Get-Sha256 $repair) -ine $seal.files.setup.sha256) { throw 'Mandatory cached repair setup hash does not match the V10.6.4 seal.' }
$outDir = Join-Path $scriptDir ("v10.6.4-reference-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$files = @()
Get-ChildItem -LiteralPath $InstallRoot -File -Recurse -Force | Sort-Object FullName | ForEach-Object { $relativePath = $_.FullName -replace ('^' + ($InstallRoot -replace '([\\(){}+.|^$])','\$1') + '\\?'), ''; $files += [ordered]@{ relative_path=$relativePath; sha256=(Get-Sha256 $_.FullName); size=$_.Length; is_pe=($_.Extension -in @('.exe','.dll','.sys','.ocx')) } }
$sealedInstallFiles = @()
foreach ($entry in @($seal.files.application, $seal.files.build_manifest, $seal.files.upgrade_helper, $seal.files.uninstall_helper)) { $sealedInstallFiles += [ordered]@{ filename=$entry.filename; sha256=$entry.sha256 } }
$evidence = [ordered]@{ schema='arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v3'; task=$seal.task; captured_utc=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'); capture_mode='READ-ONLY'; candidate_version=$seal.candidate_version; candidate_source_commit=$seal.candidate_source_commit; candidate_artifact_id=$seal.candidate_artifact_id; candidate_artifact_name=$seal.candidate_artifact_name; base_policy_id=$basePolicyIdText; base_policy_friendly_name=$base[0].FriendlyName; base_policy_options=@($base[0].PolicyOptions); bootstrap_policy_id=$BootstrapPolicyId; bootstrap_policy_friendly_name=$friendlyName; bootstrap_policy_version=$bootstrap[0].Version; mandatory_repair_cache=[ordered]@{ filename=$seal.repair_cache_filename; sha256=$seal.files.setup.sha256; size=(Get-Item -LiteralPath $repair).Length }; sealed_install_files=$sealedInstallFiles; install_root=$InstallRoot; files=$files }
$capturePath = Join-Path $outDir 'reference-capture.json'
$evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $capturePath -Encoding UTF8
"$(Get-Sha256 $capturePath)  reference-capture.json" | Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "REFERENCE CAPTURE COMPLETE: $outDir"
