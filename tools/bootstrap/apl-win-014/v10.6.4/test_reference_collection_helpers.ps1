<# Behavioral fixture tests for CLM-safe reference collection helpers. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'reference_collection_helpers.ps1')

# --- Get-ClmRelativePath tests ---
$normalFile = Get-ClmRelativePath -BasePath 'C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher' -FullPath 'C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe'
if ($normalFile -ne 'Arvectum Proxy Launcher.exe') { throw "RelativePath normal file failed: $normalFile" }

$nestedFile = Get-ClmRelativePath -BasePath 'C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher' -FullPath 'C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher\sub\file.dll'
if ($nestedFile -ne 'sub\file.dll') { throw "RelativePath nested file failed: $nestedFile" }

$spacesFile = Get-ClmRelativePath -BasePath 'C:\Test Root' -FullPath 'C:\Test Root\My Documents\file.exe'
if ($spacesFile -ne 'My Documents\file.exe') { throw "RelativePath spaces failed: $spacesFile" }

$trailingSlash = Get-ClmRelativePath -BasePath 'C:\Test Root\' -FullPath 'C:\Test Root\file.exe'
if ($trailingSlash -ne 'file.exe') { throw "RelativePath trailing slash failed: $trailingSlash" }

# --- Test-ClmPolicyOptionsValid tests ---
$passResult = $false
try { Test-ClmPolicyOptionsValid -PolicyOptions @('Enabled:Allow Supplemental Policies') -RequireSupplemental $true -PolicyLabel 'test'; $passResult = $true } catch { }
if (-not $passResult) { throw 'PolicyOptionsValid: valid enforced state should PASS.' }

$auditFailed = $false
try { Test-ClmPolicyOptionsValid -PolicyOptions @('Enabled:Allow Supplemental Policies','Enabled:Audit Mode') -RequireSupplemental $true -PolicyLabel 'test' } catch { $auditFailed = $true }
if (-not $auditFailed) { throw 'PolicyOptionsValid: Audit Mode should FAIL.' }

$missingSuppFailed = $false
try { Test-ClmPolicyOptionsValid -PolicyOptions @() -RequireSupplemental $true -PolicyLabel 'test' } catch { $missingSuppFailed = $true }
if (-not $missingSuppFailed) { throw 'PolicyOptionsValid: missing supplemental should FAIL.' }

# --- Test-ClmAuditModeRejection tests ---
$noAudit = Test-ClmAuditModeRejection -PolicyOptions @('Enabled:Allow Supplemental Policies') -PolicyLabel 'test'
if ($noAudit -ne $true) { throw 'AuditModeRejection: non-audit should PASS.' }

$auditRej = $false
try { Test-ClmAuditModeRejection -PolicyOptions @('Enabled:Audit Mode') -PolicyLabel 'test' } catch { $auditRej = $true }
if (-not $auditRej) { throw 'AuditModeRejection: Audit Mode should FAIL.' }

# --- Get-ClmOptionalRegistryValue tests ---
$presentVal = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'ProxyEnable'
if ($presentVal.present -ne $true) { throw 'OptionalRegistryValue: ProxyEnable should be present.' }

$absentVal = Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'NonExistentValue_12345'
if ($absentVal.present -ne $false) { throw 'OptionalRegistryValue: absent value should have present=false.' }
if ($null -ne $absentVal.value) { throw 'OptionalRegistryValue: absent value should have value=null.' }

# --- Get-ClmNetstatTcpListeners tests ---
$netstatPath = Join-Path $env:SystemRoot 'System32\netstat.exe'
$listenerResult = Get-ClmNetstatTcpListeners -NetstatPath $netstatPath -TargetPort 8082
if ($null -eq $listenerResult.tcp_8082_present) { throw 'NetstatTcpListeners: tcp_8082_present must not be null.' }
if ($null -eq $listenerResult.listeners) { throw 'NetstatTcpListeners: listeners must not be null.' }

# --- Get-ClmProcessEvidence tests ---
$procEvidence = Get-ClmProcessEvidence -ProcessName 'nonexistent_process_12345'
if ($procEvidence.Count -ne 0) { throw 'ProcessEvidence: nonexistent process should return empty array.' }
if (-not ($procEvidence -is [System.Array])) { throw 'ProcessEvidence: result must be an array.' }

# --- Get-ClmCodeIntegrityEvidence tests ---
$ciEvidence = Get-ClmCodeIntegrityEvidence -MaxEvents 3
if ($null -eq $ciEvidence.available) { throw 'CodeIntegrityEvidence: available must not be null.' }
if ($null -eq $ciEvidence.events) { throw 'CodeIntegrityEvidence: events must not be null.' }

# --- Compare-ClmInventory tests ---
$expectedInv = @([ordered]@{ relative_path='file.exe'; sha256='AAA'; size=100; is_pe=$true })
$liveInv = @([ordered]@{ relative_path='file.exe'; sha256='AAA'; size=100; is_pe=$true })
$compResult = Compare-ClmInventory -Expected $expectedInv -Live $liveInv
if ($compResult -ne $true) { throw 'CompareInventory: matching inventories should PASS.' }

$driftFailed = $false
$driftInv = @([ordered]@{ relative_path='file.exe'; sha256='BBB'; size=100; is_pe=$true })
try { Compare-ClmInventory -Expected $expectedInv -Live $driftInv } catch { $driftFailed = $true }
if (-not $driftFailed) { throw 'CompareInventory: hash drift should FAIL.' }

$countFailed = $false
$shortInv = @([ordered]@{ relative_path='file.exe'; sha256='AAA'; size=100; is_pe=$true }, [ordered]@{ relative_path='file2.dll'; sha256='CCC'; size=200; is_pe=$true })
try { Compare-ClmInventory -Expected $expectedInv -Live $shortInv } catch { $countFailed = $true }
if (-not $countFailed) { throw 'CompareInventory: count mismatch should FAIL.' }

# --- Policy GUID identity normalization tests ---
$baseId = 'dc1c604c-46ea-40b7-9f47-cf582b225d5e'
$bootstrapId = '8d593266-9e22-463f-b594-df9b734d02de'
if ((Convert-ClmPolicyGuidIdentity '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}') -ine $baseId) { throw 'Policy GUID normalizer did not accept braced GUID.' }
if ((Convert-ClmPolicyGuidIdentity $bootstrapId) -ine (Convert-ClmPolicyGuidIdentity '{8D593266-9E22-463F-B594-DF9B734D02DE}')) { throw 'Policy GUID normalizer did not reconcile brace/case variants.' }
foreach ($badGuid in @('{{8D593266-9E22-463F-B594-DF9B734D02DE}}', '8D593266-9E22-463F-B594-DF9B734D02DE}', '{8D593266-9E22-463F-B594-DF9B734D02DE', 'wrong GUID')) {
    $rejected = $false
    try { Convert-ClmPolicyGuidIdentity $badGuid | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Policy GUID normalizer accepted malformed input: $badGuid" }
}

# --- Test-ClmBasePolicyInvariant tests ---
$validPolicy = [ordered]@{ policy_id='{DC1C604C-46EA-40B7-9F47-CF582B225D5E}'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Test'; is_on_disk=$true; is_enforced=$true; is_authorized=$true; policy_options=@('Enabled:Allow Supplemental Policies') }
$invResult = Test-ClmBasePolicyInvariant -Policy $validPolicy -ExpectedPolicyId $baseId -ExpectedBasePolicyId "{$baseId}" -ExpectedFriendlyName 'Test'
if ($invResult -ne $true) { throw 'BasePolicyInvariant: valid policy should PASS.' }

$idFailed = $false
try { Test-ClmBasePolicyInvariant -Policy $validPolicy -ExpectedPolicyId '00000000-0000-0000-0000-000000000000' -ExpectedBasePolicyId $baseId -ExpectedFriendlyName 'Test' } catch { $idFailed = $true }
if (-not $idFailed) { throw 'BasePolicyInvariant: wrong PolicyId should FAIL.' }

$auditPolicy = [ordered]@{ policy_id=$baseId; base_policy_id=$baseId; friendly_name='Test'; is_on_disk=$true; is_enforced=$true; is_authorized=$true; policy_options=@('Enabled:Audit Mode') }
$auditInvFailed = $false
try { Test-ClmBasePolicyInvariant -Policy $auditPolicy -ExpectedPolicyId $baseId -ExpectedBasePolicyId $baseId -ExpectedFriendlyName 'Test' } catch { $auditInvFailed = $true }
if (-not $auditInvFailed) { throw 'BasePolicyInvariant: Audit Mode should FAIL.' }

Write-Host 'RESULT: PASS'
