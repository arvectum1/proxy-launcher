<# Shared CLM-safe, fail-closed structural validation for generated ConfigCI XML with supplemental semantics. #>
function Convert-ClmPolicyGuid {
    [CmdletBinding()]
    param([string]$Guid = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($Guid -eq '') { throw 'GUID is required.' }
    $normalized = $Guid -replace '^\{', '' -replace '\}$', ''
    if ($normalized -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') { throw "Malformed policy GUID: $Guid" }
    return ($normalized -replace '^(.*)$', { $_.Value.ToLower() })
}
function Get-ClmConfigCiRuleBaseName {
    [CmdletBinding()]
    param([string]$FriendlyName = '')
    if ($FriendlyName -match '[\\/]') { return ($FriendlyName -replace '^.*[\\/]', '') }
    return $FriendlyName
}
function Test-ConfigCiSupplementalXml {
    [CmdletBinding()]
    param(
        [string]$XmlPath = '',
        [string]$PolicyId = '',
        [string]$BasePolicyId = '',
        [string]$PolicyFriendlyName = '',
        [string]$ExpectedPolicyVersion = '',
        [string[]]$ExpectedHashRuleFileNames = @()
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($XmlPath -eq '' -or -not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) { throw 'ConfigCI XML path is required and must exist.' }
    if ($PolicyId -eq '' -or $BasePolicyId -eq '' -or $PolicyFriendlyName -eq '' -or $ExpectedHashRuleFileNames.Count -eq 0) { throw 'ConfigCI XML validator requires policy identity and expected hash-rule filenames.' }
    $lines = @(Get-Content -LiteralPath $XmlPath -Encoding UTF8)
    $policyIds = @($lines | Where-Object { $_ -match '<PolicyID>\s*([^<\s]+)\s*</PolicyID>' } | ForEach-Object { Convert-ClmPolicyGuid $matches[1] })
    $baseIds = @($lines | Where-Object { $_ -match '<BasePolicyID>\s*([^<\s]+)\s*</BasePolicyID>' } | ForEach-Object { Convert-ClmPolicyGuid $matches[1] })
    $normalizedPolicyId = Convert-ClmPolicyGuid $PolicyId
    $normalizedBaseId = Convert-ClmPolicyGuid $BasePolicyId
    if ($policyIds.Count -ne 1 -or $policyIds[0] -ne $normalizedPolicyId) { throw 'Generated ConfigCI XML PolicyID does not exactly match the authored PolicyID.' }
    if ($baseIds.Count -ne 1 -or $baseIds[0] -ne $normalizedBaseId) { throw 'Generated ConfigCI XML BasePolicyID does not exactly match the canonical base.' }
    if ($policyIds[0] -ceq $baseIds[0]) { throw 'Generated ConfigCI XML PolicyID and BasePolicyID must differ for a supplemental policy.' }
    $hasSettings = $false
    foreach ($line in $lines) { if ($line -match '<Settings>') { $hasSettings = $true } }
    if (-not $hasSettings) { throw 'Generated ConfigCI XML is missing the Settings element required by multiple-policy format.' }
    $hasUserSigningScenario = $false
    foreach ($line in $lines) { if ($line -match '<SigningScenario\s+[^>]*Value="12"') { $hasUserSigningScenario = $true } }
    if (-not $hasUserSigningScenario) { throw 'Generated ConfigCI XML is missing user-mode SigningScenario Value=12.' }
    if (@($lines | Where-Object { $_ -like "*$PolicyFriendlyName*" }).Count -eq 0) { throw 'Generated ConfigCI XML does not contain the expected policy friendly name.' }
    if ($ExpectedPolicyVersion -ne '' -and @($lines | Where-Object { $_ -match '<VersionEx>\s*([^<\s]+)\s*</VersionEx>' -and $matches[1] -eq $ExpectedPolicyVersion }).Count -ne 1) { throw 'Generated ConfigCI XML does not contain the expected policy version.' }
    $rules = @($lines | Where-Object { $_ -match '<Allow\s+[^>]*\bID="[^"]+"[^>]*\bFriendlyName="[^"]+"[^>]*\bHash="[^"]+"' })
    $refs = @()
    $allRefs = @()
    $inUserScenario = $false
    foreach ($line in $lines) {
        if ($line -match '<SigningScenario\b[^>]*\bValue="12"') { $inUserScenario = $true }
        if ($line -match '<FileRuleRef\s+RuleID="([^"]+)"') { $allRefs += $matches[1]; if ($inUserScenario) { $refs += $matches[1] } }
        if ($line -match '</SigningScenario>') { $inUserScenario = $false }
    }
    if ($rules.Count -ne ($ExpectedHashRuleFileNames.Count * 4) -or $refs.Count -ne $rules.Count -or $allRefs.Count -ne $refs.Count) { throw 'Generated ConfigCI XML has an unexpected hash-rule or user-mode FileRuleRef count.' }
    $ruleIds = @()
    $ruleNames = @()
    $ruleBaseNames = @()
    foreach ($rule in $rules) {
        if ($rule -notmatch '\bID="([^"]+)"') { throw 'Generated ConfigCI XML has a hash rule without ID.' }
        $ruleIds += $matches[1]
        if ($rule -notmatch '\bFriendlyName="([^"]+)"') { throw 'Generated ConfigCI XML has a hash rule without FriendlyName.' }
        $rawName = $matches[1]
        $ruleNames += $rawName
        $ruleBaseNames += Get-ClmConfigCiRuleBaseName $rawName
    }
    if (@($ruleIds | Sort-Object -Unique).Count -ne $ruleIds.Count -or @($refs | Sort-Object -Unique).Count -ne $refs.Count -or @($refs | Where-Object { $_ -notin $ruleIds }).Count -ne 0 -or @($ruleIds | Where-Object { $_ -notin $refs }).Count -ne 0) { throw 'Generated ConfigCI XML FileRuleRefs do not exactly bind every hash rule.' }
    foreach ($fileName in $ExpectedHashRuleFileNames) {
        $variants = @($ruleBaseNames | Where-Object { $_ -like "$fileName Hash *" } | ForEach-Object { $_ -replace '^.* Hash ', '' } | Sort-Object -Unique)
        if ($variants.Count -ne 4 -or @($variants | Where-Object { $_ -notin @('Sha1', 'Sha256', 'Page Sha1', 'Page Sha256') }).Count -ne 0) { throw "Generated ConfigCI XML does not contain exactly four hash variants for $fileName." }
    }
    if (@($ruleBaseNames | Where-Object { $known = $false; foreach ($fileName in $ExpectedHashRuleFileNames) { if ($_ -like "$fileName Hash *") { $known = $true } }; -not $known }).Count -ne 0) { throw 'Generated ConfigCI XML contains an unexpected hash-rule file.' }
    if (@($lines | Where-Object { $_ -match '<Signer\b|<CertRoot\b|<CertPublisher\b' }).Count -ne 0) { throw 'Generated ConfigCI XML contains a signer-based trust path.' }
    $true
}
