<# Canonical APL-REL-006 / APL-WIN-010..012 installer build. Requires exact Inno Setup 6.7.1. #>
[CmdletBinding()]
param(
    [string]$PythonExecutable = 'python',
    [string]$IsccPath,
    [switch]$SyntheticPredecessor,
    [switch]$UseExistingPayload,
    [string]$ApplicationExe,
    [string]$PortableZip,
    [string]$BuildResultPath,
    [string]$ExpectedApplicationSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows installer build must run on Windows.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root

function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$canonicalVersion = (Get-Content VERSION -Raw).Trim()
$semver = [regex]::Match($canonicalVersion, '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
if (-not $semver.Success) { throw "Invalid canonical VERSION: $canonicalVersion" }

$version = $canonicalVersion
$synthetic = $false
if ($SyntheticPredecessor) {
    if ($canonicalVersion -match '[-+]') { throw 'Synthetic predecessor generation requires a stable numeric canonical VERSION.' }
    $major = [int]$semver.Groups['major'].Value
    $minor = [int]$semver.Groups['minor'].Value
    $patch = [int]$semver.Groups['patch'].Value
    if ($patch -gt 0) {
        $version = "$major.$minor.$($patch - 1)"
    } elseif ($minor -gt 0) {
        $version = "$major.$($minor - 1).0"
    } else {
        throw "Cannot derive a synthetic predecessor for $canonicalVersion"
    }
    $synthetic = $true
}

$versionCore = ($version -split '[-+]')[0]
$versionInfoVersion = "$versionCore.0"
$exe = Join-Path $root 'dist\Arvectum Proxy Launcher.exe'
$portableZip = Join-Path $root "out\Arvectum-Proxy-Launcher-$canonicalVersion-windows-x64-portable.zip"

if ($UseExistingPayload) {
    foreach ($input in @($ApplicationExe, $PortableZip, $BuildResultPath)) {
        if ([string]::IsNullOrWhiteSpace($input)) { throw 'UseExistingPayload requires -ApplicationExe, -PortableZip, and -BuildResultPath.' }
        if (-not (Test-Path -LiteralPath $input -PathType Leaf)) { throw "UseExistingPayload input does not exist: $input" }
    }
    $exe = (Resolve-Path -LiteralPath $ApplicationExe).Path
    $portableZip = (Resolve-Path -LiteralPath $PortableZip).Path
    $buildResult = Get-Content -LiteralPath $BuildResultPath -Raw | ConvertFrom-Json
    if ([string]$buildResult.version -cne $canonicalVersion) { throw 'UseExistingPayload build-result version does not match VERSION.' }
    if ([string]$buildResult.format -cne 'portable') { throw 'UseExistingPayload build-result format must be portable.' }
    if ([string]$buildResult.source_commit -cne (git rev-parse HEAD).Trim()) { throw 'UseExistingPayload build-result source_commit does not match HEAD.' }
    if ((Hash $portableZip) -cne ([string]$buildResult.zip_sha256).ToLowerInvariant()) { throw 'UseExistingPayload portable ZIP hash does not match build-result.json.' }
    if ((Hash $exe) -cne ([string]$buildResult.exe_sha256).ToLowerInvariant()) { throw 'UseExistingPayload application hash does not match build-result.json.' }
    if ($ExpectedApplicationSha256 -and (Hash $exe) -cne $ExpectedApplicationSha256.ToLowerInvariant()) { throw 'UseExistingPayload application hash does not match -ExpectedApplicationSha256.' }
} elseif (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $portableZip)) {
    & (Join-Path $root 'tools\clean_build_windows.ps1') -PythonExecutable $PythonExecutable
    if ($LASTEXITCODE) { throw 'portable build failed' }
    & (Join-Path $root 'tools\windows_promoted_license_compliance.ps1') -PortableZip $portableZip
    if ($LASTEXITCODE) { throw 'APL-IP-004 portable license compliance failed' }
}
if (-not (Test-Path -LiteralPath $exe)) { throw 'dist\\Arvectum Proxy Launcher.exe is required' }
if (-not (Test-Path -LiteralPath $portableZip)) { throw 'APL-IP-004 compliant portable ZIP is required' }

$payload = Join-Path $root 'out\installer-payload'
Remove-Item -LiteralPath $payload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $payload 'Arvectum Proxy Launcher.exe')
Copy-Item -LiteralPath (Join-Path $root 'installer\upgrade_helper.ps1') -Destination $payload
Copy-Item -LiteralPath (Join-Path $root 'installer\uninstall_helper.ps1') -Destination $payload
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $payload 'LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $root 'THIRD_PARTY_NOTICES.txt') -Destination (Join-Path $payload 'THIRD_PARTY_NOTICES.txt')

$licenseExtract = Join-Path $root 'out\installer-license-source'
Remove-Item -LiteralPath $licenseExtract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $portableZip -DestinationPath $licenseExtract -Force
$portableExe = Join-Path $licenseExtract 'Arvectum Proxy Launcher.exe'
if (-not (Test-Path -LiteralPath $portableExe -PathType Leaf)) { throw 'Portable ZIP does not contain Arvectum Proxy Launcher.exe.' }
if ((Hash $portableExe) -cne (Hash $exe)) { throw 'Portable ZIP application bytes do not match the installer payload application.' }
if ($UseExistingPayload) {
    $portableSums = Join-Path $licenseExtract 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $portableSums -PathType Leaf)) { throw 'UseExistingPayload portable ZIP has no SHA256SUMS.txt.' }
    $sumMatch = Select-String -LiteralPath $portableSums -Pattern '^[0-9A-Fa-f]{64}\s+Arvectum Proxy Launcher\.exe$'
    if (@($sumMatch).Count -ne 1) { throw 'UseExistingPayload portable ZIP checksum manifest is ambiguous.' }
    $sumHash = ($sumMatch[0].Line -split '\s+')[0]
    if ($sumHash.ToLowerInvariant() -cne (Hash $exe)) { throw 'UseExistingPayload portable ZIP checksum does not match the installer payload application.' }
}
$portableBundle = Join-Path $licenseExtract 'THIRD_PARTY_LICENSES'
if (-not (Test-Path -LiteralPath (Join-Path $portableBundle 'manifest.json'))) {
    throw 'APL-IP-004: portable ZIP does not contain a verified third-party license bundle.'
}
Copy-Item -LiteralPath $portableBundle -Destination (Join-Path $payload 'THIRD_PARTY_LICENSES') -Recurse
$bundlePython = Join-Path $root '.build-venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $bundlePython)) { throw 'APL-IP-004: canonical build Python is unavailable for installer bundle verification.' }
& $bundlePython (Join-Path $root 'tools\third_party_license_bundle.py') --verify --output (Join-Path $payload 'THIRD_PARTY_LICENSES')
if ($LASTEXITCODE -ne 0) { throw 'APL-IP-004: installer third-party license bundle verification failed.' }
Remove-Item -LiteralPath $licenseExtract -Recurse -Force

function NormalizedVersionInfoValue($Value) {
    # Inno Setup may space-pad string-table fields in the PE resource. Windows
    # Explorer presents the same logical value without that padding, so compare
    # the semantic value while still requiring exact text/case after trimming.
    return ([string]$Value).Trim()
}

if (-not $IsccPath) {
    $IsccPath = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}
if (-not $IsccPath) { throw 'Inno Setup 6.7.1 ISCC.exe was not found.' }
if (-not (Test-Path -LiteralPath $IsccPath)) { throw "ISCC.exe path does not exist: $IsccPath" }

# ISCC.exe itself carries a 0.0.0 PE file version in official 6.7.1 builds, so
# Windows VersionInfo is not a trustworthy compiler-version probe. The canonical
# .iss file instead checks Inno Setup's own predefined ISPP Ver/PREPROCVER value:
# 0x06070100 == 6.7.1.0. Compilation therefore fails closed on any other version.
$requiredInnoSetupVersion = '6.7.1'
$isccHash = Hash $IsccPath

$manifest = [ordered]@{
    product='Arvectum Proxy Launcher'
    company='ООО «Арвектум»'
    version=$version
    canonical_version=$canonicalVersion
    synthetic_lifecycle_fixture=$synthetic
    platform='windows-x64'
    format='setup'
    source_commit=(git rev-parse HEAD).Trim()
    application_sha256=(Hash (Join-Path $payload 'Arvectum Proxy Launcher.exe'))
    upgrade_helper_sha256=(Hash (Join-Path $payload 'upgrade_helper.ps1'))
    uninstall_helper_sha256=(Hash (Join-Path $payload 'uninstall_helper.ps1'))
    third_party_license_manifest_sha256=(Hash (Join-Path $payload 'THIRD_PARTY_LICENSES\manifest.json'))
    inno_setup_version=$requiredInnoSetupVersion
    inno_setup_version_verification='compiler-preprocessor-ver-0x06070100'
    iscc_sha256=$isccHash
}
$payloadManifestPath = Join-Path $payload 'build_manifest.json'
$manifest | ConvertTo-Json | Set-Content -LiteralPath $payloadManifestPath -Encoding utf8
Write-Host "Selected ISCC.exe SHA256=$isccHash; exact Inno Setup $requiredInnoSetupVersion is enforced by the compiler preprocessor contract."

$isccArgs = @(
    "/DAppVersion=$version",
    "/DVersionInfoVersion=$versionInfoVersion",
    "/DPayloadDir=$payload"
)
if ($SyntheticPredecessor) { $isccArgs += '/DSyntheticLifecycleFixture=1' }
$isccArgs += 'installer\ArvectumProxyLauncher.iss'
& $IsccPath @isccArgs
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed (exact 6.7.1 compiler contract not satisfied or script compilation failed).' }
Write-Host "Inno Setup $requiredInnoSetupVersion compiler contract PASS."

$suffix = if ($SyntheticPredecessor) { '-synthetic-predecessor' } else { '' }
$setup = Join-Path $root "out\installer\Arvectum-Proxy-Launcher-$version-windows-x64-setup$suffix.exe"
if (-not (Test-Path -LiteralPath $setup)) { throw "Expected setup EXE was not produced: $setup" }
$setupHash = Hash $setup

$setupInfo = (Get-Item -LiteralPath $setup).VersionInfo
$actualCompany = NormalizedVersionInfoValue $setupInfo.CompanyName
$actualProduct = NormalizedVersionInfoValue $setupInfo.ProductName
$actualDescription = NormalizedVersionInfoValue $setupInfo.FileDescription
$actualFileVersion = NormalizedVersionInfoValue $setupInfo.FileVersion
if ($actualCompany -cne 'ООО «Арвектум»') { throw "Setup CompanyName mismatch: '$actualCompany'" }
if ($actualProduct -cne 'Arvectum Proxy Launcher') { throw "Setup ProductName mismatch: '$actualProduct'" }
if ($actualDescription -cne 'Arvectum Proxy Launcher Windows Installer') { throw "Setup FileDescription mismatch: '$actualDescription'" }
if ($actualFileVersion -cne $versionInfoVersion) { throw "Setup FileVersion mismatch: '$actualFileVersion' != '$versionInfoVersion'" }

if ($env:GITHUB_OUTPUT) {
    if ($SyntheticPredecessor) {
        "predecessor_setup_path=$setup" >> $env:GITHUB_OUTPUT
        "predecessor_version=$version" >> $env:GITHUB_OUTPUT
    } else {
        "setup_path=$setup" >> $env:GITHUB_OUTPUT
        "setup_name=$(Split-Path $setup -Leaf)" >> $env:GITHUB_OUTPUT
        "setup_sha256=$setupHash" >> $env:GITHUB_OUTPUT
        "build_manifest_path=$payloadManifestPath" >> $env:GITHUB_OUTPUT
    }
}
Write-Host "Installer build PASS: $setup SHA256=$setupHash synthetic=$synthetic"
