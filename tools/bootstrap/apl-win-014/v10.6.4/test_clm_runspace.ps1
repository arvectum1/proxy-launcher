<# Executes actual production helpers in Windows PowerShell 5.1 ConstrainedLanguage runspace. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$initialState.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage
$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
$runspace.Open()

function Invoke-InConstrainedLanguage {
    param([string]$Description = '', [string]$Script = '')
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript($Script) | Out-Null
    $output = $ps.Invoke()
    $hadErrors = $ps.HadErrors
    $errorMessages = @()
    foreach ($err in $ps.Streams.Error) { $errorMessages += $err.Exception.Message }
    $ps.Dispose()
    if ($hadErrors) {
        foreach ($msg in $errorMessages) {
            if ($msg -match 'MethodInvocationNotSupportedInConstrainedLanguage') { throw "CLM VIOLATION in $Description : $msg" }
        }
        throw "FAILED in $Description : $($errorMessages -join '; ')"
    }
    Write-Host "  PASS: $Description"
}

$helpers = (Join-Path $scriptDir 'reference_collection_helpers.ps1') -replace "'","''"
$validator = (Join-Path $scriptDir 'configci_xml_validation.ps1') -replace "'","''"
$checksum = (Join-Path $scriptDir 'checksum_validation.ps1') -replace "'","''"
$fixtureXml = (Join-Path (Join-Path $scriptDir 'fixtures') 'configci_real_xml_structure.xml') -replace "'","''"
$goodChecksum = (Join-Path (Join-Path $scriptDir 'fixtures') 'sha256sums_reference_capture.txt') -replace "'","''"
$badChecksum = (Join-Path (Join-Path $scriptDir 'fixtures') 'sha256sums_malformed.txt') -replace "'","''"

$tempDir = Join-Path $env:TEMP ("clm-test-" + (Get-Date -Format 'yyyyMMddHHmmss'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tempDir 'nested') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $tempDir 'file1.txt') -Value 'test content' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $tempDir 'nested\file2.dll') -Value 'dll content' -Encoding ASCII
$tempDirEsc = $tempDir -replace "'","''"

$tempUnins = Join-Path $env:TEMP ("clm-unins-" + (Get-Date -Format 'yyyyMMddHHmmss'))
New-Item -ItemType Directory -Path $tempUnins -Force | Out-Null
Set-Content -LiteralPath (Join-Path $tempUnins 'unins000.exe') -Value 'unins content' -Encoding ASCII
$tempUninsEsc = $tempUnins -replace "'","''"

$tempUninsZero = Join-Path $env:TEMP ("clm-unins-zero-" + (Get-Date -Format 'yyyyMMddHHmmss'))
New-Item -ItemType Directory -Path $tempUninsZero -Force | Out-Null
$tempUninsZeroEsc = $tempUninsZero -replace "'","''"

$tempUninsTwo = Join-Path $env:TEMP ("clm-unins-two-" + (Get-Date -Format 'yyyyMMddHHmmss'))
New-Item -ItemType Directory -Path $tempUninsTwo -Force | Out-Null
Set-Content -LiteralPath (Join-Path $tempUninsTwo 'unins000.exe') -Value 'a' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $tempUninsTwo 'unins001.exe') -Value 'b' -Encoding ASCII
$tempUninsTwoEsc = $tempUninsTwo -replace "'","''"

Write-Host 'CLM RUNSPACE TEST: A. ConfigCI validator'
Invoke-InConstrainedLanguage -Description 'Test-ConfigCiSupplementalXml' -Script ". '$validator'; Test-ConfigCiSupplementalXml -XmlPath '$fixtureXml' -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null"
$pathQualifiedFixture = (Join-Path (Join-Path $scriptDir 'fixtures') 'configci_real_path_qualified.xml') -replace "'","''"
Invoke-InConstrainedLanguage -Description 'Test-ConfigCiSupplementalXml (path-qualified)' -Script ". '$validator'; Test-ConfigCiSupplementalXml -XmlPath '$pathQualifiedFixture' -PolicyId '{8B2309ED-EA37-4ABD-86D3-760ACC499274}' -BasePolicyId '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe') | Out-Null"
$pathQualifiedBadXml = (Join-Path (Join-Path $scriptDir 'fixtures') 'configci_real_path_qualified_wrong_leaf.xml') -replace "'","''"
$pathQualifiedBadFailed = $false
try { Invoke-InConstrainedLanguage -Description 'Test-ConfigCiSupplementalXml (path-qualified wrong leaf)' -Script ". '$validator'; Test-ConfigCiSupplementalXml -XmlPath '$pathQualifiedBadXml' -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe')" } catch { $pathQualifiedBadFailed = $true }
if (-not $pathQualifiedBadFailed) { throw 'Path-qualified wrong leaf should fail in CLM.' }
Write-Host '  PASS: path-qualified wrong leaf rejected in CLM'

Write-Host 'CLM RUNSPACE TEST: B. Checksum parser'
Invoke-InConstrainedLanguage -Description 'Get-ChecksumEvidenceHash (valid)' -Script ". '$checksum'; Get-ChecksumEvidenceHash -ChecksumPath '$goodChecksum' -ExpectedFileName 'reference-capture.json' | Out-Null"
$badFailedInClm = $false
try { Invoke-InConstrainedLanguage -Description 'Get-ChecksumEvidenceHash (malformed)' -Script ". '$checksum'; Get-ChecksumEvidenceHash -ChecksumPath '$badChecksum' -ExpectedFileName 'reference-capture.json'" } catch { $badFailedInClm = $true }
if (-not $badFailedInClm) { throw 'Checksum parser should reject malformed input in CLM.' }
Write-Host '  PASS: Get-ChecksumEvidenceHash (malformed rejected)'

Write-Host 'CLM RUNSPACE TEST: C. Relative path construction'
Invoke-InConstrainedLanguage -Description 'Get-ClmRelativePath' -Script ". '$helpers'; Get-ClmRelativePath -BasePath 'C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher' -FullPath 'C:\Users\ARVECTUM-DEMO\Documents\ArvectumProxyLauncher\Arvectum Proxy Launcher.exe' | Out-Null"
Invoke-InConstrainedLanguage -Description 'Get-ClmRelativePath nested' -Script ". '$helpers'; Get-ClmRelativePath -BasePath 'C:\Root' -FullPath 'C:\Root\sub\file.dll' | Out-Null"

Write-Host 'CLM RUNSPACE TEST: D. Policy option validation'
Invoke-InConstrainedLanguage -Description 'Test-ClmPolicyOptionsValid (pass)' -Script ". '$helpers'; Test-ClmPolicyOptionsValid -PolicyOptions @('Enabled:Allow Supplemental Policies') -RequireSupplemental `$true -PolicyLabel 'test' | Out-Null"
$auditFailedInClm = $false
try { Invoke-InConstrainedLanguage -Description 'Test-ClmPolicyOptionsValid (audit mode)' -Script ". '$helpers'; Test-ClmPolicyOptionsValid -PolicyOptions @('Enabled:Audit Mode') -RequireSupplemental `$true -PolicyLabel 'test'" } catch { $auditFailedInClm = $true }
if (-not $auditFailedInClm) { throw 'Audit Mode should fail in CLM.' }
Write-Host '  PASS: Test-ClmPolicyOptionsValid (audit mode rejected)'

Write-Host 'CLM RUNSPACE TEST: E. Audit Mode rejection'
Invoke-InConstrainedLanguage -Description 'Test-ClmAuditModeRejection (pass)' -Script ". '$helpers'; Test-ClmAuditModeRejection -PolicyOptions @('Enabled:Allow Supplemental Policies') -PolicyLabel 'test' | Out-Null"
$auditRejClm = $false
try { Invoke-InConstrainedLanguage -Description 'Test-ClmAuditModeRejection (fail)' -Script ". '$helpers'; Test-ClmAuditModeRejection -PolicyOptions @('Enabled:Audit Mode') -PolicyLabel 'test'" } catch { $auditRejClm = $true }
if (-not $auditRejClm) { throw 'Audit Mode rejection should fail in CLM.' }
Write-Host '  PASS: Test-ClmAuditModeRejection (audit mode rejected)'

Write-Host 'CLM RUNSPACE TEST: F. Inventory normalization'
Invoke-InConstrainedLanguage -Description 'Compare-ClmInventory (match)' -Script ". '$helpers'; Compare-ClmInventory -Expected @([ordered]@{ relative_path='a.exe'; sha256='AAA'; size=100; is_pe=`$true }) -Live @([ordered]@{ relative_path='a.exe'; sha256='AAA'; size=100; is_pe=`$true }) | Out-Null"
$driftClm = $false
try { Invoke-InConstrainedLanguage -Description 'Compare-ClmInventory (drift)' -Script ". '$helpers'; Compare-ClmInventory -Expected @([ordered]@{ relative_path='a.exe'; sha256='AAA'; size=100; is_pe=`$true }) -Live @([ordered]@{ relative_path='a.exe'; sha256='BBB'; size=100; is_pe=`$true })" } catch { $driftClm = $true }
if (-not $driftClm) { throw 'Inventory drift should fail in CLM.' }
Write-Host '  PASS: Compare-ClmInventory (drift rejected)'

Write-Host 'CLM RUNSPACE TEST: G. Optional registry value'
Invoke-InConstrainedLanguage -Description 'Get-ClmOptionalRegistryValue (present)' -Script ". '$helpers'; Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'ProxyEnable' | Out-Null"
Invoke-InConstrainedLanguage -Description 'Get-ClmOptionalRegistryValue (absent)' -Script ". '$helpers'; Get-ClmOptionalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName 'NonExistent_99999' | Out-Null"

Write-Host 'CLM RUNSPACE TEST: H. Netstat TCP listener parser'
Invoke-InConstrainedLanguage -Description 'Get-ClmNetstatTcpListeners' -Script ". '$helpers'; Get-ClmNetstatTcpListeners -NetstatPath (Join-Path `$env:SystemRoot 'System32\netstat.exe') -TargetPort 8082 | Out-Null"

Write-Host 'CLM RUNSPACE TEST: I. Process evidence normalization'
Invoke-InConstrainedLanguage -Description 'Get-ClmProcessEvidence (empty)' -Script ". '$helpers'; Get-ClmProcessEvidence -ProcessName 'nonexistent_process_xyz' | Out-Null"

Write-Host 'CLM RUNSPACE TEST: J. Code Integrity evidence'
Invoke-InConstrainedLanguage -Description 'Get-ClmCodeIntegrityEvidence' -Script ". '$helpers'; Get-ClmCodeIntegrityEvidence -MaxEvents 2 | Out-Null"

Write-Host 'CLM RUNSPACE TEST: K. Base policy invariant'
Invoke-InConstrainedLanguage -Description 'Test-ClmBasePolicyInvariant (pass)' -Script ". '$helpers'; Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=`$true; is_enforced=`$true; is_authorized=`$true; policy_options=@('Enabled:Allow Supplemental Policies') }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base' | Out-Null"
$auditInvClm = $false
try { Invoke-InConstrainedLanguage -Description 'Test-ClmBasePolicyInvariant (audit)' -Script ". '$helpers'; Test-ClmBasePolicyInvariant -Policy ([ordered]@{ policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; base_policy_id='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; friendly_name='Arvectum APL-WIN-014 Lab Base'; is_on_disk=`$true; is_enforced=`$true; is_authorized=`$true; policy_options=@('Enabled:Audit Mode') }) -ExpectedPolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedFriendlyName 'Arvectum APL-WIN-014 Lab Base'" } catch { $auditInvClm = $true }
if (-not $auditInvClm) { throw 'Audit Mode invariant should fail in CLM.' }
Write-Host '  PASS: Test-ClmBasePolicyInvariant (audit mode rejected)'

Write-Host 'CLM RUNSPACE TEST: L. Get-ClmLiveInventory'
Invoke-InConstrainedLanguage -Description 'Get-ClmLiveInventory' -Script ". '$helpers'; `$inv = Get-ClmLiveInventory -InstallRoot '$tempDirEsc'; if (`$inv.Count -ne 2) { throw ('expected 2 files got {0}' -f `$inv.Count) }; `$r1 = @(`$inv | Where-Object { `$_.relative_path -eq 'file1.txt' }); `$r2 = @(`$inv | Where-Object { `$_.relative_path -eq 'nested\file2.dll' }); if (`$r1.Count -ne 1) { throw 'file1.txt not found' }; if (`$r2.Count -ne 1) { throw 'nested\file2.dll not found' }; if (`$r1[0].sha256 -eq '') { throw 'empty sha256' }; if (`$r2[0].is_pe -ne `$true) { throw 'dll not PE' }; if (`$r1[0].is_pe -ne `$false) { throw 'txt is PE' }"

Write-Host 'CLM RUNSPACE TEST: M. Get-ClmUninstallerEvidence'
Invoke-InConstrainedLanguage -Description 'Get-ClmUninstallerEvidence (single)' -Script ". '$helpers'; `$u = Get-ClmUninstallerEvidence -InstallRoot '$tempUninsEsc'; if (`$u.filename -ne 'unins000.exe') { throw ('filename: {0}' -f `$u.filename) }; if (`$u.sha256 -eq '') { throw 'empty sha256' }; if (`$u.size -le 0) { throw ('size: {0}' -f `$u.size) }"
$zeroUninsFailed = $false
try { Invoke-InConstrainedLanguage -Description 'Get-ClmUninstallerEvidence (zero)' -Script ". '$helpers'; Get-ClmUninstallerEvidence -InstallRoot '$tempUninsZeroEsc'" } catch { $zeroUninsFailed = $true }
if (-not $zeroUninsFailed) { throw 'Zero uninstallers should fail in CLM.' }
Write-Host '  PASS: Get-ClmUninstallerEvidence (zero rejected)'
$twoUninsFailed = $false
try { Invoke-InConstrainedLanguage -Description 'Get-ClmUninstallerEvidence (two)' -Script ". '$helpers'; Get-ClmUninstallerEvidence -InstallRoot '$tempUninsTwoEsc'" } catch { $twoUninsFailed = $true }
if (-not $twoUninsFailed) { throw 'Two uninstallers should fail in CLM.' }
Write-Host '  PASS: Get-ClmUninstallerEvidence (two rejected)'

Write-Host 'CLM RUNSPACE TEST: N. Resolve-ClmPolicyEvidence (pure validation)'
Invoke-InConstrainedLanguage -Description 'Resolve-ClmPolicyEvidence (pass)' -Script ". '$helpers'; `$fake = [ordered]@{ OperationResult=0; Policies=@([ordered]@{ PolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='Arvectum APL-WIN-014 Lab Base'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }, [ordered]@{ PolicyID='test-bootstrap-id'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'; Version='10.0.0.17'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@() }) }; Resolve-ClmPolicyEvidence -CiToolResult `$fake -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -ExpectedBootstrapPolicyId 'test-bootstrap-id' -ExpectedBootstrapFriendlyName 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap' | Out-Null"
$wrongNameFailed = $false
try { Invoke-InConstrainedLanguage -Description 'Resolve-ClmPolicyEvidence (wrong name)' -Script ". '$helpers'; `$fake = [ordered]@{ OperationResult=0; Policies=@([ordered]@{ PolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='Arvectum APL-WIN-014 Lab Base'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }, [ordered]@{ PolicyID='test-bootstrap-id'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='WRONG NAME'; Version='10.0.0.17'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@() }) }; Resolve-ClmPolicyEvidence -CiToolResult `$fake -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -ExpectedBootstrapPolicyId 'test-bootstrap-id' -ExpectedBootstrapFriendlyName 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'" } catch { $wrongNameFailed = $true }
if (-not $wrongNameFailed) { throw 'Wrong bootstrap FriendlyName should fail in CLM.' }
Write-Host '  PASS: Resolve-ClmPolicyEvidence (wrong name rejected)'
$wrongBaseFailed = $false
try { Invoke-InConstrainedLanguage -Description 'Resolve-ClmPolicyEvidence (wrong base)' -Script ". '$helpers'; `$fake = [ordered]@{ OperationResult=0; Policies=@([ordered]@{ PolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='Arvectum APL-WIN-014 Lab Base'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }, [ordered]@{ PolicyID='test-bootstrap-id'; BasePolicyID='00000000-0000-0000-0000-000000000000'; FriendlyName='Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'; Version='10.0.0.17'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@() }) }; Resolve-ClmPolicyEvidence -CiToolResult `$fake -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -ExpectedBootstrapPolicyId 'test-bootstrap-id' -ExpectedBootstrapFriendlyName 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'" } catch { $wrongBaseFailed = $true }
if (-not $wrongBaseFailed) { throw 'Wrong bootstrap BasePolicyID should fail in CLM.' }
Write-Host '  PASS: Resolve-ClmPolicyEvidence (wrong base rejected)'
$baseOnlyFailed = $false
try { Invoke-InConstrainedLanguage -Description 'Resolve-ClmPolicyEvidence (base-only no bootstrap)' -Script ". '$helpers'; `$fake = [ordered]@{ OperationResult=0; Policies=@([ordered]@{ PolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='Arvectum APL-WIN-014 Lab Base'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }; Resolve-ClmPolicyEvidence -CiToolResult `$fake -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -RequireBootstrap `$true -ExpectedBootstrapPolicyId 'missing-id' -ExpectedBootstrapFriendlyName 'Arvectum APL-WIN-014 Harness V10.6.4 Bootstrap'" } catch { $baseOnlyFailed = $true }
if (-not $baseOnlyFailed) { throw 'RequireBootstrap=true with missing bootstrap should fail in CLM.' }
Write-Host '  PASS: Resolve-ClmPolicyEvidence (missing bootstrap rejected)'
Invoke-InConstrainedLanguage -Description 'Resolve-ClmPolicyEvidence (base-only pass)' -Script ". '$helpers'; `$fake = [ordered]@{ OperationResult=0; Policies=@([ordered]@{ PolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; BasePolicyID='dc1c604c-46ea-40b7-9f47-cf582b225d5e'; FriendlyName='Arvectum APL-WIN-014 Lab Base'; IsOnDisk=`$true; IsEnforced=`$true; IsAuthorized=`$true; PolicyOptions=@('Enabled:Allow Supplemental Policies') }) }; Resolve-ClmPolicyEvidence -CiToolResult `$fake -ExpectedBasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -ExpectedBaseFriendlyName 'Arvectum APL-WIN-014 Lab Base' -RequireBootstrap `$false | Out-Null"

Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempUnins -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempUninsZero -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempUninsTwo -Recurse -Force -ErrorAction SilentlyContinue

$runspace.Close()
$runspace.Dispose()
Write-Host 'RESULT: PASS'
