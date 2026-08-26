<#
.SYNOPSIS
    Produces the exact ARVECTUM-DEMO stand-driver hotfix for the recovered sealed
    0.2.3 state observed on 2026-08-26.
.DESCRIPTION
    The validated 0.2.4 stand kit assumed that an exact sealed 0.2.3 EXE under
    Documents\ArvectumProxyLauncher must always have exactly one Inno uninstaller.
    Emergency recovery legitimately restored the exact EXE plus durable state and
    owner marker without recreating Inno ownership.

    This patch is intentionally bound to the exact previously validated stand
    driver SHA256. It changes only two contracts:
      * Preflight accepts zero OR one unins*.exe, while still rejecting >1.
        Zero uninstallers is accepted only when the recovery owner marker exists.
      * After Save-RecoveryBackup + Enforced native-recovery PREARM have passed,
        destructive cleanup either runs the single Inno uninstaller or, for the
        zero-uninstaller recovery state, removes only the exact sealed EXE and the
        recovery owner marker.

    It does not execute the input script and does not mutate App Control, product,
    network, Defender, or Smart App Control by itself.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$inputResolved = (Resolve-Path -LiteralPath $InputPath).Path
$expectedInputSha256 = '4cc50bfb55bb5b1773c7a39468e11d53b2d87a05247b23babf40af33be529f1f'
$actualInputSha256 = (Get-FileHash -LiteralPath $inputResolved -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualInputSha256 -ne $expectedInputSha256) {
    throw "Refusing to patch unknown stand driver. Expected SHA256 $expectedInputSha256, found $actualInputSha256."
}

# The validated stand-kit stores LF line endings, while Git checkout on a Windows
# runner can materialize this patcher itself with CRLF. Normalize all compared
# strings so the fail-closed exact-block checks are content-exact but newline-style
# independent. The output remains bound by a newly generated SHA256 and harness
# supplemental, so this does not weaken byte identity on the stand.
$text = (Get-Content -LiteralPath $inputResolved -Raw -Encoding UTF8) -replace "`r`n","`n"

$oldHealth = @'
function Assert-Sealed023CurrentHealthy {
    if (-not (Test-Path -LiteralPath $Sealed023Exe -PathType Leaf) -or (Hash $Sealed023Exe) -ne $ExpectedSealed023AppSha256) { throw 'Exact sealed 0.2.3 is not installed at the governed current path.' }
    $null = Resolve-Uninstaller
    foreach ($name in @('proxy_settings.json','no_proxy.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $StateRoot $name) -PathType Leaf)) { throw "Exact current durable state missing: $name" }
    }
    Wait-PacHealth $Sealed023Exe 10
}
'@

$newHealth = @'
function Assert-Sealed023CurrentHealthy {
    if (-not (Test-Path -LiteralPath $Sealed023Exe -PathType Leaf) -or (Hash $Sealed023Exe) -ne $ExpectedSealed023AppSha256) { throw 'Exact sealed 0.2.3 is not installed at the governed current path.' }
    $uninstallers = @(Get-ChildItem -LiteralPath $InstallRoot -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
    if ($uninstallers.Count -gt 1) { throw "Exact sealed 0.2.3 install-root state has multiple Inno uninstallers; found $($uninstallers.Count)." }
    if ($uninstallers.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $InstallRoot '.arvectum-install-owner') -PathType Leaf)) {
        throw 'Exact sealed 0.2.3 has no Inno uninstaller and no recovery owner marker; refusing ambiguous install-root state.'
    }
    foreach ($name in @('proxy_settings.json','no_proxy.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $StateRoot $name) -PathType Leaf)) { throw "Exact current durable state missing: $name" }
    }
    Wait-PacHealth $Sealed023Exe 10
}
'@

$oldHealth = $oldHealth -replace "`r`n","`n"
$newHealth = $newHealth -replace "`r`n","`n"
if (($text.Split($oldHealth).Count - 1) -ne 1) {
    throw 'Expected exact Assert-Sealed023CurrentHealthy block was not found exactly once; refusing to patch.'
}
$text = $text.Replace($oldHealth,$newHealth)

$oldRemoval = @'
function Remove-CurrentInstallAfterRollback {
    Invoke-BoundedRollback $Sealed023Exe 20
    $uninstaller = Resolve-Uninstaller
    $p = Start-Process -FilePath $uninstaller -WorkingDirectory $InstallRoot -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$(Join-Path $EvidenceRoot 'sealed-023-pre-lifecycle-uninstall.log')")) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "Sealed 0.2.3 uninstall failed with exit code $($p.ExitCode)." }
    Stop-ExactProcesses $Sealed023Exe
    Remove-Item -LiteralPath $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
        $left = @(Get-ChildItem -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { Remove-Item -LiteralPath $InstallRoot -Force }
    }
    if (@(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue).Count -gt 0) { throw 'TCP 8082 is not free after sealed 0.2.3 rollback/uninstall.' }
}
'@

$newRemoval = @'
function Remove-CurrentInstallAfterRollback {
    Invoke-BoundedRollback $Sealed023Exe 20
    $uninstallers = @(Get-ChildItem -LiteralPath $InstallRoot -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
    if ($uninstallers.Count -gt 1) { throw "Exact sealed 0.2.3 install-root state has multiple Inno uninstallers after rollback; found $($uninstallers.Count)." }
    if ($uninstallers.Count -eq 1) {
        $uninstaller = $uninstallers[0].FullName
        $p = Start-Process -FilePath $uninstaller -WorkingDirectory $InstallRoot -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$(Join-Path $EvidenceRoot 'sealed-023-pre-lifecycle-uninstall.log')")) -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Sealed 0.2.3 uninstall failed with exit code $($p.ExitCode)." }
    } else {
        $ownerMarker = Join-Path $InstallRoot '.arvectum-install-owner'
        if (-not (Test-Path -LiteralPath $ownerMarker -PathType Leaf)) { throw 'Recovery owner marker disappeared after PREARM; refusing destructive cleanup.' }
        if (-not (Test-Path -LiteralPath $Sealed023Exe -PathType Leaf) -or (Hash $Sealed023Exe) -ne $ExpectedSealed023AppSha256) { throw 'Exact recovered sealed 0.2.3 bytes changed after PREARM; refusing cleanup.' }
        Remove-Item -LiteralPath $Sealed023Exe -Force -ErrorAction Stop
        Remove-Item -LiteralPath $ownerMarker -Force -ErrorAction Stop
    }
    Stop-ExactProcesses $Sealed023Exe
    Remove-Item -LiteralPath $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
        $left = @(Get-ChildItem -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { Remove-Item -LiteralPath $InstallRoot -Force }
    }
    if (@(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue).Count -gt 0) { throw 'TCP 8082 is not free after sealed 0.2.3 rollback/uninstall.' }
}
'@

$oldRemoval = $oldRemoval -replace "`r`n","`n"
$newRemoval = $newRemoval -replace "`r`n","`n"
if (($text.Split($oldRemoval).Count - 1) -ne 1) {
    throw 'Expected exact Remove-CurrentInstallAfterRollback block was not found exactly once; refusing to patch.'
}
$text = $text.Replace($oldRemoval,$newRemoval)

$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
Set-Content -LiteralPath $OutputPath -Value $text -Encoding UTF8 -NoNewline

$out = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
foreach ($required in @(
    "`$uninstallers.Count -gt 1",
    "no Inno uninstaller and no recovery owner marker",
    "Recovery owner marker disappeared after PREARM",
    "Exact recovered sealed 0.2.3 bytes changed after PREARM"
)) {
    if (-not $out.Contains($required)) { throw "Patched stand driver is missing required contract: $required" }
}
if ($out.Contains("    `$null = Resolve-Uninstaller")) { throw 'Legacy preflight uninstaller requirement survived the patch.' }
if ($out.Contains("    `$uninstaller = Resolve-Uninstaller`r`n    `$p = Start-Process")) { throw 'Legacy unconditional uninstall path survived the patch.' }

Write-Host 'APL-WIN-014 exact install-root recovery-state stand-driver patch: PASS'
Write-Host "Input SHA256:  $actualInputSha256"
Write-Host "Output SHA256: $((Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Host 'Input execution: NONE'
Write-Host 'Policy/product/network mutation: NONE'
