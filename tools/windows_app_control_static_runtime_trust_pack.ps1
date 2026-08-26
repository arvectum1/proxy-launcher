<#
.SYNOPSIS
    Generate the forward App Control for Business trust pack for a static Windows runtime.
.DESCRIPTION
    APL-WIN-014 post-incident generator for the App-Control-compatible Windows packaging
    model. It accepts only a portable ZIP whose application is a static PyInstaller onedir
    tree under runtime/, verifies every runtime file against RUNTIME_SHA256SUMS.txt, verifies
    the Russian release set before policy generation, optionally includes the complete
    enterprise installer bundle, then emits a non-deployed supplemental exact-hash policy.

    Security invariants:
      * no PyInstaller onefile/_MEI runtime is accepted;
      * every executable runtime byte exists before policy generation;
      * supplemental rule option 3 (Audit Mode) is removed before .cip conversion;
      * the customer base policy ID is preserved as the supplemental relationship;
      * this generator never deploys, removes, or weakens App Control policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,

    [Parameter(Mandatory = $true)]
    [Guid]$BasePolicyId,

    [Parameter(Mandatory = $true)]
    [string]$EnterpriseInstallerBundle,

    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'APL-WIN-014 static-runtime trust-pack generation must run on Windows.'
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required Windows command/cmdlet is unavailable: $Name"
    }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativePath([string]$Root, [string]$Path) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\\') + '\\'
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside expected root: $Path"
    }
    return $pathFull.Substring($rootFull.Length).Replace('\\','/')
}

function Get-TreeRecords([string]$Root) {
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    return @(
        Get-ChildItem -LiteralPath $resolved -File -Recurse -Force |
        ForEach-Object {
            [pscustomobject]@{
                relative_path = Get-RelativePath -Root $resolved -Path $_.FullName
                sha256 = Get-Sha256 $_.FullName
                size = [long]$_.Length
            }
        } |
        Sort-Object relative_path
    )
}

function Read-HashManifest([string]$Path) {
    $records = @{}
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding ascii)) {
        if (-not $line.Trim()) { continue }
        $match = [regex]::Match($line, '^([0-9A-Fa-f]{64})\s{2}(.+)$')
        if (-not $match.Success) { throw "Invalid SHA256 manifest line: $line" }
        $relative = $match.Groups[2].Value.Replace('\\','/')
        if ($relative.StartsWith('/') -or $relative.Contains('../') -or $relative.Contains('/../')) {
            throw "Unsafe runtime manifest path: $relative"
        }
        if ($records.ContainsKey($relative)) { throw "Duplicate runtime manifest path: $relative" }
        $records[$relative] = $match.Groups[1].Value.ToLowerInvariant()
    }
    return $records
}

function Assert-StaticRuntime([string]$PortableRoot) {
    $runtime = Join-Path $PortableRoot 'runtime'
    $manifestPath = Join-Path $PortableRoot 'RUNTIME_SHA256SUMS.txt'
    $launcher = Join-Path $runtime 'Arvectum Proxy Launcher.exe'
    if (-not (Test-Path -LiteralPath $runtime -PathType Container)) {
        throw 'StaticRuntimeHash requires portable runtime/ directory.'
    }
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw 'StaticRuntimeHash requires runtime/Arvectum Proxy Launcher.exe.'
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'StaticRuntimeHash requires RUNTIME_SHA256SUMS.txt.'
    }
    $manifest = Read-HashManifest $manifestPath
    $actual = @(Get-TreeRecords $runtime)
    if ($actual.Count -lt 2) {
        throw 'Static onedir runtime unexpectedly contains fewer than two files.'
    }
    if ($manifest.Count -ne $actual.Count) {
        throw "Runtime manifest file-count mismatch: manifest=$($manifest.Count) actual=$($actual.Count)"
    }
    foreach ($record in $actual) {
        if (-not $manifest.ContainsKey($record.relative_path)) {
            throw "Runtime manifest does not bind file: $($record.relative_path)"
        }
        if ($manifest[$record.relative_path] -cne $record.sha256) {
            throw "Runtime SHA256 mismatch: $($record.relative_path)"
        }
    }
    if (@($actual | Where-Object { $_.relative_path -match '(^|/)_MEI\d*($|/)' }).Count -ne 0) {
        throw 'Static runtime contains a forbidden PyInstaller _MEI extraction tree.'
    }
    return [pscustomobject]@{
        runtime = $runtime
        launcher = $launcher
        records = $actual
        manifest = $manifestPath
    }
}

function Invoke-RussianReleaseVerifier([string]$Verifier, [string]$Directory) {
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Verifier -ReleaseDirectory $Directory | Out-Host
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldEap
    }
    if ($exitCode -ne 0) {
        throw "Russian release verification failed with exit code $exitCode"
    }
}

function Get-PolicyIdFromXml([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, '<PolicyID>\s*([^<]+)\s*</PolicyID>', 'IgnoreCase')
    if (-not $match.Success) { throw 'Generated App Control policy has no PolicyID.' }
    return $match.Groups[1].Value.Trim()
}

foreach ($command in @(
    'New-CIPolicy',
    'Set-CIPolicyIdInfo',
    'Set-CIPolicyVersion',
    'Set-RuleOption',
    'ConvertFrom-CIPolicy'
)) {
    Assert-Command $command
}

$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$EnterpriseInstallerBundle = (Resolve-Path -LiteralPath $EnterpriseInstallerBundle).Path
$verifier = Join-Path $ReleaseDirectory 'verify_russian_release.ps1'
$buildResultPath = Join-Path $ReleaseDirectory 'build-result.json'
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "Russian release verifier is missing: $verifier"
}
if (-not (Test-Path -LiteralPath $buildResultPath -PathType Leaf)) {
    throw "Static runtime build manifest is missing: $buildResultPath"
}

$build = Get-Content -LiteralPath $buildResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$build.version
if ($version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+].*)?$') {
    throw "Invalid build-result version: $version"
}
if ([string]$build.app_control_runtime_model -cne 'static-onedir') {
    throw 'Release build-result does not declare app_control_runtime_model=static-onedir.'
}
$portableName = "Arvectum-Proxy-Launcher-$version-windows-x64-portable.zip"
$portable = Join-Path $ReleaseDirectory $portableName
if (-not (Test-Path -LiteralPath $portable -PathType Leaf)) {
    throw "Static runtime portable ZIP is missing: $portable"
}
if ([string]$build.zip_sha256 -and ([string]$build.zip_sha256).ToLowerInvariant() -cne (Get-Sha256 $portable)) {
    throw 'Portable ZIP SHA256 does not match build-result.json.'
}

Write-Host '=== APL-WIN-014 Russian release verification ==='
Invoke-RussianReleaseVerifier -Verifier $verifier -Directory $ReleaseDirectory

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PWD ("out\app-control-static-runtime-$version")
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Output directory already exists; refusing to overwrite a prior trust pack: $OutputDirectory"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ("ArvectumStaticAppControlPack-" + [guid]::NewGuid().ToString('N'))
$portableExtract = Join-Path $tempRoot 'portable'
$installerExtract = Join-Path $tempRoot 'installer'
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $portableExtract -Force | Out-Null
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null

try {
    Expand-Archive -LiteralPath $portable -DestinationPath $portableExtract -Force
    $static = Assert-StaticRuntime $portableExtract

    $runtimeStage = Join-Path $scanRoot 'runtime'
    Copy-Item -LiteralPath $static.runtime -Destination $runtimeStage -Recurse -Force

    $installerSource = $EnterpriseInstallerBundle
    if (Test-Path -LiteralPath $installerSource -PathType Leaf) {
        if ([IO.Path]::GetExtension($installerSource) -ine '.zip') {
            throw 'EnterpriseInstallerBundle must be a directory or ZIP.'
        }
        New-Item -ItemType Directory -Path $installerExtract -Force | Out-Null
        Expand-Archive -LiteralPath $installerSource -DestinationPath $installerExtract -Force
        $installerSource = $installerExtract
    }
    if (-not (Test-Path -LiteralPath $installerSource -PathType Container)) {
        throw 'Enterprise installer bundle could not be resolved to a directory.'
    }
    $installerRecords = @(Get-TreeRecords $installerSource)
    if ($installerRecords.Count -lt 2) {
        throw 'Enterprise installer bundle must be a multi-file pre-authorizable artifact set.'
    }
    if (@($installerRecords | Where-Object { $_.relative_path -match '(^|/)_MEI\d*($|/)' }).Count -ne 0) {
        throw 'Enterprise installer bundle contains a forbidden _MEI extraction tree.'
    }
    $installerStage = Join-Path $scanRoot 'installer-bundle'
    Copy-Item -LiteralPath $installerSource -Destination $installerStage -Recurse -Force

    $policyXml = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-AppControl-StaticRuntime-Supplemental.xml'
    $policyName = "Arvectum Proxy Launcher $version Static Runtime"

    Write-Host '=== Generating static-runtime exact-hash supplemental policy ==='
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoScript -NoShadowCopy -FilePath $policyXml -Level Hash | Out-Null
    Set-CIPolicyIdInfo -FilePath $policyXml -ResetPolicyID -PolicyName $policyName -SupplementsBasePolicyID $BasePolicyId | Out-Null

    # ConfigCI can carry the template Audit option into a supplemental XML. The
    # customer base policy owns Audit/Enforced state; a supplemental must not.
    Set-RuleOption -FilePath $policyXml -Option 3 -Delete
    $policyText = Get-Content -LiteralPath $policyXml -Raw -Encoding UTF8
    if ($policyText -match 'Enabled:Audit Mode') {
        throw 'Generated supplemental still contains Enabled:Audit Mode after sanitization.'
    }

    $core = ($version -split '[-+]')[0]
    Set-CIPolicyVersion -FilePath $policyXml -Version "$core.0"
    $policyId = Get-PolicyIdFromXml $policyXml
    $policyFileSafe = $policyId.Trim('{}')
    $policyCip = Join-Path $OutputDirectory ("{$policyFileSafe}.cip")
    ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath $policyCip
    if (-not (Test-Path -LiteralPath $policyCip -PathType Leaf)) {
        throw 'ConfigCI did not create the binary supplemental policy.'
    }

    $runtimeRecords = @($static.records | ForEach-Object {
        [ordered]@{ relative_path=$_.relative_path; sha256=$_.sha256; size=[long]$_.size }
    })
    $installerManifestRecords = @($installerRecords | ForEach-Object {
        [ordered]@{ relative_path=$_.relative_path; sha256=$_.sha256; size=[long]$_.size }
    })
    $manifest = [ordered]@{
        schema = 'arvectum.proxy.windows-app-control-static-runtime-trust-pack.v1'
        task = 'APL-WIN-014'
        created_utc = [DateTime]::UtcNow.ToString('o')
        mode = 'StaticRuntimeHash'
        version = $version
        base_policy_id = $BasePolicyId.ToString('B')
        supplemental_policy_id = $policyId
        supplemental_policy_xml = [IO.Path]::GetFileName($policyXml)
        supplemental_policy_cip = [IO.Path]::GetFileName($policyCip)
        portable = [ordered]@{
            name = $portableName
            sha256 = Get-Sha256 $portable
            runtime_file_count = [int]$runtimeRecords.Count
            runtime_tree_sha256 = [string]$build.runtime_tree_sha256
            runtime_files = $runtimeRecords
        }
        enterprise_installer = [ordered]@{
            source = (Split-Path -Leaf $EnterpriseInstallerBundle)
            file_count = [int]$installerManifestRecords.Count
            files = $installerManifestRecords
        }
        russian_release_verification = 'PASS'
        app_control_base_state_changed = $false
        deployment_performed = $false
        deployment_invariants = @(
            'pack generation never deploys App Control policy',
            'Smart App Control must not be disabled as a workaround',
            'base Audit/Enforced state is never changed by this generator',
            'all Windows runtime executable bytes are static before policy generation',
            'hash trust is release-specific and must be regenerated for changed bytes'
        )
    }
    $manifestPath = Join-Path $OutputDirectory 'trust-pack.json'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $deployment = @"
ARVECTUM PROXY LAUNCHER - STATIC RUNTIME APP CONTROL TRUST PACK
==============================================================
Task: APL-WIN-014
Version: $version
Mode: StaticRuntimeHash
Base policy ID: $($BasePolicyId.ToString('B'))
Supplemental policy ID: $policyId

This pack does not deploy or weaken App Control. Customer IT owns policy deployment.
The package uses a static PyInstaller onedir runtime; no _MEI runtime discovery is part
of the supported enterprise trust model. Deploy only after isolated Enforced rehearsal.
"@
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'DEPLOYMENT.txt') -Value $deployment -Encoding UTF8

    $checksums = @(
        Get-ChildItem -LiteralPath $OutputDirectory -File | Sort-Object Name | ForEach-Object {
            "$(Get-Sha256 $_.FullName)  $($_.Name)"
        }
    )
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

    Write-Host ''
    Write-Host 'APL-WIN-014 static runtime enterprise trust pack: PASS'
    Write-Host "Output: $OutputDirectory"
    Write-Host "Policy ID: $policyId"
    Write-Host 'Deployment: NOT PERFORMED'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
