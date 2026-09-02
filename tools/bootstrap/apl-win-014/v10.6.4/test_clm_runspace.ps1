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

$validator = (Join-Path $scriptDir 'configci_xml_validation.ps1') -replace "'","''"
$checksum = (Join-Path $scriptDir 'checksum_validation.ps1') -replace "'","''"
$helpers = (Join-Path $scriptDir 'reference_collection_helpers.ps1') -replace "'","''"
$fixtureXml = (Join-Path (Join-Path $scriptDir 'fixtures') 'configci_real_xml_structure.xml') -replace "'","''"
$goodChecksum = (Join-Path (Join-Path $scriptDir 'fixtures') 'sha256sums_reference_capture.txt') -replace "'","''"
$badChecksum = (Join-Path (Join-Path $scriptDir 'fixtures') 'sha256sums_malformed.txt') -replace "'","''"

Write-Host 'CLM RUNSPACE TEST: A. ConfigCI validator'
Invoke-InConstrainedLanguage -Description 'Test-ConfigCiSupplementalXml' -Script ". '$validator'; Test-ConfigCiSupplementalXml -XmlPath '$fixtureXml' -PolicyId '{11111111-1111-1111-1111-111111111111}' -BasePolicyId 'dc1c604c-46ea-40b7-9f47-cf582b225d5e' -PolicyFriendlyName 'Arvectum APL-WIN-014 Fixture' -ExpectedHashRuleFileNames @('Arvectum Proxy Launcher.exe', 'Arvectum-Proxy-Launcher-setup.exe') | Out-Null"

Write-Host 'CLM RUNSPACE TEST: B. Checksum parser'
Invoke-InConstrainedLanguage -Description 'Get-ChecksumEvidenceHash (valid)' -Script ". '$checksum'; Get-ChecksumEvidenceHash -ChecksumPath '$goodChecksum' -ExpectedFileName 'reference-capture.json' | Out-Null"
$badFailedInClm = $false
try {
    Invoke-InConstrainedLanguage -Description 'Get-ChecksumEvidenceHash (malformed)' -Script ". '$checksum'; Get-ChecksumEvidenceHash -ChecksumPath '$badChecksum' -ExpectedFileName 'reference-capture.json'"
} catch { $badFailedInClm = $true }
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

$runspace.Close()
$runspace.Dispose()
Write-Host 'RESULT: PASS'
