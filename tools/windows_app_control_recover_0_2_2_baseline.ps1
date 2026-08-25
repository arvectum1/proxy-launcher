<#
.SYNOPSIS
    Recover the exact historical 0.2.2 P0.4 customer package for APL-WIN-014.
.DESCRIPTION
    Materializes the retained customer ZIP directly from the immutable Git object at
    commit 0ea08d9..., verifies its Git blob identity/size and the historically recorded
    application EXE SHA-256/version, expands it, and writes a local recovery manifest.

    This script NEVER rebuilds 0.2.2 and never accepts a same-version substitute.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutputDirectory = 'C:\Arvectum\Releases\0.2.2-P0.4-baseline',
    [string]$EvidenceDirectory = 'C:\Arvectum\Evidence\APL-WIN-014\baseline-recovery'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedCommit = '0ea08d9c815da36d0175f62db153de78f89731fc'
$ExpectedPath = 'release/Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip'
$ExpectedBlobSha1 = '574d3dc5f90a116555e3a72ff3288c31c19d3dc7'
$ExpectedBlobSize = 15963815
$ExpectedApplicationSha256 = '7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0'
$ExpectedProductVersion = '0.2.2'
$ExpectedFileVersion = '0.2.2.0'
$QaEvidencePath = 'qa/CHATGPT_REPORT_0.2.2_P0.4.md'
$QaEvidenceBlobSha1 = '163e61cd2e1d8ff798289faf075775af8f9bbd41'

function Invoke-GitText([string[]]$Arguments) {
    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join ' ')" }
    return (($output -join [Environment]::NewLine).Trim())
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { throw 'git.exe is required to recover the retained historical baseline.' }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot '.git'))) { throw "RepositoryRoot is not a Git working copy: $RepositoryRoot" }

if (Test-Path -LiteralPath $OutputDirectory) { throw "OutputDirectory already exists; refusing to overwrite recovered evidence: $OutputDirectory" }
if (Test-Path -LiteralPath $EvidenceDirectory) { throw "EvidenceDirectory already exists; refusing to overwrite evidence: $EvidenceDirectory" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ('Arvectum-0.2.2-baseline-' + [guid]::NewGuid().ToString('N'))
$historyArchive = Join-Path $tempRoot 'git-history.zip'
$historyExtract = Join-Path $tempRoot 'history'
New-Item -ItemType Directory -Path $tempRoot,$historyExtract -Force | Out-Null

Push-Location $RepositoryRoot
try {
    $commit = Invoke-GitText @('rev-parse','--verify',("$ExpectedCommit^{commit}"))
    if ($commit.ToLowerInvariant() -ne $ExpectedCommit) { throw 'Historical 0.2.2 commit identity mismatch.' }

    $blob = Invoke-GitText @('rev-parse',("${ExpectedCommit}:$ExpectedPath"))
    if ($blob.ToLowerInvariant() -ne $ExpectedBlobSha1) { throw "Historical package Git blob mismatch. Expected=$ExpectedBlobSha1 actual=$blob" }

    $blobSize = [long](Invoke-GitText @('cat-file','-s',$ExpectedBlobSha1))
    if ($blobSize -ne $ExpectedBlobSize) { throw "Historical package size mismatch. Expected=$ExpectedBlobSize actual=$blobSize" }

    $qaBlob = Invoke-GitText @('rev-parse',("${ExpectedCommit}:$QaEvidencePath"))
    if ($qaBlob.ToLowerInvariant() -ne $QaEvidenceBlobSha1) { throw 'Historical P0.4 QA evidence blob mismatch.' }

    & git archive --format=zip --output=$historyArchive $ExpectedCommit $ExpectedPath $QaEvidencePath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $historyArchive -PathType Leaf)) { throw 'git archive failed while materializing historical baseline.' }
}
finally {
    Pop-Location
}

try {
    Expand-Archive -LiteralPath $historyArchive -DestinationPath $historyExtract -Force
    $materialized = Join-Path $historyExtract ($ExpectedPath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $materialized -PathType Leaf)) { throw 'Historical customer ZIP was not materialized from git archive.' }

    Push-Location $RepositoryRoot
    try { $materializedBlob = Invoke-GitText @('hash-object',$materialized) }
    finally { Pop-Location }
    if ($materializedBlob.ToLowerInvariant() -ne $ExpectedBlobSha1) { throw 'Materialized ZIP bytes do not reproduce the governed Git blob.' }

    $packageZip = Join-Path $OutputDirectory 'Arvectum-Proxy-Launcher-Windows-0.2.2-P0.4-client.zip'
    Copy-Item -LiteralPath $materialized -Destination $packageZip -Force
    if ((Get-Item -LiteralPath $packageZip).Length -ne $ExpectedBlobSize) { throw 'Recovered customer ZIP size changed after copy.' }
    $packageSha256 = Get-Sha256 $packageZip

    $packageDir = Join-Path $OutputDirectory 'package'
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    Expand-Archive -LiteralPath $packageZip -DestinationPath $packageDir -Force

    $appCandidates = @(Get-ChildItem -LiteralPath $packageDir -Recurse -File -Filter 'Arvectum Proxy Launcher.exe')
    if ($appCandidates.Count -ne 1) { throw "Recovered package must contain exactly one launcher EXE; found $($appCandidates.Count)." }
    $appExe = $appCandidates[0].FullName
    $packageRoot = $appCandidates[0].Directory.FullName
    $appSha256 = Get-Sha256 $appExe
    if ($appSha256 -ne $ExpectedApplicationSha256) { throw "Historical application SHA256 mismatch. Expected=$ExpectedApplicationSha256 actual=$appSha256" }

    $version = (Get-Item -LiteralPath $appExe).VersionInfo
    if ([string]$version.ProductVersion -ne $ExpectedProductVersion) { throw "Historical ProductVersion mismatch: $($version.ProductVersion)" }
    if ([string]$version.FileVersion -ne $ExpectedFileVersion) { throw "Historical FileVersion mismatch: $($version.FileVersion)" }

    foreach ($required in @('install.bat','install.ps1','uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $required) -PathType Leaf)) { throw "Recovered P0.4 package is missing required installer file beside the application EXE: $required" }
    }

    $files = @(Get-ChildItem -LiteralPath $packageDir -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relative_path = $_.FullName.Substring($packageDir.Length).TrimStart('\')
            size = [long]$_.Length
            sha256 = Get-Sha256 $_.FullName
        }
    })

    $manifest = [ordered]@{
        schema = 'arvectum.proxy.apl-win-014-baseline-recovery.v1'
        task = 'APL-WIN-014'
        recovered_utc = [DateTime]::UtcNow.ToString('o')
        source = [ordered]@{
            repository = 'arvectum1/proxy-launcher'
            commit = $ExpectedCommit
            path = $ExpectedPath
            git_blob_sha1 = $ExpectedBlobSha1
            git_blob_size = $ExpectedBlobSize
            qa_evidence_path = $QaEvidencePath
            qa_evidence_blob_sha1 = $QaEvidenceBlobSha1
        }
        baseline = [ordered]@{
            kind = 'LegacyClientZip'
            version = $ExpectedProductVersion
            file_version = $ExpectedFileVersion
            package_zip = $packageZip
            package_sha256 = $packageSha256
            package_directory = $packageDir
            package_root = $packageRoot
            application_exe_sha256 = $appSha256
            application_relative_path = $appExe.Substring($packageDir.Length).TrimStart('\')
        }
        files = $files
        result = 'PASS'
    }
    $manifestPath = Join-Path $EvidenceDirectory 'apl-win-014-0.2.2-baseline-recovery.json'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifestHash = Get-Sha256 $manifestPath
    Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'SHA256SUMS.txt') -Value "$manifestHash  apl-win-014-0.2.2-baseline-recovery.json" -Encoding ASCII

    Write-Host 'APL-WIN-014 historical 0.2.2 P0.4 recovery: PASS'
    Write-Host "Source commit: $ExpectedCommit"
    Write-Host "Git blob: $ExpectedBlobSha1"
    Write-Host "Recovered ZIP SHA256: $packageSha256"
    Write-Host "Application SHA256: $appSha256"
    Write-Host "Package root: $packageRoot"
    Write-Host "Manifest: $manifestPath"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
