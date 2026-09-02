<# Shared fail-closed structural validation for generated ConfigCI supplemental XML. #>
function Test-ConfigCiSupplementalXml {
    [CmdletBinding()]
    param(
        [string]$XmlPath = '',
        [string]$PolicyId = '',
        [string]$BasePolicyId = '',
        [string]$PolicyFriendlyName = '',
        [string[]]$ExpectedHashRuleFileNames = @()
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ([string]::IsNullOrWhiteSpace($XmlPath) -or -not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) { throw 'ConfigCI XML path is required and must exist.' }
    if ([string]::IsNullOrWhiteSpace($PolicyId) -or [string]::IsNullOrWhiteSpace($BasePolicyId) -or [string]::IsNullOrWhiteSpace($PolicyFriendlyName) -or $ExpectedHashRuleFileNames.Count -eq 0) { throw 'ConfigCI XML validator requires policy identity and expected hash-rule filenames.' }
    [xml]$document = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8
    $policyNodes = @($document.SelectNodes("//*[local-name()='PolicyID']") | ForEach-Object { $_.InnerText.Trim() })
    $baseNodes = @($document.SelectNodes("//*[local-name()='BasePolicyID']") | ForEach-Object { $_.InnerText.Trim() })
    if ($policyNodes.Count -ne 1 -or $policyNodes[0] -ine $PolicyId) { throw 'Generated ConfigCI XML PolicyID does not exactly match the authored PolicyID.' }
    if ($baseNodes.Count -ne 1 -or $baseNodes[0] -ine $BasePolicyId) { throw 'Generated ConfigCI XML BasePolicyID does not exactly match the canonical base.' }
    if ((Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8) -notlike "*$PolicyFriendlyName*") { throw 'Generated ConfigCI XML does not contain the expected policy friendly name.' }
    $rules = @($document.SelectNodes("//*[local-name()='Allow'][@Hash]"))
    $refs = @($document.SelectNodes("//*[local-name()='SigningScenario' and @Value='12']//*[local-name()='FileRuleRef']"))
    if ($rules.Count -ne ($ExpectedHashRuleFileNames.Count * 4) -or $refs.Count -ne $rules.Count) { throw 'Generated ConfigCI XML has an unexpected hash-rule or user-mode FileRuleRef count.' }
    $ruleIds = @()
    foreach ($rule in $rules) {
        $id = [string]$rule.GetAttribute('ID')
        $hash = [string]$rule.GetAttribute('Hash')
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($hash)) { throw 'Generated ConfigCI XML has a hash rule without ID or Hash.' }
        $ruleIds += $id
    }
    if (@($ruleIds | Select-Object -Unique).Count -ne $ruleIds.Count) { throw 'Generated ConfigCI XML has duplicate hash-rule IDs.' }
    $refIds = @($refs | ForEach-Object { [string]$_.GetAttribute('RuleID') })
    if (@($refIds | Select-Object -Unique).Count -ne $refIds.Count -or @($refIds | Where-Object { $_ -notin $ruleIds }).Count -ne 0 -or @($ruleIds | Where-Object { $_ -notin $refIds }).Count -ne 0) { throw 'Generated ConfigCI XML FileRuleRefs do not exactly bind every hash rule.' }
    foreach ($fileName in $ExpectedHashRuleFileNames) {
        $fileRules = @($rules | Where-Object { $_.GetAttribute('FriendlyName') -like "$fileName Hash *" })
        $variants = @($fileRules | ForEach-Object { $_.GetAttribute('FriendlyName').Substring($fileName.Length + 6) })
        if ($fileRules.Count -ne 4 -or @($variants | Sort-Object -Unique) -join '|' -ne 'Page Sha1|Page Sha256|Sha1|Sha256') { throw "Generated ConfigCI XML does not contain exactly four hash variants for $fileName." }
    }
    foreach ($rule in $rules) {
        $known = $false
        foreach ($fileName in $ExpectedHashRuleFileNames) { if ($rule.GetAttribute('FriendlyName') -like "$fileName Hash *") { $known = $true } }
        if (-not $known) { throw 'Generated ConfigCI XML contains an unexpected hash-rule file.' }
    }
    $signers = @($document.SelectNodes("//*[local-name()='Signers']"))
    if (@($signers | Where-Object { $_.ChildNodes.Count -ne 0 }).Count -ne 0) { throw 'Generated ConfigCI XML contains a signer-based trust path.' }
    $true
}
