<#
.SYNOPSIS
    Builds a lab-only App Control supplemental that trusts the exact APL-WIN-014
    PowerShell acceptance harness scripts.
.DESCRIPTION
    This policy is deliberately separate from product trust. It exists only so the
    acceptance harness can run in FullLanguage under the already-Enforced dedicated
    ARVECTUM-DEMO base policy. It never changes/deploys/removes policy itself.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [Guid]$BasePolicyId,
    [Parameter(Mandatory = $true)] [string]$OutputDirectory,
    [string]$CandidateRunner = 'tools\windows_app_control_candidate_runner.ps1',
    [string]$CandidateStand = 'tools\windows_app_control_candidate_stand.ps1',
    [string]$TrustPackV2 = 'tools\windows_app_control_enterprise_trust_pack_v2.ps1',
    [string]$EnforcedReadiness = 'tools\windows_app_control_enforced_readiness.ps1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }

foreach ($command in @('New-CIPolicy','Set-CIPolicyIdInfo','Set-CIPolicyVersion','Set-RuleOption','ConvertFrom-CIPolicy')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required ConfigCI command unavailable: $command" }
}

function Resolve-Leaf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}
function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$definitions = @(
    [ordered]@{ source = Resolve-Leaf $CandidateRunner 'candidate runner'; stand_relative_path = 'APL-WIN-014.ps1' },
    [ordered]@{ source = Resolve-Leaf $CandidateStand 'candidate stand driver'; stand_relative_path = 'APL-WIN-014-STAND.ps1' },
    [ordered]@{ source = Resolve-Leaf $TrustPackV2 'v2 trust-pack promoter'; stand_relative_path = 'kit-tools/windows_app_control_enterprise_trust_pack_v2.ps1' },
    [ordered]@{ source = Resolve-Leaf $EnforcedReadiness 'Enforced readiness gate'; stand_relative_path = 'kit-tools/windows_app_control_enforced_readiness.ps1' }
)

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { Remove-Item -LiteralPath $OutputDirectory -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$tempRoot = Join-Path $env:TEMP ("ArvectumAplWin014HarnessTrust-" + [guid]::NewGuid().ToString('N'))
$scanRoot = Join-Path $tempRoot 'scan'
New-Item -ItemType Directory -Path $scanRoot -Force | Out-Null
try {
    $trustedScripts = @()
    foreach ($definition in $definitions) {
        $source = [string]$definition.source
        $name = [IO.Path]::GetFileName($source)
        $destination = Join-Path $scanRoot $name
        if (Test-Path -LiteralPath $destination) { throw "Duplicate harness script basename: $name" }
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $item = Get-Item -LiteralPath $source
        $trustedScripts += [ordered]@{
            source_path = $source
            stand_relative_path = [string]$definition.stand_relative_path
            file_name = $name
            size = [long]$item.Length
            sha256 = Hash $source
        }
    }

    if ($trustedScripts.Count -ne 4) { throw 'Exactly four acceptance scripts must be trusted.' }
    if (@($trustedScripts | Select-Object -ExpandProperty sha256 -Unique).Count -ne 4) { throw 'Harness trust inputs unexpectedly contain duplicate bytes.' }

    $xml = Join-Path $OutputDirectory 'Arvectum-APL-WIN-014-Lab-Harness-Trust.xml'

    # IMPORTANT: intentionally do NOT use -NoScript. The purpose of this policy is
    # to admit these exact PowerShell scripts so Windows PowerShell 5.1 can execute
    # them as policy-approved files under the Enforced base policy.
    New-CIPolicy -MultiplePolicyFormat -ScanPath $scanRoot -UserPEs -NoShadowCopy -FilePath $xml -Level Hash | Out-Null
    Set-CIPolicyIdInfo -FilePath $xml -ResetPolicyID -PolicyName 'Arvectum APL-WIN-014 Lab Harness Trust' -SupplementsBasePolicyID $BasePolicyId | Out-Null
    Set-RuleOption -FilePath $xml -Option 3 -Delete
    Set-CIPolicyVersion -FilePath $xml -Version '1.0.0.0'

    if (Select-String -LiteralPath $xml -Pattern 'Enabled:Audit Mode' -Quiet) { throw 'Harness supplemental contains Audit Mode.' }

    [xml]$policyXml = Get-Content -LiteralPath $xml -Raw -Encoding UTF8
    $ns = New-Object Xml.XmlNamespaceManager($policyXml.NameTable)
    $ns.AddNamespace('si','urn:schemas-microsoft-com:sipolicy')
    $policyIdNode = $policyXml.SelectSingleNode('//si:PolicyID',$ns)
    $baseIdNode = $policyXml.SelectSingleNode('//si:BasePolicyID',$ns)
    if (-not $policyIdNode -or -not $baseIdNode) { throw 'Harness supplemental XML identity is incomplete.' }
    $policyId = ([string]$policyIdNode.InnerText).Trim()
    $actualBaseId = ([string]$baseIdNode.InnerText).Trim().Trim('{}')
    if ($actualBaseId -ine $BasePolicyId.ToString('D')) { throw 'Harness supplemental targets another base policy.' }

    # Fail closed if ConfigCI produced no script-oriented rules. The XML generated
    # from the scan must contain every exact script basename; this also catches an
    # accidental future reintroduction of -NoScript.
    $xmlText = Get-Content -LiteralPath $xml -Raw -Encoding UTF8
    foreach ($script in $trustedScripts) {
        if ($xmlText -notmatch [regex]::Escape([string]$script.file_name)) {
            throw "ConfigCI policy does not contain a rule reference for harness script: $([string]$script.file_name)"
        }
    }

    $cipName = ($policyId.Trim('{}')) + '.cip'
    $cip = Join-Path $OutputDirectory $cipName
    ConvertFrom-CIPolicy -XmlFilePath $xml -BinaryFilePath $cip | Out-Null
    if (-not (Test-Path -LiteralPath $cip -PathType Leaf)) { throw 'ConfigCI did not produce harness supplemental CIP.' }

    $manifest = [ordered]@{
        schema = 'arvectum.proxy.apl-win-014-harness-trust.v1'
        task = 'APL-WIN-014'
        created_utc = [DateTime]::UtcNow.ToString('o')
        result = 'PASS'
        purpose = 'lab-harness-only'
        product_trust = $false
        promoted_release = $false
        final_acceptance_evidence = $false
        base_policy_id = $BasePolicyId.ToString('B')
        supplemental_policy_id = $policyId
        policy_name = 'Arvectum APL-WIN-014 Lab Harness Trust'
        supplemental_policy_xml = [IO.Path]::GetFileName($xml)
        supplemental_policy_cip = [IO.Path]::GetFileName($cip)
        supplemental_policy_cip_sha256 = Hash $cip
        script_scan_enabled = $true
        no_script_option_used = $false
        trusted_script_count = $trustedScripts.Count
        trusted_scripts = $trustedScripts
        invariants = @(
            'lab acceptance harness only; not product trust',
            'exact script bytes are hash-bound by generated App Control rules',
            'supplements only the dedicated APL-WIN-014 base policy',
            'supplemental contains no Enabled:Audit Mode',
            'builder never deploys/removes/changes App Control policy',
            'bootstrap deployment never changes base policy, Defender, Smart App Control, network, or product state'
        )
    }
    $manifestPath = Join-Path $OutputDirectory 'harness-trust.json'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host 'APL-WIN-014 lab harness trust build: PASS'
    Write-Host "PolicyID: $policyId"
    Write-Host "BasePolicyID: $($BasePolicyId.ToString('B'))"
    Write-Host "CIP SHA256: $(Hash $cip)"
    Write-Host "Trusted scripts: $($trustedScripts.Count)"
    Write-Host 'Product trust: FALSE'
    Write-Host 'Final acceptance evidence: FALSE'
    Write-Host 'Policy mutation: NONE'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
