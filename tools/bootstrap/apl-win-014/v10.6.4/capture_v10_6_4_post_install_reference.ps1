<# Read-only capture of the sealed V10.6.4 candidate installation for V10.7 authoring. #>
#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Join-Path $env:USERPROFILE 'Documents\ArvectumProxyLauncher' }
if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { throw "Installation directory not found: $InstallRoot" }
function Get-Sha256([string]$Path) { $out = & (Join-Path $env:SystemRoot 'System32\certutil.exe') -hashfile $Path SHA256; $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' }); if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 1) { throw "certutil SHA256 failed for $Path" }; $hashes[0] }
$seal = Get-Content -LiteralPath (Join-Path $scriptDir 'expected_hashes.json') -Raw | ConvertFrom-Json
$app = Join-Path $InstallRoot $seal.files.application.filename
$repair = Join-Path $InstallRoot $seal.files.setup.filename
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { throw 'Installed application is missing.' }
if ((Get-Sha256 $app) -ine $seal.files.application.sha256) { throw 'Installed application hash does not match the V10.6.4 seal.' }
if (Test-Path -LiteralPath $repair -PathType Leaf) { if ((Get-Sha256 $repair) -ine $seal.files.setup.sha256) { throw 'Cached repair setup hash does not match the V10.6.4 seal.' } }
$outDir = Join-Path $scriptDir ("v10.6.4-reference-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$files = @()
Get-ChildItem -LiteralPath $InstallRoot -File -Recurse -Force | ForEach-Object { $files += [ordered]@{ relative_path=($_.FullName -replace ('^' + ($InstallRoot -replace '([\\(){}+.|^$])','\$1') + '\\?'), ''); sha256=(Get-Sha256 $_.FullName); size=$_.Length; is_pe=($_.Extension -in @('.exe','.dll','.sys','.ocx')) } }
[ordered]@{ schema='arvectum.proxy.apl-win-014-v10.6.4-reference-capture.v1'; candidate_source_commit=$seal.candidate_source_commit; candidate_artifact_id=$seal.candidate_artifact_id; install_root=$InstallRoot; files=$files } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outDir 'reference-capture.json') -Encoding UTF8
Write-Host "REFERENCE CAPTURE COMPLETE: $outDir"
