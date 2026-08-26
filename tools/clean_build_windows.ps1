<#
.SYNOPSIS
    Canonical reproducible clean-build script for Arvectum Proxy Launcher on Windows.
.DESCRIPTION
    Cleans previous build outputs, initializes an isolated build virtual environment,
    installs locked build dependencies, validates toolchain and versions, runs unit tests,
    builds a static PyInstaller onedir runtime, verifies Windows branding metadata,
    packages the complete runtime tree, verifies SHA256 manifests, and produces a
    build-result.json provenance manifest.

    APL-WIN-014 security invariant: the Windows enterprise runtime is never PyInstaller
    onefile. All executable DLL/PYD/support artifacts must exist in a static release tree
    before App Control policy generation. This prevents runtime extraction into _MEI temp
    directories after an App Control Audit -> Enforced transition.

    When -WheelhousePath is supplied, dependency installation is forced offline from the
    approved Windows x64 wheelhouse and every package is verified by pip against
    requirements-build.windows-x64.hashes.txt using --require-hashes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PythonExecutable,

    [Parameter(Mandatory = $false)]
    [string]$WheelhousePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $RepoRoot

Write-Host '=== Arvectum Proxy Launcher Canonical Clean Build ==='
Write-Host "Repository root: $RepoRoot"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RuntimeRecords([string]$Root) {
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    return @(
        Get-ChildItem -LiteralPath $resolved -File -Recurse -Force |
        Sort-Object FullName |
        ForEach-Object {
            $relative = [IO.Path]::GetRelativePath($resolved, $_.FullName).Replace('\\','/')
            [pscustomobject]@{
                relative_path = $relative
                sha256 = Get-Sha256 $_.FullName
                size = [long]$_.Length
            }
        }
    )
}

function Get-RuntimeTreeSha256([object[]]$Records) {
    $lines = @($Records | ForEach-Object { "$($_.relative_path)`0$($_.sha256)" })
    $payload = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

# ---------------------------------------------------------------------------
# 1. Resolve & Validate Python Toolchain
# ---------------------------------------------------------------------------
$ExpectedPyVersion = (Get-Content -LiteralPath (Join-Path $RepoRoot 'BUILD_PYTHON_VERSION') -Raw).Trim()
Write-Host "Required build Python version: $ExpectedPyVersion (64-bit)"

$CandidatePythons = @()
if ($PythonExecutable) { $CandidatePythons += $PythonExecutable }
$CandidatePythons += 'python.exe'
$CandidatePythons += "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$CandidatePythons += 'C:\Python312\python.exe'
$CandidatePythons += 'C:\Program Files\Python312\python.exe'

$ResolvedPython = $null
foreach ($cand in $CandidatePythons) {
    try {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        $target = if ($cmd) { $cmd.Source } else { $cand }
        if (Test-Path -LiteralPath $target) {
            $verCheck = & $target -c "import sys, platform; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}'); print(platform.architecture()[0])" 2>$null
            if ($LASTEXITCODE -eq 0 -and $verCheck.Count -ge 2) {
                if ($verCheck[0].Trim() -eq $ExpectedPyVersion -and $verCheck[1].Trim() -eq '64bit') {
                    $ResolvedPython = (Resolve-Path -LiteralPath $target).Path
                    break
                }
            }
        }
    } catch {}
}
if (-not $ResolvedPython) {
    throw "Required Python $ExpectedPyVersion (64-bit) not found. Install it or pass -PythonExecutable <path>."
}
Write-Host "Using base Python: $ResolvedPython"

# ---------------------------------------------------------------------------
# 2. Clean Build Artifacts
# ---------------------------------------------------------------------------
Write-Host 'Cleaning build-generated paths...'
$CleanPaths = @(
    (Join-Path $RepoRoot '.build-venv'),
    (Join-Path $RepoRoot 'build'),
    (Join-Path $RepoRoot 'dist'),
    (Join-Path $RepoRoot 'out'),
    (Join-Path $RepoRoot 'artifact')
)
foreach ($p in $CleanPaths) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
}
Get-ChildItem -Path $RepoRoot -Filter '*.spec' -File | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $RepoRoot -Filter '__pycache__' -Directory -Recurse | ForEach-Object {
    if ($_.FullName -notmatch '\\.git\\') { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
# 3. Create Isolated Virtual Environment
# ---------------------------------------------------------------------------
$VenvDir = Join-Path $RepoRoot '.build-venv'
Write-Host "Creating isolated virtual environment at $VenvDir..."
& $ResolvedPython -m venv --clear $VenvDir
if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $VenvPython)) { throw "Venv Python executable not found at $VenvPython" }
$isIsolated = & $VenvPython -c "import sys; print(sys.prefix != sys.base_prefix)"
if ($isIsolated.Trim() -ne 'True') { throw 'Virtual environment is not properly isolated.' }

# ---------------------------------------------------------------------------
# 4. Install Locked Build Toolchain
# ---------------------------------------------------------------------------
$LockFile = Join-Path $RepoRoot 'requirements-build.lock.txt'
$HashLockFile = Join-Path $RepoRoot 'requirements-build.windows-x64.hashes.txt'
if (-not (Test-Path -LiteralPath $LockFile)) { throw 'Lock file requirements-build.lock.txt missing' }

$DependencyMode = 'online-version-locked'
$ResolvedWheelhouse = $null
$WheelhouseManifestHash = $null
if ($WheelhousePath) {
    if (-not (Test-Path -LiteralPath $WheelhousePath -PathType Container)) { throw "Wheelhouse path does not exist: $WheelhousePath" }
    if (-not (Test-Path -LiteralPath $HashLockFile)) { throw 'Hash lock requirements-build.windows-x64.hashes.txt missing' }
    $ResolvedWheelhouse = (Resolve-Path -LiteralPath $WheelhousePath).Path
    Write-Host "Installing hash-locked build toolchain OFFLINE from $ResolvedWheelhouse..."
    $previousNoIndex = $env:PIP_NO_INDEX
    $previousDisableCheck = $env:PIP_DISABLE_PIP_VERSION_CHECK
    try {
        $env:PIP_NO_INDEX = '1'
        $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
        & $VenvPython -m pip install --no-index --find-links $ResolvedWheelhouse --only-binary=:all: --no-deps --require-hashes -r $HashLockFile
        if ($LASTEXITCODE -ne 0) { throw 'Offline hash-locked build dependency installation failed' }
    } finally {
        $env:PIP_NO_INDEX = $previousNoIndex
        $env:PIP_DISABLE_PIP_VERSION_CHECK = $previousDisableCheck
    }
    $DependencyMode = 'offline-hash-locked'
    $WheelhouseManifest = Join-Path $ResolvedWheelhouse 'wheelhouse-manifest.json'
    if (Test-Path -LiteralPath $WheelhouseManifest) { $WheelhouseManifestHash = Get-Sha256 $WheelhouseManifest }
} else {
    Write-Host 'Installing pinned pip (26.1.2)...'
    & $VenvPython -m pip install --upgrade 'pip==26.1.2'
    if ($LASTEXITCODE -ne 0) { throw 'pip upgrade failed' }
    Write-Host "Installing pinned build dependencies from $LockFile..."
    & $VenvPython -m pip install --no-deps -r $LockFile
    if ($LASTEXITCODE -ne 0) { throw 'Build dependencies installation failed' }
}
& $VenvPython -m pip check
if ($LASTEXITCODE -ne 0) { throw 'pip check reported broken dependencies' }
$ResolvedToolchain = & $VenvPython -m pip freeze --all
$ActualPipVersion = (& $VenvPython -m pip --version).Split(' ')[1]
if ($ActualPipVersion -ne '26.1.2') { throw "Unexpected pip version: $ActualPipVersion" }

# ---------------------------------------------------------------------------
# 5. Read Version & Generate Canonical Windows VERSIONINFO
# ---------------------------------------------------------------------------
$VersionFile = Join-Path $RepoRoot 'VERSION'
if (-not (Test-Path -LiteralPath $VersionFile)) { throw 'VERSION file is missing' }
$ProductVersion = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
$SemVerPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
if ($ProductVersion -notmatch $SemVerPattern) { throw "Invalid SemVer in VERSION: '$ProductVersion'" }
Write-Host "Product Version: $ProductVersion"
& $VenvPython (Join-Path $RepoRoot 'tools\generate_windows_version_info.py') --version-file $VersionFile --output (Join-Path $RepoRoot 'version_info.txt')
if ($LASTEXITCODE -ne 0) { throw 'Windows VERSIONINFO generation failed' }

# ---------------------------------------------------------------------------
# 6. Compile & Run Tests
# ---------------------------------------------------------------------------
Write-Host 'Compiling source files...'
& $VenvPython -m py_compile proxy_core.py structured_logging.py secret_redaction.py windows_diagnostics.py doctor.py proxy_gui.py portable_lifecycle.py tools\generate_windows_version_info.py
if ($LASTEXITCODE -ne 0) { throw 'py_compile failed' }
Write-Host 'Running unit test suite...'
& $VenvPython -m unittest discover -s tests -v
if ($LASTEXITCODE -ne 0) { throw 'Unit tests failed' }

# ---------------------------------------------------------------------------
# 7. PyInstaller STATIC ONEDIR Build
# ---------------------------------------------------------------------------
Write-Host 'Building static App-Control-compatible onedir runtime with PyInstaller...'
& $VenvPython -m PyInstaller `
    --noconfirm `
    --clean `
    --onedir `
    --contents-directory '.' `
    --windowed `
    --name 'Arvectum Proxy Launcher' `
    --version-file 'version_info.txt' `
    --icon 'assets\arvectum.ico' `
    --add-data 'no_proxy.txt;.' `
    --add-data 'assets;assets' `
    proxy_gui.py
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller build failed' }

$BuiltRuntime = Join-Path $RepoRoot 'dist\Arvectum Proxy Launcher'
$BuiltExe = Join-Path $BuiltRuntime 'Arvectum Proxy Launcher.exe'
if (-not (Test-Path -LiteralPath $BuiltRuntime -PathType Container)) { throw "Built runtime not found at $BuiltRuntime" }
if (-not (Test-Path -LiteralPath $BuiltExe -PathType Leaf)) { throw "Built executable not found at $BuiltExe" }

$RuntimeRecords = @(Get-RuntimeRecords $BuiltRuntime)
if ($RuntimeRecords.Count -lt 2) { throw 'Onedir runtime unexpectedly contains fewer than two files.' }
$RuntimeTreeHash = Get-RuntimeTreeSha256 $RuntimeRecords
$ExeHash = Get-Sha256 $BuiltExe

# APL-WIN-010: assert user-visible Windows PE branding from final bytes.
$ExeInfo = (Get-Item -LiteralPath $BuiltExe).VersionInfo
$VersionCore = ($ProductVersion -split '[-+]')[0]
$ExpectedFileVersion = "$VersionCore.0"
$MetadataAssertions = [ordered]@{
    CompanyName      = @($ExeInfo.CompanyName, 'ООО «Арвектум»')
    FileDescription  = @($ExeInfo.FileDescription, 'Arvectum Proxy Launcher')
    ProductName      = @($ExeInfo.ProductName, 'Arvectum Proxy Launcher')
    ProductVersion   = @($ExeInfo.ProductVersion, $ProductVersion)
    FileVersion      = @($ExeInfo.FileVersion, $ExpectedFileVersion)
    OriginalFilename = @($ExeInfo.OriginalFilename, 'Arvectum Proxy Launcher.exe')
}
foreach ($entry in $MetadataAssertions.GetEnumerator()) {
    if ([string]$entry.Value[0] -cne [string]$entry.Value[1]) {
        throw "Windows executable metadata mismatch for $($entry.Key): actual='$($entry.Value[0])' expected='$($entry.Value[1])'"
    }
}
Write-Host "Executable branding metadata PASS for $ProductVersion"
Write-Host "Static runtime: $BuiltRuntime"
Write-Host "Runtime files: $($RuntimeRecords.Count); tree SHA256: $RuntimeTreeHash"

# ---------------------------------------------------------------------------
# 8. Assemble Portable Package & Runtime Checksums
# ---------------------------------------------------------------------------
$ArtifactName = "Arvectum-Proxy-Launcher-$ProductVersion-windows-x64-portable"
$ZipName = "$ArtifactName.zip"
$OutDir = Join-Path $RepoRoot 'out'
$StageDir = Join-Path $OutDir "stage\$ArtifactName"
$RuntimeStage = Join-Path $StageDir 'runtime'
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
Copy-Item -LiteralPath $BuiltRuntime -Destination $RuntimeStage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'release\README_WINDOWS_PORTABLE.txt') -Destination (Join-Path $StageDir 'README.txt')
Copy-Item -LiteralPath (Join-Path $RepoRoot 'qa\diagnose_app_control.ps1') -Destination (Join-Path $StageDir 'diagnose_app_control.ps1')
Copy-Item -LiteralPath (Join-Path $RepoRoot 'qa\run_p01_native_qa_v2.ps1') -Destination (Join-Path $StageDir 'run_p01_native_qa_v2.ps1')

$RuntimeChecksumLines = @($RuntimeRecords | ForEach-Object { "$($_.sha256)  $($_.relative_path)" })
Set-Content -LiteralPath (Join-Path $StageDir 'RUNTIME_SHA256SUMS.txt') -Value $RuntimeChecksumLines -Encoding ascii
Set-Content -LiteralPath (Join-Path $StageDir 'SHA256SUMS.txt') -Value "$ExeHash  runtime/Arvectum Proxy Launcher.exe" -Encoding ascii

# ---------------------------------------------------------------------------
# 9. Create ZIP Package & External Checksum
# ---------------------------------------------------------------------------
$ZipPath = Join-Path $OutDir $ZipName
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Compress-Archive -Path "$StageDir\*" -DestinationPath $ZipPath -Force
$ZipHash = Get-Sha256 $ZipPath
Write-Host "Created portable ZIP package: $ZipPath (SHA256: $ZipHash)"
Set-Content -LiteralPath (Join-Path $OutDir 'SHA256SUMS.txt') -Value "$ZipHash  $ZipName" -Encoding ascii

# ---------------------------------------------------------------------------
# 10. Unpack & Verify Package Content Contract
# ---------------------------------------------------------------------------
Write-Host 'Verifying ZIP package structure and complete runtime integrity...'
$VerifyDir = Join-Path $OutDir 'verify'
if (Test-Path -LiteralPath $VerifyDir) { Remove-Item -LiteralPath $VerifyDir -Recurse -Force }
Expand-Archive -LiteralPath $ZipPath -DestinationPath $VerifyDir -Force
$ExpectedFiles = @('README.txt', 'diagnose_app_control.ps1', 'run_p01_native_qa_v2.ps1', 'SHA256SUMS.txt', 'RUNTIME_SHA256SUMS.txt')
$ActualTopFiles = @(Get-ChildItem -LiteralPath $VerifyDir -File | Select-Object -ExpandProperty Name)
foreach ($ef in $ExpectedFiles) {
    if ($ActualTopFiles -notcontains $ef) { throw "Package verification failed: missing expected file '$ef'" }
}
foreach ($af in $ActualTopFiles) {
    if ($ExpectedFiles -notcontains $af) { throw "Package verification failed: unexpected top-level file '$af'" }
}
$UnpackedRuntime = Join-Path $VerifyDir 'runtime'
$UnpackedExe = Join-Path $UnpackedRuntime 'Arvectum Proxy Launcher.exe'
if (-not (Test-Path -LiteralPath $UnpackedExe -PathType Leaf)) { throw 'Package verification failed: runtime launcher is missing.' }
$UnpackedRecords = @(Get-RuntimeRecords $UnpackedRuntime)
$UnpackedTreeHash = Get-RuntimeTreeSha256 $UnpackedRecords
if ($UnpackedTreeHash -ne $RuntimeTreeHash) { throw "Package verification failed: runtime tree hash mismatch ($UnpackedTreeHash != $RuntimeTreeHash)" }
if ((Get-Sha256 $UnpackedExe) -ne $ExeHash) { throw 'Package verification failed: EXE hash mismatch.' }
$RuntimeManifest = @(Get-Content -LiteralPath (Join-Path $VerifyDir 'RUNTIME_SHA256SUMS.txt') -Encoding ascii)
if ($RuntimeManifest.Count -ne $RuntimeRecords.Count) { throw 'Package verification failed: runtime checksum record count mismatch.' }
foreach ($record in $RuntimeRecords) {
    $expectedLine = "$($record.sha256)  $($record.relative_path)"
    if ($RuntimeManifest -cnotcontains $expectedLine) { throw "Package verification failed: runtime manifest missing $($record.relative_path)" }
}
Remove-Item -LiteralPath $VerifyDir -Recurse -Force
Remove-Item -LiteralPath (Join-Path $OutDir 'stage') -Recurse -Force

# ---------------------------------------------------------------------------
# 11. Build Result Manifest
# ---------------------------------------------------------------------------
$GitCommit = ''
try {
    $GitCommit = (git rev-parse HEAD 2>$null)
    if ($GitCommit) { $GitCommit = $GitCommit.Trim() }
} catch { $GitCommit = 'unknown' }
$LockHash = Get-Sha256 $LockFile
$HashLockHash = $null
if (Test-Path -LiteralPath $HashLockFile) { $HashLockHash = Get-Sha256 $HashLockFile }
$Manifest = [ordered]@{
    product                    = 'Arvectum Proxy Launcher'
    company                    = 'ООО «Арвектум»'
    version                    = $ProductVersion
    file_version               = $ExpectedFileVersion
    platform                   = 'windows-x64'
    format                     = 'portable-onedir'
    app_control_runtime_model  = 'static-onedir'
    python_version             = $ExpectedPyVersion
    pip_version                = '26.1.2'
    pyinstaller_version        = '6.22.0'
    dependency_mode            = $DependencyMode
    source_commit              = $GitCommit
    artifact_name              = $ArtifactName
    zip_file                   = $ZipName
    exe_sha256                 = $ExeHash
    runtime_root               = 'runtime'
    runtime_file_count         = [int]$RuntimeRecords.Count
    runtime_tree_sha256        = $RuntimeTreeHash
    zip_sha256                 = $ZipHash
    toolchain_lock_sha256      = $LockHash
    hash_lock_sha256           = $HashLockHash
    wheelhouse_manifest_sha256 = $WheelhouseManifestHash
}
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'build-result.json') -Encoding utf8
Write-Host 'Build manifest written to out/build-result.json'

# ---------------------------------------------------------------------------
# 12. Export to GITHUB_OUTPUT if present
# ---------------------------------------------------------------------------
if ($env:GITHUB_OUTPUT -and (Test-Path -LiteralPath $env:GITHUB_OUTPUT)) {
    "version=$ProductVersion" >> $env:GITHUB_OUTPUT
    "artifact_name=$ArtifactName" >> $env:GITHUB_OUTPUT
    "zip_path=$ZipPath" >> $env:GITHUB_OUTPUT
    "runtime_path=$BuiltRuntime" >> $env:GITHUB_OUTPUT
    "exe_path=$BuiltExe" >> $env:GITHUB_OUTPUT
    "exe_sha256=$ExeHash" >> $env:GITHUB_OUTPUT
    "runtime_tree_sha256=$RuntimeTreeHash" >> $env:GITHUB_OUTPUT
    "zip_sha256=$ZipHash" >> $env:GITHUB_OUTPUT
    "dependency_mode=$DependencyMode" >> $env:GITHUB_OUTPUT
}

Write-Host '=== Build Completed Successfully ==='
Write-Host "Artifact: $ArtifactName"
Write-Host "Dependency mode: $DependencyMode"
Write-Host "EXE SHA256: $ExeHash"
Write-Host "Runtime tree SHA256: $RuntimeTreeHash"
Write-Host "ZIP SHA256: $ZipHash"
