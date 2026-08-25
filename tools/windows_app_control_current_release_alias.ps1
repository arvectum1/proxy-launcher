<#
.SYNOPSIS
    Create the exact-byte local-gate compatibility alias for the sealed 0.2.3 Setup.
.DESCRIPTION
    The governed Russian release uses the canonical filename
    Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe while the older local App
    Control harness resolves ArvectumProxyLauncher-Setup-0.2.3.exe. This helper
    closes only that filename mismatch by copying the exact verified Setup bytes.

    It does not rebuild, modify, sign, deploy or otherwise transform the installer.
    The alias is local acceptance scaffolding and is not a promoted release artifact.
#>
[CmdletBinding()]
param(
    [string]$ReleaseDirectory = 'C:\Arvectum\Releases\0.2.3-russian-production'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$CanonicalName = 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
$LocalGateAlias = 'ArvectumProxyLauncher-Setup-0.2.3.exe'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$canonical = Join-Path $ReleaseDirectory $CanonicalName
$alias = Join-Path $ReleaseDirectory $LocalGateAlias
if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) { throw "Canonical sealed Setup is missing: $canonical" }
if ((Get-Sha256 $canonical) -ne $ExpectedSetupSha256) { throw 'Canonical sealed Setup SHA256 mismatch.' }

if (Test-Path -LiteralPath $alias -PathType Leaf) {
    if ((Get-Sha256 $alias) -ne $ExpectedSetupSha256) { throw 'Existing local-gate Setup alias has unexpected bytes; refusing to overwrite it.' }
    Write-Host 'APL-WIN-014 current Setup alias already present with exact sealed bytes: PASS'
    exit 0
}

Copy-Item -LiteralPath $canonical -Destination $alias -ErrorAction Stop
if ((Get-Sha256 $alias) -ne $ExpectedSetupSha256) {
    Remove-Item -LiteralPath $alias -Force -ErrorAction SilentlyContinue
    throw 'Local-gate Setup alias copy failed exact SHA256 verification.'
}

Write-Host 'APL-WIN-014 current Setup filename compatibility alias: PASS'
Write-Host "Canonical: $canonical"
Write-Host "Alias: $alias"
Write-Host "SHA256: $ExpectedSetupSha256"
Write-Host 'Promoted artifact mutation: NONE'
