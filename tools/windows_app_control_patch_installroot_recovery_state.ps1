<#
.SYNOPSIS
    Produces the ARVECTUM-DEMO stand-driver hotfix for a recovered sealed 0.2.3
    runtime that lives in the canonical install root without an Inno uninstaller.
.DESCRIPTION
    The emergency recovery can legitimately leave the exact sealed 0.2.3 EXE and
    install-owner marker in Documents\ArvectumProxyLauncher without unins*.exe.
    That state is recovery-owned, not an installed Inno lifecycle. The original
    APL-WIN-014 driver classified by path alone and blocked preflight.

    This patch is intentionally narrow and fail-closed. It:
      * treats install-root + zero uninstallers as INSTALL_ROOT_RECOVERY;
      * still rejects more than one uninstaller;
      * keeps exactly-one-uninstaller as INSTALLED;
      * after the already-guarded rollback in Execute, removes only the recovered
        exact EXE and owner marker before installing the historical baseline.

    It does not execute the input script and does not mutate App Control, product,
    network, Defender, or Smart App Control.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$inputResolved = (Resolve-Path -LiteralPath $InputPath).Path
$text = Get-Content -LiteralPath $inputResolved -Raw -Encoding UTF8

$oldClassification = @'
    $current = $healthy[0]
    $mode = 'PORTABLE_RECOVERY'
    $uninstaller = $null
    if ([IO.Path]::GetFullPath([string]$current.exe) -ieq [IO.Path]::GetFullPath($Sealed023Exe)) {
        $uninstallers = @(Get-ChildItem -LiteralPath $InstallRoot -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
        if ($uninstallers.Count -ne 1) {
            throw "Installed exact sealed 0.2.3 must have exactly one Inno uninstaller; found $($uninstallers.Count)."
        }
        $mode = 'INSTALLED'
        $uninstaller = $uninstallers[0].FullName
    }
'@

$newClassification = @'
    $current = $healthy[0]
    $mode = 'PORTABLE_RECOVERY'
    $uninstaller = $null
    if ([IO.Path]::GetFullPath([string]$current.exe) -ieq [IO.Path]::GetFullPath($Sealed023Exe)) {
        $uninstallers = @(Get-ChildItem -LiteralPath $InstallRoot -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
        if ($uninstallers.Count -gt 1) {
            throw "Exact sealed 0.2.3 install-root state has multiple Inno uninstallers; found $($uninstallers.Count)."
        }
        if ($uninstallers.Count -eq 1) {
            $mode = 'INSTALLED'
            $uninstaller = $uninstallers[0].FullName
        } else {
            # Emergency/native recovery can legitimately restore the exact sealed
            # EXE into InstallRoot without recreating Inno ownership. Path alone is
            # therefore not sufficient evidence of an installed lifecycle.
            $mode = 'INSTALL_ROOT_RECOVERY'
        }
    }
'@

if (-not $text.Contains($oldClassification)) {
    throw 'Expected sealed-0.2.3 classification block was not found exactly once; refusing to patch unknown input.'
}
if (($text.Split($oldClassification).Count - 1) -ne 1) {
    throw 'Expected sealed-0.2.3 classification block is not unique; refusing to patch.'
}
$text = $text.Replace($oldClassification,$newClassification)

$oldSupported = "    if (-not `$Current -or [string]`$Current.mode -notin @('INSTALLED','PORTABLE_RECOVERY')) {"
$newSupported = "    if (-not `$Current -or [string]`$Current.mode -notin @('INSTALLED','PORTABLE_RECOVERY','INSTALL_ROOT_RECOVERY')) {"
if (($text.Split($oldSupported).Count - 1) -ne 1) {
    throw 'Expected current-state mode guard was not found exactly once.'
}
$text = $text.Replace($oldSupported,$newSupported)

$anchor = @'
    if ([string]$Current.mode -eq 'INSTALLED') {
        $uninstaller = [string]$Current.uninstaller
        if (-not $uninstaller -or -not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
            throw 'Installed exact sealed 0.2.3 uninstaller disappeared after preflight.'
        }
        $p = Start-Process -FilePath $uninstaller -WorkingDirectory $InstallRoot -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$(Join-Path $EvidenceRoot 'sealed-023-pre-lifecycle-uninstall.log')")) -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Sealed 0.2.3 uninstall failed with exit code $($p.ExitCode)." }
    }

    Remove-Item -LiteralPath $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
'@

$replacement = @'
    if ([string]$Current.mode -eq 'INSTALLED') {
        $uninstaller = [string]$Current.uninstaller
        if (-not $uninstaller -or -not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
            throw 'Installed exact sealed 0.2.3 uninstaller disappeared after preflight.'
        }
        $p = Start-Process -FilePath $uninstaller -WorkingDirectory $InstallRoot -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$(Join-Path $EvidenceRoot 'sealed-023-pre-lifecycle-uninstall.log')")) -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Sealed 0.2.3 uninstall failed with exit code $($p.ExitCode)." }
    }

    if ([string]$Current.mode -eq 'INSTALL_ROOT_RECOVERY') {
        # This is not an Inno-owned installation. After exact --rollback has
        # stopped the recovered runtime, remove only the recovered outer EXE and
        # its portable/install-owner marker so the historical lifecycle starts
        # from an unambiguous product root. Durable proxy state is backed up first
        # by Invoke-Execute and is handled separately below.
        Remove-Item -LiteralPath ([string]$Current.exe) -Force -ErrorAction Stop
        Remove-Item -LiteralPath (Join-Path $InstallRoot '.arvectum-install-owner') -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
'@

if (($text.Split($anchor).Count - 1) -ne 1) {
    throw 'Expected sealed-0.2.3 cleanup anchor was not found exactly once.'
}
$text = $text.Replace($anchor,$replacement)

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
Set-Content -LiteralPath $OutputPath -Value $text -Encoding UTF8 -NoNewline

# Static postconditions on the output. No script execution is performed here.
$out = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
foreach ($required in @(
    "`$mode = 'INSTALL_ROOT_RECOVERY'",
    "@('INSTALLED','PORTABLE_RECOVERY','INSTALL_ROOT_RECOVERY')",
    "if ([string]`$Current.mode -eq 'INSTALL_ROOT_RECOVERY')"
)) {
    if (-not $out.Contains($required)) { throw "Patched stand driver is missing required contract: $required" }
}
if ($out.Contains('Installed exact sealed 0.2.3 must have exactly one Inno uninstaller')) {
    throw 'Legacy path-only Inno classification guard survived the patch.'
}

Write-Host 'APL-WIN-014 install-root recovery-state stand-driver patch: PASS'
Write-Host "Input SHA256:  $((Get-FileHash -LiteralPath $inputResolved -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Host "Output SHA256: $((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Host 'Input execution: NONE'
Write-Host 'Policy/product/network mutation: NONE'
