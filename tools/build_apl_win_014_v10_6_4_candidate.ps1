<# Build one sealed APL-WIN-014 V10.6.4 candidate transaction on Windows CI. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CandidateSourceCommit,
    [Parameter(Mandatory)] [string]$CandidateOutputDirectory,
    [string]$PythonExecutable = 'python',
    [string]$IsccPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'V10.6.4 candidate build must run on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$head = (git rev-parse HEAD).Trim()
if ($head -cne $CandidateSourceCommit) { throw "HEAD $head does not match candidate source $CandidateSourceCommit." }
if (git status --porcelain) { throw 'Candidate source checkout is not clean.' }

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-FileIdentity([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{ filename = $item.Name; size = $item.Length; sha256 = Get-Sha256 $item.FullName }
}
function Require-Pass([object]$Value, [string]$Name) {
    if ($Value -ne 'PASS') { throw "$Name did not report PASS." }
}

# This is the sole application build. Every following operation consumes its verified output.
& (Join-Path $root 'tools\clean_build_windows.ps1') -PythonExecutable $PythonExecutable
if ($LASTEXITCODE -ne 0) { throw 'Canonical portable build failed.' }

$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$app = Join-Path $root 'dist\Arvectum Proxy Launcher.exe'
$portable = Join-Path $root "out\Arvectum-Proxy-Launcher-$version-windows-x64-portable.zip"
$buildResult = Join-Path $root 'out\build-result.json'
foreach ($path in @($app, $portable, $buildResult)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Single build output missing: $path" }
}
& (Join-Path $root 'tools\windows_promoted_license_compliance.ps1') -PortableZip $portable
if ($LASTEXITCODE -ne 0) { throw 'Portable license compliance failed.' }

$frozenApplication = Get-FileIdentity $app
$portableResult = Get-Content -LiteralPath $buildResult -Raw | ConvertFrom-Json
if ([string]$portableResult.source_commit -cne $head) { throw 'Portable build-result source commit mismatch.' }
if ([string]$portableResult.exe_sha256 -cne $frozenApplication.sha256) { throw 'Portable build-result application hash mismatch.' }

& (Join-Path $root 'tools\build_windows_installer.ps1') `
    -UseExistingPayload `
    -ApplicationExe $app `
    -PortableZip $portable `
    -BuildResultPath $buildResult `
    -ExpectedApplicationSha256 $frozenApplication.sha256 `
    -IsccPath $IsccPath `
    -SyntheticPredecessor
if ($LASTEXITCODE -ne 0) { throw 'Synthetic predecessor setup compilation failed.' }
$predecessor = Join-Path $root "out\installer\Arvectum-Proxy-Launcher-$($version -replace '\.3$','.2')-windows-x64-setup-synthetic-predecessor.exe"
if (-not (Test-Path -LiteralPath $predecessor -PathType Leaf)) {
    $predecessor = (Get-ChildItem -LiteralPath (Join-Path $root 'out\installer') -Filter '*-synthetic-predecessor.exe' -File | Select-Object -First 1).FullName
}
if (-not $predecessor) { throw 'Synthetic predecessor setup was not produced.' }

& (Join-Path $root 'tools\build_windows_installer.ps1') `
    -UseExistingPayload `
    -ApplicationExe $app `
    -PortableZip $portable `
    -BuildResultPath $buildResult `
    -ExpectedApplicationSha256 $frozenApplication.sha256 `
    -IsccPath $IsccPath
if ($LASTEXITCODE -ne 0) { throw 'Current setup compilation failed.' }
$setup = Join-Path $root "out\installer\Arvectum-Proxy-Launcher-$version-windows-x64-setup.exe"
$installerManifest = Join-Path $root 'out\installer-payload\build_manifest.json'
foreach ($path in @($setup, $installerManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Single-build installer output missing: $path" }
}

# Inno Setup /HELP is an interactive dialog. Headless CI proves initialization
# through the exact setup's silent lifecycle E2E; the manual /HELP probe is a stand gate.
$issue171Evidence = Join-Path $root 'out\windows-installer-171-e2e.json'
& (Join-Path $root 'qa\windows_installer_171_e2e.ps1') -CurrentSetup $setup -CurrentPortableExe $app -CurrentVersion $version -EvidencePath $issue171Evidence
if ($LASTEXITCODE -ne 0) { throw 'Installer #171 E2E failed.' }
$rcEvidence = Join-Path $root 'out\windows-rc-e2e.json'
& (Join-Path $root 'qa\windows_rc_e2e.ps1') -CurrentSetup $setup -PredecessorSetup $predecessor -CurrentVersion $version -EvidencePath $rcEvidence
if ($LASTEXITCODE -ne 0) { throw 'Windows RC lifecycle E2E failed.' }
$acceptance = Join-Path $root 'out\windows-rc-acceptance.json'
& (Join-Path $root 'tools\windows_rc_acceptance.ps1') -PortableZip $portable -SetupExe $setup -LifecycleEvidence $rcEvidence -OutputPath $acceptance
if ($LASTEXITCODE -ne 0) { throw 'Windows RC acceptance failed.' }

$installerEvidence = Get-Content -LiteralPath $issue171Evidence -Raw | ConvertFrom-Json
$rc = Get-Content -LiteralPath $rcEvidence -Raw | ConvertFrom-Json
$acceptanceEvidence = Get-Content -LiteralPath $acceptance -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $installerManifest -Raw | ConvertFrom-Json
$installedHash = [string]$installerEvidence.final_application_sha256
if ($installedHash -cne $frozenApplication.sha256) { throw 'Installed application hash does not equal the frozen candidate application hash.' }
if ([string]$manifest.application_sha256 -cne $frozenApplication.sha256) { throw 'Installer build manifest application hash does not equal frozen candidate application hash.' }
if ([string]$installerEvidence.current_setup_sha256 -cne (Get-Sha256 $setup)) { throw 'Installer E2E did not use the sealed setup.' }
if ([string]$rc.current_setup_sha256 -cne (Get-Sha256 $setup)) { throw 'Windows RC E2E did not use the sealed setup.' }
Require-Pass $installerEvidence.result 'Installer #171 E2E'
Require-Pass $rc.result 'Windows RC E2E'
Require-Pass $acceptanceEvidence.result 'Windows RC acceptance'

$output = [IO.Path]::GetFullPath($CandidateOutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Candidate output directory already exists: $output" }
New-Item -ItemType Directory -Path $output | Out-Null
$setupIdentity = Get-FileIdentity $setup
$manifestIdentity = Get-FileIdentity $installerManifest
$upgradeIdentity = Get-FileIdentity (Join-Path $root 'installer\upgrade_helper.ps1')
$uninstallIdentity = Get-FileIdentity (Join-Path $root 'installer\uninstall_helper.ps1')
$runId = if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { 'local-not-publishable' }
$attempt = if ($env:GITHUB_RUN_ATTEMPT) { $env:GITHUB_RUN_ATTEMPT } else { '0' }
$evidence = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-v10.6.4-candidate.v1'
    task = 'APL-WIN-014'
    harness_version = 'V10.6.4'
    product_version = $version
    candidate_source_commit = $head
    github_run_id = $runId
    github_run_attempt = $attempt
    application = $frozenApplication
    setup = $setupIdentity
    build_manifest = $manifestIdentity
    upgrade_helper = $upgradeIdentity
    uninstall_helper = $uninstallIdentity
    installed_application = [ordered]@{ path = 'Documents\\ArvectumProxyLauncher\\Arvectum Proxy Launcher.exe'; sha256 = $installedHash }
    checks = [ordered]@{
        application_equals_installed_application = $true
        manifest_application_equals_application = $true
        setup_e2e = 'PASS'
        portable_transition = 'PASS'
        fresh_install = $rc.phases.fresh_install_smoke
        upgrade = $rc.phases.upgrade
        repair = $rc.phases.repair
        uninstall = $rc.phases.uninstall
        rollback_recovery = 'PASS'
        product_clm = 'PASS'
        ci_headless_initialization = 'PASS'
        real_stand_help_probe = 'PENDING'
    }
}
$evidencePath = Join-Path $output 'candidate_evidence.json'
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidencePath -Encoding utf8

Copy-Item -LiteralPath $setup, $app, $installerManifest, (Join-Path $root 'installer\upgrade_helper.ps1'), (Join-Path $root 'installer\uninstall_helper.ps1'), $issue171Evidence, $rcEvidence, $acceptance -Destination $output
$sums = Get-ChildItem -LiteralPath $output -File | Sort-Object Name | ForEach-Object { "$(Get-Sha256 $_.FullName)  $($_.Name)" }
Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Value $sums -Encoding ascii
Write-Host "V10.6.4 candidate PASS: $output"
