<#
.SYNOPSIS
    Build the native APL-WIN-014 recovery executable.
.DESCRIPTION
    Recovery must remain executable after App Control switches to Enforced and
    Windows PowerShell enters ConstrainedLanguage. This builder therefore emits
    a small .NET Framework EXE that uses only native/managed Windows APIs at run
    time. It never deploys or changes App Control policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$StaticRuntimeDirectory,
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Native App Control recovery build must run on Windows.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$StaticRuntimeDirectory = (Resolve-Path -LiteralPath $StaticRuntimeDirectory).Path
$runtimeManifestPath = Join-Path $StaticRuntimeDirectory 'static-runtime.json'
if (-not (Test-Path -LiteralPath $runtimeManifestPath -PathType Leaf)) {
    throw 'Static runtime manifest is required before recovery can be built.'
}
$runtimeManifest = Get-Content -LiteralPath $runtimeManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$runtimeManifest.result -ne 'PASS' -or
    [string]$runtimeManifest.packaging_layout -ne 'static-runtime' -or
    [bool]$runtimeManifest.pyinstaller_onefile) {
    throw 'Recovery build refuses a non-static or onefile runtime.'
}

$entry = Join-Path $StaticRuntimeDirectory ([string]$runtimeManifest.entry_executable)
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'Static runtime entry executable is missing.' }
$entryHash = (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant()
if ($entryHash -ne ([string]$runtimeManifest.entry_sha256).ToLowerInvariant()) {
    throw 'Static runtime entry hash does not match static-runtime.json.'
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root 'out\app-control-recovery'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { Remove-Item -LiteralPath $OutputDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $csc) {
    $command = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($command) { $csc = $command.Source }
}
if (-not $csc) { throw 'C# compiler csc.exe is unavailable on this Windows build host.' }

$source = Join-Path $root 'tools\windows_app_control_recovery.cs'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Native recovery source is missing.' }
$exe = Join-Path $OutputDirectory 'Arvectum Proxy Launcher Recovery.exe'

Write-Host "Compiling native recovery with: $csc"
& $csc /nologo /target:exe /platform:anycpu /optimize+ "/out:$exe" $source
if ($LASTEXITCODE -ne 0) { throw "csc.exe failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Native recovery executable was not created.' }

$exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    schema = 'arvectum.proxy.apl-win-014-native-recovery-build.v1'
    task = 'APL-WIN-014'
    created_utc = [DateTime]::UtcNow.ToString('o')
    result = 'PASS'
    artifact = [IO.Path]::GetFileName($exe)
    artifact_sha256 = $exeHash
    runtime_entry = [IO.Path]::GetFileName($entry)
    runtime_entry_sha256 = $entryHash
    requires_powershell_runtime = $false
    app_control_policy_mutation = $false
    destructive_recovery_rehearsal_required = $true
    invocation = 'Arvectum Proxy Launcher Recovery.exe --backup <backup-dir> --runtime <static-runtime-dir> --expected-runtime-sha256 <sha256> --evidence <result.json>'
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'native-recovery.json') -Encoding UTF8

Write-Host 'APL-WIN-014 native recovery build: PASS'
Write-Host "Recovery EXE: $exe"
Write-Host "SHA256: $exeHash"
Write-Host 'PowerShell runtime dependency: NONE'
Write-Host 'App Control policy mutation: NONE'
Write-Host 'Enforced rehearsal: STILL REQUIRED'
