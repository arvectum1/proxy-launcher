<#
.SYNOPSIS
    Build a deterministic PyInstaller onedir runtime for App Control for Business work.
.DESCRIPTION
    This is the replacement build shape for the unsafe PyInstaller onefile/_MEI model
    discovered on ARVECTUM-DEMO. It emits a static runtime directory plus an exact hash
    inventory. It does not alter App Control, does not deploy a policy, and does not by
    itself claim installer-lifecycle readiness.
#>
[CmdletBinding()]
param(
    [string]$PythonExecutable = '',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Static Windows runtime build must run on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root

if (-not $PythonExecutable) {
    $candidate = Join-Path $root '.build-venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $PythonExecutable = $candidate }
    else { $PythonExecutable = 'python.exe' }
}

$python = Get-Command $PythonExecutable -ErrorAction Stop
$pythonPath = $python.Source

$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root "out\app-control-static-runtime-$version"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

if (Test-Path -LiteralPath $OutputDirectory) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$work = Join-Path $root 'build\app-control-static-runtime'
$dist = Join-Path $root 'dist\app-control-static-runtime'
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue

$versionInfo = Join-Path $root 'version_info.txt'
if (-not (Test-Path -LiteralPath $versionInfo -PathType Leaf)) {
    & $pythonPath (Join-Path $root 'tools\generate_windows_version_info.py') `
        --version-file (Join-Path $root 'VERSION') `
        --output $versionInfo
    if ($LASTEXITCODE -ne 0) { throw 'Windows VERSIONINFO generation failed.' }
}

Write-Host 'Building App Control static runtime with PyInstaller --onedir...'
& $pythonPath -m PyInstaller `
    --noconfirm `
    --clean `
    --onedir `
    --windowed `
    --name 'Arvectum Proxy Launcher' `
    --workpath $work `
    --distpath $dist `
    --version-file $versionInfo `
    --icon (Join-Path $root 'assets\arvectum.ico') `
    --add-data "$(Join-Path $root 'no_proxy.txt');." `
    --add-data "$(Join-Path $root 'assets');assets" `
    (Join-Path $root 'proxy_gui.py')
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller --onedir build failed.' }

$runtimeSource = Join-Path $dist 'Arvectum Proxy Launcher'
$entry = Join-Path $runtimeSource 'Arvectum Proxy Launcher.exe'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) {
    throw 'Static runtime entry executable is missing.'
}

Copy-Item -LiteralPath (Join-Path $runtimeSource '*') -Destination $OutputDirectory -Recurse -Force
$entryOut = Join-Path $OutputDirectory 'Arvectum Proxy Launcher.exe'
if (-not (Test-Path -LiteralPath $entryOut -PathType Leaf)) { throw 'Static runtime copy is incomplete.' }

$files = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse -Force)
if ($files.Count -lt 2) {
    throw 'Static runtime unexpectedly contains fewer than two files; onefile output is not accepted.'
}
if (@($files | Where-Object { $_.FullName -match '[\\/]_MEI\d+' }).Count -gt 0) {
    throw 'Static runtime contains a forbidden _MEI extraction path.'
}

$executableExtensions = @('.exe','.dll','.pyd','.ocx','.sys')
$executableFiles = @(
    $files | Where-Object { $executableExtensions -contains $_.Extension.ToLowerInvariant() }
)
if ($executableFiles.Count -lt 2) {
    throw 'Static runtime executable inventory is incomplete.'
}

$inventory = @(
    $files | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relative_path = $_.FullName.Substring($OutputDirectory.Length).TrimStart('\')
            size = [long]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            executable = $executableExtensions -contains $_.Extension.ToLowerInvariant()
        }
    }
)

$manifest = [ordered]@{
    schema = 'arvectum.proxy.windows-app-control-static-runtime.v1'
    task = 'APL-WIN-014'
    version = $version
    created_utc = [DateTime]::UtcNow.ToString('o')
    result = 'PASS'
    packaging_layout = 'static-runtime'
    pyinstaller_mode = 'onedir'
    pyinstaller_onefile = $false
    runtime_complete = $true
    installer_lifecycle_complete = $false
    enforced_lifecycle_ready = $false
    entry_executable = 'Arvectum Proxy Launcher.exe'
    entry_sha256 = (Get-FileHash -LiteralPath $entryOut -Algorithm SHA256).Hash.ToLowerInvariant()
    file_count = $files.Count
    executable_file_count = $executableFiles.Count
    files = $inventory
    safety = @(
        'no App Control policy is deployed or changed by this builder',
        'no _MEI runtime discovery is permitted',
        'installer lifecycle readiness remains false until deterministic installer artifacts and Enforced recovery rehearsal are proven'
    )
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'static-runtime.json') -Encoding UTF8

Write-Host 'APL-WIN-014 static runtime build: PASS'
Write-Host "Output: $OutputDirectory"
Write-Host "Executable artifacts: $($executableFiles.Count)"
Write-Host 'PyInstaller onefile/_MEI: PROHIBITED'
Write-Host 'Installer lifecycle readiness: NOT YET PROVEN'
