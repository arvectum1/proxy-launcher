<# Read-only capture of the sealed V10.6.4 candidate installation for V10.7 authoring. #>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot = '', [string]$BootstrapPolicyId = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')
if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Join-Path $env:USERPROFILE 'Documents\ArvectumProxyLauncher' }
if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { throw "Installation directory not found: $InstallRoot" }
if ([string]::IsNullOrWhiteSpace($BootstrapPolicyId)) { throw 'BootstrapPolicyId is required; this script never prompts.' }
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
$basePolicyIdText = $seal.base_policy_id
$friendlyName = $seal.bootstrap_policy_friendly_name
$policyEvi = Get-ClmPolicyEvidence -ExpectedBasePolicyId $basePolicyIdText -ExpectedBootstrapPolicyId $BootstrapPolicyId -ExpectedBootstrapFriendlyName $friendlyName
$basePolicy = $policyEvi.base
$bootstrapPolicy = $policyEvi.bootstrap
Test-ClmBasePolicyInvariant -Policy $basePolicy -ExpectedPolicyId $basePolicyIdText -ExpectedBasePolicyId $basePolicyIdText -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'
if ($bootstrapPolicy.policy_id -ne $BootstrapPolicyId) { throw 'Bootstrap PolicyID does not match expected.' }
if ($bootstrapPolicy.is_on_disk -ne $true -or $bootstrapPolicy.is_enforced -ne $true -or $bootstrapPolicy.is_authorized -ne $true) { throw 'Bootstrap policy is not OnDisk/Enforced/Authorized.' }
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
$files = Get-ClmLiveInventory -InstallRoot $InstallRoot
$unins000 = Get-ClmUninstallerEvidence -InstallRoot $InstallRoot
$processes = Get-ClmProcessEvidence -ProcessName 'Arvectum Proxy Launcher'
$netstatPath = Join-Path $env:SystemRoot 'System32\netstat.exe'
$listenerEvidence = Get-ClmNetstatTcpListeners -NetstatPath $netstatPath -TargetPort 8082
$proxyEnable = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'ProxyEnable'
$proxyServer = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'ProxyServer'
$proxyOverride = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'ProxyOverride'
$autoConfigUrl = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'AutoConfigURL'
$autoDetect = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'AutoDetect'
$wininet = [ordered]@{
    proxy_enable=$proxyEnable
    proxy_server=$proxyServer
    proxy_override=$proxyOverride
    auto_config_url=$autoConfigUrl
    auto_detect=$autoDetect
}
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runLauncher = Get-ClmOptionalRegistryValue -Path $runKeyPath -ValueName 'ArvectumProxyLauncher'
$runRecovery = Get-ClmOptionalRegistryValue -Path $runKeyPath -ValueName 'ArvectumProxyLauncherRecovery'
$runEntries = [ordered]@{
    arvectum_proxy_launcher=$runLauncher
    arvectum_proxy_launcher_recovery=$runRecovery
}
$codeIntegrity = Get-ClmCodeIntegrityEvidence -MaxEvents 10
$sealedInstallFiles = @()
foreach ($entry in @($seal.files.application, $seal.files.build_manifest, $seal.files.upgrade_helper, $seal.files.uninstall_helper)) { $sealedInstallFiles += [ordered]@{ filename=$entry.filename; sha256=$entry.sha256 } }
$evidence = [ordered]@{
    schema='arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v4'
    task=$seal.task
    captured_utc=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    capture_mode='READ-ONLY'
    candidate_version=$seal.candidate_version
    candidate_source_commit=$seal.candidate_source_commit
    candidate_artifact_id=$seal.candidate_artifact_id
    candidate_artifact_name=$seal.candidate_artifact_name
    base_policy_id=$basePolicyIdText
    base_policy_friendly_name=$basePolicy.friendly_name
    base_policy_options=$basePolicy.policy_options
    bootstrap_policy_id=$BootstrapPolicyId
    bootstrap_policy_friendly_name=$friendlyName
    bootstrap_policy_version=$bootstrapPolicy.version
    bootstrap_policy_enforced=$bootstrapPolicy.is_enforced
    bootstrap_policy_authorized=$bootstrapPolicy.is_authorized
    mandatory_repair_cache=[ordered]@{ filename=$seal.repair_cache_filename; sha256=$seal.files.setup.sha256; size=(Get-Item -LiteralPath $repair).Length }
    sealed_install_files=$sealedInstallFiles
    install_root=$InstallRoot
    files=$files
    unins000=$unins000
    processes=$processes
    listeners=$listenerEvidence
    wininet=$wininet
    run_entries=$runEntries
    code_integrity=$codeIntegrity
    policies=$policyEvi
}
$capturePath = Join-Path $outDir 'reference-capture.json'
$evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $capturePath -Encoding UTF8
"$(Get-Sha256 $capturePath)  reference-capture.json" | Set-Content -LiteralPath (Join-Path $outDir 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "REFERENCE CAPTURE COMPLETE: $outDir"
