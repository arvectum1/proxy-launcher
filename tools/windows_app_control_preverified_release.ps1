<#
.SYNOPSIS
    Exact preverified Russian release evidence validation for APL-WIN-014.
.DESCRIPTION
    Validates the immutable v0.2.3-ru.2 release bytes against the canonical
    owner-station signing acceptance record. This is for an acceptance host that
    does not carry CryptoPro/Rutoken signing infrastructure.

    This helper does not claim Authenticode or SmartScreen trust and never changes
    App Control, Smart App Control, Defender, registry policy, proxy state, or files.
#>

$script:ArvectumExpectedVersion = '0.2.3'
$script:ArvectumExpectedTag = 'v0.2.3-ru.2'
$script:ArvectumExpectedBuildCommit = '54ce2585222948b51c67510ea620516ea6c3f876'
$script:ArvectumExpectedReleaseCommit = '47823585c42da54ab51c67510ea620516ea6c3f876'
$script:ArvectumExpectedSetupSha256 = '5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414'
$script:ArvectumExpectedPortableSha256 = '62d313547b4d8c2c8e6951d6cd866bb954fdf199ad7650063c8ed3bfbc455801'
$script:ArvectumExpectedApplicationSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$script:ArvectumExpectedSignerThumbprint = 'EE1CFA955BA22F03C39C76B183D94CD37494582E'
$script:ArvectumExpectedSigningEvidenceSha256 = '67d379db11a238960b9324c8054e73790cf18b1eaa85db8c04a9226bb27bc58e'

function Get-ArvectumSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-ArvectumToken([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim().ToLowerInvariant()
}

function Assert-ArvectumPreverifiedRussianRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ReleaseDirectory,
        [Parameter(Mandatory = $true)] [string]$SigningEvidencePath
    )

    $release = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
    $evidencePath = (Resolve-Path -LiteralPath $SigningEvidencePath).Path
    $setup = Join-Path $release 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe'
    $portable = Join-Path $release 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-portable.zip'
    $compatAlias = Join-Path $release 'ArvectumProxyLauncher-Setup-0.2.3.exe'

    foreach ($required in @($setup, $portable, $evidencePath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required preverified release input is missing: $required"
        }
    }
    if (Test-Path -LiteralPath $compatAlias -PathType Leaf) {
        throw 'Strict production release directory contains the retired compatibility Setup alias.'
    }

    $setupHash = Get-ArvectumSha256 $setup
    $portableHash = Get-ArvectumSha256 $portable
    $evidenceHash = Get-ArvectumSha256 $evidencePath
    if ($setupHash -ne $script:ArvectumExpectedSetupSha256) { throw 'Production installer SHA256 mismatch.' }
    if ($portableHash -ne $script:ArvectumExpectedPortableSha256) { throw 'Production portable ZIP SHA256 mismatch.' }
    if ($evidenceHash -ne $script:ArvectumExpectedSigningEvidenceSha256) { throw 'Canonical Russian signing evidence file SHA256 mismatch.' }

    $ev = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$ev.schema_version -ne 1) { throw 'Signing evidence schema mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.version) -ne (ConvertTo-ArvectumToken $script:ArvectumExpectedVersion)) { throw 'Signing evidence version mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.git_tag) -ne (ConvertTo-ArvectumToken $script:ArvectumExpectedTag)) { throw 'Signing evidence tag mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.artifact_build_commit) -ne (ConvertTo-ArvectumToken $script:ArvectumExpectedBuildCommit)) { throw 'Signing evidence build commit mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.release_policy_commit) -ne (ConvertTo-ArvectumToken $script:ArvectumExpectedReleaseCommit)) { throw 'Signing evidence release-policy commit mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.installer.name) -ne 'arvectum-proxy-launcher-0.2.3-windows-x64-setup.exe') { throw 'Signing evidence installer name mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.installer.sha256) -ne $script:ArvectumExpectedSetupSha256) { throw 'Signing evidence installer hash mismatch.' }
    if ([long]$ev.installer.size_bytes -ne 17559854) { throw 'Signing evidence installer size mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.portable_zip.name) -ne 'arvectum-proxy-launcher-0.2.3-windows-x64-portable.zip') { throw 'Signing evidence portable name mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.portable_zip.sha256) -ne $script:ArvectumExpectedPortableSha256) { throw 'Signing evidence portable hash mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.signer.thumbprint) -ne (ConvertTo-ArvectumToken $script:ArvectumExpectedSignerThumbprint)) { throw 'Signing evidence signer thumbprint mismatch.' }
    if (-not [bool]$ev.acceptance.rel011_detached_signature_verified) { throw 'Signing evidence detached signature verification is not true.' }
    if ((ConvertTo-ArvectumToken $ev.acceptance.rel011_result) -ne 'pass') { throw 'Signing evidence REL-011 is not PASS.' }
    if ((ConvertTo-ArvectumToken $ev.acceptance.rel012_exact_release_verification) -ne 'pass') { throw 'Signing evidence REL-012 exact release verification is not PASS.' }
    if ((ConvertTo-ArvectumToken $ev.acceptance.rel012_negative_tamper_test) -ne 'pass_expected_failure') { throw 'Signing evidence tamper negative test mismatch.' }
    if ((ConvertTo-ArvectumToken $ev.acceptance.rel013_publication_decision) -ne 'publish') { throw 'Signing evidence publication decision is not PUBLISH.' }
    if ([bool]$ev.trust_boundary.embedded_authenticode_claimed) { throw 'Signing evidence unexpectedly claims embedded Authenticode trust.' }
    if ([bool]$ev.trust_boundary.smartscreen_trust_claimed) { throw 'Signing evidence unexpectedly claims SmartScreen trust.' }

    return [pscustomobject]@{
        release_directory = $release
        signing_evidence_path = $evidencePath
        signing_evidence_sha256 = $evidenceHash
        setup = $setup
        setup_sha256 = $setupHash
        portable = $portable
        portable_sha256 = $portableHash
        application_sha256 = $script:ArvectumExpectedApplicationSha256
        version = $script:ArvectumExpectedVersion
        tag = $script:ArvectumExpectedTag
        verification = 'PREVERIFIED_EXACT_HASH_BOUND'
    }
}
