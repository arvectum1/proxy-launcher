<#
.SYNOPSIS
    Guarded ARVECTUM-DEMO driver for the post-incident APL-WIN-014 static-runtime candidate.
.DESCRIPTION
    Modes:
      Preflight - verifies the complete stand kit, exact current connectivity, dedicated
                  App Control state, and prepares (but never deploys) an Enforced copy of
                  the dedicated base when the base is still Audit.
      Execute   - deploys the rehearsal-only provisional supplemental, ensures the dedicated
                  base is Enforced, proves a new PowerShell child is ConstrainedLanguage,
                  proves native recovery is executable in verify-only mode BEFORE any network
                  mutation, then performs real historical 0.2.2 -> exact candidate upgrade,
                  fresh install/repair/uninstall, and a real native recovery rehearsal.
      Recover   - never changes App Control. It invokes the exact native recovery executable
                  from this kit using the most recent durable backup.

    Security invariants:
      * never disables/removes/weakens App Control, Smart App Control, or Defender;
      * never restores Audit after Enforced;
      * never removes any supplemental policy;
      * destructive lifecycle cannot begin until native recovery PREARM passes under Enforced;
      * recovery does not depend on PowerShell language mode;
      * exact historical/current/candidate bytes are hash-bound by the stand kit and policy.
#>
[CmdletBinding()]
param(
    [ValidateSet('Preflight','Execute','Recover')]
    [string]$Mode = 'Preflight',
    [string]$RecoveryBackupDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BasePolicyId = [Guid]'DC1C604C-46EA-40B7-9F47-CF582B225D5E'
$HistoricalSupplementalPolicyId = [Guid]'EE6C778F-0FC2-4D9B-ACA9-2FA8463D3624'
$Sealed023SupplementalPolicyId = [Guid]'C3B6C04A-0C15-4486-A2CE-8490DD286B2C'
$ExpectedAuditBaseCipSha256 = 'b730c6f0ce38847d1e096c3646a37ec706956fb57ecf59a11d593c88fa4380fb'
$ExpectedSealed023AppSha256 = 'f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a'
$ExpectedHistorical022AppSha256 = '7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0'
$PacUrl = 'http://127.0.0.1:8082/proxy.pac'

$KitRoot = Split-Path -Parent $PSCommandPath
$KitManifestPath = Join-Path $KitRoot 'stand-kit.json'
$CandidateRoot = Join-Path $KitRoot 'candidate'
$ProvisionalRoot = Join-Path $KitRoot 'provisional'
$HistoricalRoot = Join-Path $KitRoot 'historical-0.2.2-p0.4'
$NormalEvidencePath = Join-Path $KitRoot 'evidence\windows-appcontrol-candidate-e2e.json'

$InstallRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ArvectumProxyLauncher'
$Sealed023Exe = Join-Path $InstallRoot 'Arvectum Proxy Launcher.exe'
$StateRoot = Join-Path $env:LOCALAPPDATA 'Arvectum\ProxyLauncher'
$EvidenceRoot = 'C:\Arvectum\Evidence\APL-WIN-014'
$RecoveryRoot = 'C:\Arvectum\StandKit\APL-WIN-014\appcontrol-candidate-backup'
$RecoveryPointerPath = Join-Path $RecoveryRoot 'latest-recovery.json'
$PreflightEvidencePath = Join-Path $EvidenceRoot 'apl-win-014-appcontrol-candidate-preflight.json'
$EnforcedEvidencePath = Join-Path $EvidenceRoot 'apl-win-014-enforced-lifecycle.json'
$RecoveryEvidencePath = Join-Path $EvidenceRoot 'apl-win-014-native-recovery-rehearsal.json'
$ResultEvidencePath = Join-Path $EvidenceRoot 'apl-win-014-appcontrol-candidate-result.json'
$TranscriptPath = Join-Path $EvidenceRoot 'apl-win-014-appcontrol-candidate-transcript.txt'

$BaseXml = 'C:\Arvectum\AppControl\APL-WIN-014\Base\Arvectum-APL-WIN-014-Lab-Base.xml'
$BaseAuditCip = 'C:\Arvectum\AppControl\APL-WIN-014\Base\{DC1C604C-46EA-40B7-9F47-CF582B225D5E}.cip'
$EnforcedDirectory = 'C:\Arvectum\AppControl\APL-WIN-014\Enforced'
$EnforcedXml = Join-Path $EnforcedDirectory 'Arvectum-APL-WIN-014-Lab-Base-Enforced.xml'
$EnforcedCip = Join-Path $EnforcedDirectory '{DC1C604C-46EA-40B7-9F47-CF582B225D5E}.cip'

function Normalize-GuidText([object]$Value) {
    if ($null -eq $Value) { return '' }
    $text = ([string]$Value).Trim().Trim('{}')
    try { return ([Guid]$text).ToString('D').ToLowerInvariant() } catch { return $text.ToLowerInvariant() }
}

function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $($_.Exception.Message)" }
}

function Write-Json([object]$Value, [string]$Path, [int]$Depth = 14) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-AdminHostAndTools {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if ($env:COMPUTERNAME -ne 'ARVECTUM-DEMO') { throw "SAFETY BLOCK: expected ARVECTUM-DEMO, detected $env:COMPUTERNAME." }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Elevated Administrator PowerShell is required.' }
    foreach ($cmdlet in @('Set-RuleOption','Set-CIPolicyVersion','ConvertFrom-CIPolicy')) {
        if (-not (Get-Command $cmdlet -ErrorAction SilentlyContinue)) { throw "Required ConfigCI cmdlet is missing: $cmdlet" }
    }
    $ciTool = Join-Path $env:SystemRoot 'System32\CiTool.exe'
    if (-not (Test-Path -LiteralPath $ciTool -PathType Leaf)) { throw 'CiTool.exe is required.' }
    [pscustomobject]@{ citool = $ciTool; computer = $env:COMPUTERNAME }
}

function Assert-KitIntegrity {
    $manifest = Read-Json $KitManifestPath 'stand-kit manifest'
    if ([string]$manifest.schema -ne 'arvectum.proxy.apl-win-014-stand-kit.v1' -or [string]$manifest.result -ne 'PASS') {
        throw 'SAFETY BLOCK: unsupported/non-PASS stand-kit manifest.'
    }
    if ([string]$manifest.version -ne '0.2.4') { throw "SAFETY BLOCK: expected candidate 0.2.4, kit contains $([string]$manifest.version)." }
    foreach ($file in @($manifest.files)) {
        $relative = [string]$file.relative_path
        if (-not $relative -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) {
            throw "SAFETY BLOCK: invalid stand-kit path in manifest: $relative"
        }
        $path = Join-Path $KitRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "SAFETY BLOCK: stand-kit file missing: $relative" }
        $item = Get-Item -LiteralPath $path
        if ([long]$item.Length -ne [long]$file.size) { throw "SAFETY BLOCK: stand-kit size mismatch: $relative" }
        if ((Hash $path) -ne ([string]$file.sha256).ToLowerInvariant()) { throw "SAFETY BLOCK: stand-kit SHA256 mismatch: $relative" }
    }
    $manifest
}

function Resolve-CandidateInputs {
    $bundlePath = Join-Path $CandidateRoot 'enterprise-bundle.json'
    $bundle = Read-Json $bundlePath 'enterprise bundle manifest'
    if ([string]$bundle.schema -ne 'arvectum.proxy.windows-app-control-enterprise-bundle.v1' -or [string]$bundle.result -ne 'PASS') { throw 'Candidate enterprise bundle is invalid.' }
    if ([string]$bundle.version -ne '0.2.4' -or [string]$bundle.candidate_label -ne '0.2.4-appcontrol-candidate') { throw 'Candidate release identity is not exact 0.2.4-appcontrol-candidate.' }
    if (-not [bool]$bundle.static_runtime -or [bool]$bundle.pyinstaller_onefile) { throw 'Candidate must be static-runtime and not onefile.' }
    if ([string]$bundle.setup_loader -ne 'disabled' -or [bool]$bundle.setup_runs_from_temp) { throw 'Candidate must use UseSetupLdr=no and never re-execute Setup from TEMP.' }

    $setupDir = Join-Path $CandidateRoot 'setup'
    $setup = @(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.exe' -ErrorAction Stop)
    $bins = @(Get-ChildItem -LiteralPath $setupDir -File -Filter '*.bin' -ErrorAction Stop)
    if ($setup.Count -ne 1 -or $bins.Count -lt 1) { throw 'Candidate multi-file Setup bundle is incomplete.' }

    $rescueRoot = Join-Path $CandidateRoot 'rescue-runtime'
    $runtimeManifestPath = Join-Path $rescueRoot 'static-runtime.json'
    $runtime = Read-Json $runtimeManifestPath 'static runtime manifest'
    if ([string]$runtime.result -ne 'PASS' -or [bool]$runtime.pyinstaller_onefile -or -not [bool]$runtime.runtime_complete) { throw 'Static runtime manifest is invalid.' }
    $rescueEntry = Join-Path $rescueRoot 'Arvectum Proxy Launcher.exe'
    if ((Hash $rescueEntry) -ne ([string]$runtime.entry_sha256).ToLowerInvariant()) { throw 'Rescue runtime entry hash mismatch.' }
    foreach ($file in @($runtime.files)) {
        $path = Join-Path $rescueRoot ([string]$file.relative_path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Rescue runtime file missing: $([string]$file.relative_path)" }
        if ([long](Get-Item -LiteralPath $path).Length -ne [long]$file.size -or (Hash $path) -ne ([string]$file.sha256).ToLowerInvariant()) {
            throw "Rescue runtime exact-byte mismatch: $([string]$file.relative_path)"
        }
    }

    $recoveryExe = Join-Path $CandidateRoot 'recovery\Arvectum Proxy Launcher Recovery.exe'
    if ((Hash $recoveryExe) -ne ([string]$bundle.native_recovery_sha256).ToLowerInvariant()) { throw 'Native recovery hash mismatch.' }

    $provisionalPath = Join-Path $ProvisionalRoot 'provisional-trust-pack.json'
    $provisional = Read-Json $provisionalPath 'provisional trust manifest'
    if ([string]$provisional.schema -ne 'arvectum.proxy.windows-app-control-provisional-trust-pack.v1' -or [string]$provisional.result -ne 'PASS') { throw 'Provisional trust manifest is invalid.' }
    if ([string]$provisional.purpose -ne 'rehearsal-only' -or [bool]$provisional.final_acceptance_evidence -or [bool]$provisional.enforced_lifecycle_ready) { throw 'Provisional trust manifest illegally claims final readiness.' }
    if ((Normalize-GuidText $provisional.base_policy_id) -ne (Normalize-GuidText $BasePolicyId)) { throw 'Provisional supplemental targets another base.' }
    if ([string]$provisional.enterprise_bundle_manifest_sha256 -ne (Hash $bundlePath)) { throw 'Provisional trust is not bound to this enterprise bundle.' }
    if ([string]$provisional.setup_exe_sha256 -ne (Hash $setup[0].FullName)) { throw 'Provisional trust Setup hash mismatch.' }
    if ([string]$provisional.native_recovery_sha256 -ne (Hash $recoveryExe)) { throw 'Provisional trust native recovery hash mismatch.' }
    if ([string]$provisional.historical_outer_exe_sha256 -ne $ExpectedHistorical022AppSha256) { throw 'Provisional trust historical outer EXE hash mismatch.' }
    if ([int]$provisional.historical_onefile_runtime_executable_count -lt 2 -or [bool]$provisional.historical_onefile_input_executed_during_trust_build) { throw 'Historical onefile native trust evidence is incomplete/unsafe.' }
    $provisionalCip = Join-Path $ProvisionalRoot ([string]$provisional.supplemental_policy_cip)
    $provisionalXml = Join-Path $ProvisionalRoot ([string]$provisional.supplemental_policy_xml)
    if ((Hash $provisionalCip) -ne ([string]$provisional.supplemental_policy_cip_sha256).ToLowerInvariant()) { throw 'Provisional CIP hash mismatch.' }
    if (Select-String -LiteralPath $provisionalXml -Pattern 'Enabled:Audit Mode' -Quiet) { throw 'Provisional supplemental XML contains Audit Mode.' }

    $normal = Read-Json $NormalEvidencePath 'normal-Windows candidate E2E evidence'
    if ([string]$normal.result -ne 'PASS' -or [string]$normal.uninstaller_deterministic -ne 'PASS') { throw 'Normal-Windows candidate lifecycle/uninstaller determinism did not PASS.' }
    if ([string]$normal.fresh_uninstaller_sha256 -ne ([string]$provisional.reference_uninstaller_sha256).ToLowerInvariant()) { throw 'Provisional uninstaller hash differs from normal lifecycle evidence.' }

    $historicalExe = Join-Path $HistoricalRoot 'Arvectum Proxy Launcher.exe'
    if ((Hash $historicalExe) -ne $ExpectedHistorical022AppSha256) { throw 'Historical 0.2.2 P0.4 EXE hash mismatch.' }
    foreach ($name in @('install.bat','install.ps1','uninstall.ps1','uninstall.bat','restore_network.bat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $HistoricalRoot $name) -PathType Leaf)) { throw "Historical package file is missing: $name" }
    }

    [pscustomobject]@{
        bundle_path = $bundlePath; bundle = $bundle; setup = $setup[0].FullName; setup_dir = $setupDir
        runtime_manifest_path = $runtimeManifestPath; runtime = $runtime; rescue_root = $rescueRoot; rescue_entry = $rescueEntry
        recovery_exe = $recoveryExe; provisional_path = $provisionalPath; provisional = $provisional
        provisional_cip = $provisionalCip; provisional_xml = $provisionalXml; normal = $normal
        historical_exe = $historicalExe
    }
}

function Get-AppControlPolicies([string]$CiTool) {
    $raw = & $CiTool -lp -json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "CiTool -lp -json failed: $($raw -join ' ')" }
    $parsed = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    $items = if ($parsed.PSObject.Properties['Policies']) { @($parsed.Policies) } else { @($parsed) }
    foreach ($p in $items) {
        [pscustomobject]@{
            policy_id = Normalize-GuidText $p.PolicyID
            base_policy_id = Normalize-GuidText $p.BasePolicyID
            friendly_name = [string]$p.FriendlyName
            is_enforced = [bool]$p.IsEnforced
            is_on_disk = [bool]$p.IsOnDisk
            is_authorized = $(if ($p.PSObject.Properties['IsAuthorized']) { [bool]$p.IsAuthorized } else { $null })
            is_signed_policy = $(if ($p.PSObject.Properties['IsSignedPolicy']) { [bool]$p.IsSignedPolicy } else { $null })
            policy_options = @($p.PolicyOptions)
        }
    }
}

function Require-Supplemental([object[]]$Policies, [Guid]$Id, [string]$Label) {
    $matches = @($Policies | Where-Object { $_.policy_id -eq (Normalize-GuidText $Id) })
    if ($matches.Count -ne 1 -or -not $matches[0].is_on_disk) { throw "$Label supplemental is not uniquely active/on-disk." }
    if ($matches[0].is_authorized -eq $false) { throw "$Label supplemental is not authorized." }
    if ($matches[0].base_policy_id -ne (Normalize-GuidText $BasePolicyId)) { throw "$Label supplemental targets another base." }
    $matches[0]
}

function Get-KnownPolicyState([string]$CiTool, [object]$Inputs, [bool]$RequireProvisional) {
    $policies = @(Get-AppControlPolicies $CiTool)
    $base = @($policies | Where-Object { $_.policy_id -eq (Normalize-GuidText $BasePolicyId) })
    if ($base.Count -ne 1 -or -not $base[0].is_on_disk) { throw 'Dedicated APL-WIN-014 base is not uniquely active/on-disk.' }
    if ([string]$base[0].friendly_name -ne 'Arvectum APL-WIN-014 Lab Base') { throw 'Dedicated base FriendlyName mismatch.' }
    if ($base[0].is_signed_policy -eq $true) { throw 'Dedicated lab base unexpectedly became signed.' }
    $null = Require-Supplemental $policies $HistoricalSupplementalPolicyId 'historical 0.2.2'
    $null = Require-Supplemental $policies $Sealed023SupplementalPolicyId 'sealed 0.2.3'
    $provisionalId = [Guid](([string]$Inputs.provisional.supplemental_policy_id).Trim().Trim('{}'))
    $provisional = @($policies | Where-Object { $_.policy_id -eq (Normalize-GuidText $provisionalId) })
    if ($RequireProvisional) {
        if ($provisional.Count -ne 1 -or -not $provisional[0].is_on_disk -or $provisional[0].is_authorized -eq $false) { throw 'Provisional supplemental is not active/on-disk/authorized.' }
        if ($provisional[0].base_policy_id -ne (Normalize-GuidText $BasePolicyId)) { throw 'Provisional supplemental targets another base.' }
    } elseif ($provisional.Count -gt 1) {
        throw 'Duplicate provisional supplemental policy identities detected.'
    }
    $audit = @($base[0].policy_options) -contains 'Enabled:Audit Mode'
    if (-not $audit -and -not $base[0].is_enforced) { throw 'Dedicated base is neither known Audit nor known Enforced state.' }
    [pscustomobject]@{ mode=$(if ($audit){'AUDIT'}else{'ENFORCED'}); base=$base[0]; policies=$policies; provisional=$provisional }
}

function Get-PolicyXmlInfo([string]$Path) {
    [xml]$xml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('si','urn:schemas-microsoft-com:sipolicy')
    $policyId = $xml.SelectSingleNode('//si:PolicyID',$ns)
    $baseId = $xml.SelectSingleNode('//si:BasePolicyID',$ns)
    $version = $xml.SelectSingleNode('//si:VersionEx',$ns)
    $options = @($xml.SelectNodes('//si:Rules/si:Rule/si:Option',$ns) | ForEach-Object { [string]$_.InnerText })
    if (-not $policyId -or -not $baseId -or -not $version) { throw 'Policy XML metadata incomplete.' }
    [pscustomobject]@{ policy_id=Normalize-GuidText $policyId.InnerText; base_policy_id=Normalize-GuidText $baseId.InnerText; version=[string]$version.InnerText; options=$options }
}

function Prepare-EnforcedBasePolicy {
    if (-not (Test-Path -LiteralPath $BaseXml -PathType Leaf)) { throw 'Dedicated base XML is missing.' }
    if (-not (Test-Path -LiteralPath $BaseAuditCip -PathType Leaf) -or (Hash $BaseAuditCip) -ne $ExpectedAuditBaseCipSha256) { throw 'Governed Audit base CIP hash mismatch.' }
    $audit = Get-PolicyXmlInfo $BaseXml
    if ($audit.policy_id -ne (Normalize-GuidText $BasePolicyId) -or $audit.base_policy_id -ne (Normalize-GuidText $BasePolicyId)) { throw 'Base XML PolicyID/BasePolicyID mismatch.' }
    foreach ($option in @('Enabled:Audit Mode','Enabled:Update Policy No Reboot','Enabled:Allow Supplemental Policies')) {
        if (-not (@($audit.options) -contains $option)) { throw "Base XML missing required option: $option" }
    }
    $parts = @($audit.version.Split('.') | ForEach-Object { [uint32]$_ })
    if ($parts.Count -ne 4 -or $parts[3] -eq [uint32]::MaxValue) { throw 'Base VersionEx cannot be safely advanced.' }
    $parts[3]++
    New-Item -ItemType Directory -Path $EnforcedDirectory -Force | Out-Null
    Copy-Item -LiteralPath $BaseXml -Destination $EnforcedXml -Force
    Set-RuleOption -FilePath $EnforcedXml -Option 3 -Delete
    Set-CIPolicyVersion -FilePath $EnforcedXml -Version ($parts -join '.')
    $enforced = Get-PolicyXmlInfo $EnforcedXml
    if ($enforced.policy_id -ne $audit.policy_id -or $enforced.base_policy_id -ne $audit.base_policy_id) { throw 'Enforced base preparation changed policy identity.' }
    if (@($enforced.options) -contains 'Enabled:Audit Mode') { throw 'Prepared Enforced base still contains Audit Mode.' }
    foreach ($option in @('Enabled:Update Policy No Reboot','Enabled:Allow Supplemental Policies')) {
        if (-not (@($enforced.options) -contains $option)) { throw "Prepared Enforced base lost option: $option" }
    }
    ConvertFrom-CIPolicy -XmlFilePath $EnforcedXml -BinaryFilePath $EnforcedCip | Out-Null
    if (-not (Test-Path -LiteralPath $EnforcedCip -PathType Leaf)) { throw 'Prepared Enforced CIP is missing.' }
    [pscustomobject]@{ audit_version=$audit.version; enforced_version=$enforced.version; cip=$EnforcedCip; cip_sha256=Hash $EnforcedCip }
}

function Invoke-PolicyUpdate([string]$CiTool, [string]$Cip, [string]$Label) {
    $raw = & $CiTool --update-policy $Cip -json 2>&1
    $exit = $LASTEXITCODE
    $raw | ForEach-Object { Write-Host $_ }
    if ($exit -ne 0) { throw "$Label CiTool update failed with exit code $exit." }
}

function Wait-PolicyState([string]$CiTool, [object]$Inputs, [string]$ExpectedMode, [bool]$RequireProvisional, [int]$Seconds=20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $last = $null
    do {
        try {
            $state = Get-KnownPolicyState $CiTool $Inputs $RequireProvisional
            if ($state.mode -eq $ExpectedMode) { return $state }
        } catch { $last = $_ }
        Start-Sleep -Milliseconds 750
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($last) { throw $last }
    throw "Policy state did not become $ExpectedMode before timeout."
}

function Get-PacHealth([string]$ExpectedExe) {
    if (-not (Test-Path -LiteralPath $ExpectedExe -PathType Leaf)) { return $null }
    $expected = [IO.Path]::GetFullPath($ExpectedExe)
    foreach ($listener in @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)) {
        $owner = @(Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue)
        if ($owner.Count -ne 1 -or -not $owner[0].ExecutablePath) { continue }
        if ([IO.Path]::GetFullPath([string]$owner[0].ExecutablePath) -ine $expected) { continue }
        try {
            $pac = Invoke-WebRequest -UseBasicParsing -Uri $PacUrl -TimeoutSec 3
            $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
            $auto = $inet.PSObject.Properties['AutoConfigURL']
            if ($pac.StatusCode -eq 200 -and $auto -and [string]$auto.Value -eq $PacUrl) {
                return [pscustomobject]@{ pid=[int]$listener.OwningProcess; http_status=200; auto_config_url=[string]$auto.Value }
            }
        } catch {}
    }
    $null
}

function Wait-PacHealth([string]$ExpectedExe, [int]$Seconds=35) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $health = Get-PacHealth $ExpectedExe
        if ($health) { return $health }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Exact Launcher did not establish listener/PAC/WinINET before timeout: $ExpectedExe"
}

function Wait-ExactProcess([string]$ExpectedExe, [int]$Seconds=12) {
    $expected = [IO.Path]::GetFullPath($ExpectedExe)
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $matches = @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -and [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $expected })
        if ($matches.Count -gt 0) { return $matches[0] }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Exact Launcher process was not observed: $ExpectedExe"
}

function Stop-ExactProcesses([string]$ExpectedExe) {
    if (-not (Test-Path -LiteralPath $ExpectedExe -PathType Leaf)) { return }
    $expected = [IO.Path]::GetFullPath($ExpectedExe)
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='Arvectum Proxy Launcher.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -and [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $expected })) {
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BoundedRollback([string]$Exe, [int]$Seconds=20) {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return }
    $p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -ArgumentList @('--rollback') -PassThru
    if (-not $p.WaitForExit($Seconds * 1000)) { throw "--rollback timed out: $Exe" }
    if ($p.ExitCode -ne 0) { throw "--rollback failed with exit code $($p.ExitCode): $Exe" }
    Stop-ExactProcesses $Exe
}

function Invoke-CandidateSetup([object]$Inputs, [string]$Log) {
    $p = Start-Process -FilePath $Inputs.setup -WorkingDirectory $Inputs.setup_dir -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',("/DIR=$InstallRoot"),("/LOG=$Log")) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "Candidate Setup failed with exit code $($p.ExitCode)." }
}

function Resolve-Uninstaller([string]$Root=$InstallRoot) {
    $items = @(Get-ChildItem -LiteralPath $Root -File -Filter 'unins*.exe' -ErrorAction SilentlyContinue)
    if ($items.Count -ne 1) { throw "Expected exactly one Inno uninstaller under $Root; found $($items.Count)." }
    $items[0].FullName
}

function Invoke-Uninstall([string]$Log) {
    $uninstaller = Resolve-Uninstaller
    $p = Start-Process -FilePath $uninstaller -WorkingDirectory $InstallRoot -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$Log")) -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "Uninstall failed with exit code $($p.ExitCode)." }
}

function Restore-DurableState([string]$BackupDirectory) {
    $durable = Join-Path $BackupDirectory 'durable-state'
    foreach ($name in @('proxy_settings.json','no_proxy.txt')) {
        $source = Join-Path $durable $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Recovery backup lacks $name." }
    }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $durable 'proxy_settings.json') -Destination (Join-Path $StateRoot 'proxy_settings.json') -Force
    Copy-Item -LiteralPath (Join-Path $durable 'no_proxy.txt') -Destination (Join-Path $StateRoot 'no_proxy.txt') -Force
    foreach ($stale in @('proxy_core.pid','proxy_env_backup.json','proxy_internet_backup.json')) {
        Remove-Item -LiteralPath (Join-Path $StateRoot $stale) -Force -ErrorAction SilentlyContinue
    }
}

function Save-RecoveryBackup {
    foreach ($name in @('proxy_settings.json','no_proxy.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $StateRoot $name) -PathType Leaf)) { throw "Durable current state is missing: $name" }
    }
    New-Item -ItemType Directory -Path $RecoveryRoot -Force | Out-Null
    $dir = Join-Path $RecoveryRoot ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    $durable = Join-Path $dir 'durable-state'
    New-Item -ItemType Directory -Path $durable -Force | Out-Null
    foreach ($name in @('proxy_settings.json','no_proxy.txt')) { Copy-Item -LiteralPath (Join-Path $StateRoot $name) -Destination (Join-Path $durable $name) -Force }
    $inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $snapshot = [ordered]@{
        ProxyEnable=$(if($inet -and $inet.PSObject.Properties['ProxyEnable']){[int]$inet.ProxyEnable}else{$null})
        ProxyServer=$(if($inet -and $inet.PSObject.Properties['ProxyServer']){[string]$inet.ProxyServer}else{$null})
        AutoConfigURL=$(if($inet -and $inet.PSObject.Properties['AutoConfigURL']){[string]$inet.AutoConfigURL}else{$null})
    }
    Write-Json $snapshot (Join-Path $dir 'wininet-before.json') 5
    Write-Json ([ordered]@{schema='arvectum.proxy.apl-win-014-recovery-pointer.v2';created_utc=[DateTime]::UtcNow.ToString('o');backup_directory=$dir}) $RecoveryPointerPath 5
    $dir
}

function Resolve-RecoveryBackup([string]$Requested) {
    if ($Requested) { return (Resolve-Path -LiteralPath $Requested).Path }
    $pointer = Read-Json $RecoveryPointerPath 'recovery pointer'
    (Resolve-Path -LiteralPath ([string]$pointer.backup_directory)).Path
}

function Invoke-NativeRecovery([object]$Inputs, [string]$BackupDirectory, [string]$EvidencePath, [bool]$VerifyOnly) {
    $args = @('--backup',$BackupDirectory,'--runtime',$Inputs.rescue_root,'--expected-runtime-sha256',([string]$Inputs.runtime.entry_sha256),'--evidence',$EvidencePath)
    if ($VerifyOnly) { $args += @('--verify-only','true') }
    $p = Start-Process -FilePath $Inputs.recovery_exe -WorkingDirectory (Split-Path -Parent $Inputs.recovery_exe) -ArgumentList $args -PassThru -Wait
    if ($p.ExitCode -ne 0) { throw "Native recovery $(if($VerifyOnly){'PREARM'}else{'execution'}) failed with exit code $($p.ExitCode)." }
    $evidence = Read-Json $EvidencePath 'native recovery evidence'
    if ([string]$evidence.result -ne 'PASS' -or [bool]$evidence.verify_only -ne $VerifyOnly) { throw 'Native recovery evidence mismatch/non-PASS.' }
    if ($VerifyOnly -and [bool]$evidence.changes_network_state) { throw 'Native recovery PREARM claims network mutation.' }
    $evidence
}

function Resolve-Current023Healthy {
    foreach ($name in @('proxy_settings.json','no_proxy.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $StateRoot $name) -PathType Leaf)) {
            throw "Exact current durable state missing: $name"
        }
    }

    $healthy = @()
    foreach ($listener in @(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue)) {
        $owner = @(Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue)
        if ($owner.Count -ne 1 -or -not $owner[0].ExecutablePath) { continue }
        $exe = [string]$owner[0].ExecutablePath
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        if ((Hash $exe) -ne $ExpectedSealed023AppSha256) { continue }
        $health = Get-PacHealth $exe
        if ($health) {
            $healthy += [pscustomobject]@{ exe=$exe; health=$health }
        }
    }

    $healthy = @($healthy | Sort-Object -Property exe -Unique)
    if ($healthy.Count -ne 1) {
        throw "Expected exactly one healthy exact sealed 0.2.3 runtime owning PAC; found $($healthy.Count)."
    }

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

    [pscustomobject]@{
        mode = $mode
        exe = [string]$current.exe
        uninstaller = $uninstaller
        health = $current.health
    }
}

function Assert-CandidateInstalled([object]$Inputs) {
    $installedManifest = Read-Json (Join-Path $InstallRoot 'appcontrol_installer_manifest.json') 'installed candidate manifest'
    if ([string]$installedManifest.result -ne 'PASS' -or [string]$installedManifest.version -ne '0.2.4' -or [string]$installedManifest.candidate_label -ne '0.2.4-appcontrol-candidate') { throw 'Installed candidate manifest identity mismatch.' }
    $runtimeRoot = Join-Path $InstallRoot ("runtime\" + [string]$installedManifest.runtime_label)
    $installedRuntimeManifest = Join-Path $runtimeRoot 'static-runtime.json'
    if ((Hash $installedRuntimeManifest) -ne (Hash $Inputs.runtime_manifest_path)) { throw 'Installed static-runtime manifest differs from candidate rescue runtime.' }
    foreach ($file in @($Inputs.runtime.files)) {
        $path = Join-Path $runtimeRoot ([string]$file.relative_path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [long](Get-Item -LiteralPath $path).Length -ne [long]$file.size -or (Hash $path) -ne ([string]$file.sha256).ToLowerInvariant()) {
            throw "Installed runtime byte mismatch: $([string]$file.relative_path)"
        }
    }
    $entry = Join-Path $runtimeRoot 'Arvectum Proxy Launcher.exe'
    if ((Hash $entry) -ne ([string]$Inputs.runtime.entry_sha256).ToLowerInvariant()) { throw 'Installed runtime entry hash mismatch.' }
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'Arvectum Proxy Launcher.exe')) { throw 'Legacy top-level onefile survives in candidate installation.' }
    $uninstaller = Resolve-Uninstaller
    if ((Hash $uninstaller) -ne ([string]$Inputs.provisional.reference_uninstaller_sha256).ToLowerInvariant()) { throw 'Generated candidate uninstaller hash differs from provisional trust.' }
    [pscustomobject]@{ manifest=$installedManifest; runtime_root=$runtimeRoot; entry=$entry; uninstaller=$uninstaller }
}

function Get-Arvectum3077([datetime]$Since) {
    @(
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational';Id=3077;StartTime=$Since} -ErrorAction SilentlyContinue |
        Where-Object { ([string]$_.Message) -match '(?i)Arvectum|Proxy Launcher' }
    )
}

function Assert-NoArvectum3077([datetime]$Since, [string]$Phase) {
    $events = @(Get-Arvectum3077 $Since)
    if ($events.Count -gt 0) {
        $summary = @($events | Select-Object -First 3 | ForEach-Object { ([string]$_.Message -replace "`r|`n",' ') }) -join ' | '
        throw "SAFETY BLOCK: $($events.Count) Arvectum-related Code Integrity 3077 event(s) since $Since during $Phase. $summary"
    }
    0
}

function Assert-ConstrainedLanguage {
    $output = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command '$ExecutionContext.SessionState.LanguageMode' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'New Windows PowerShell child could not be started under Enforced App Control.' }
    $mode = (($output | ForEach-Object { [string]$_ }) -join '').Trim()
    if ($mode -ne 'ConstrainedLanguage') { throw "SAFETY BLOCK: new PowerShell child is '$mode', expected ConstrainedLanguage." }
    $mode
}

function Invoke-Preflight {
    New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    $hostInfo = Assert-AdminHostAndTools
    $kit = Assert-KitIntegrity
    $inputs = Resolve-CandidateInputs
    $policy = Get-KnownPolicyState $hostInfo.citool $inputs $false
    $prepared = $null
    if ($policy.mode -eq 'AUDIT') { $prepared = Prepare-EnforcedBasePolicy }
    $current = Resolve-Current023Healthy
    $health = $current.health
    $record = [ordered]@{
        schema='arvectum.proxy.apl-win-014-candidate-preflight.v1';task='APL-WIN-014';created_utc=[DateTime]::UtcNow.ToString('o');result='PASS'
        host=$env:COMPUTERNAME;version=[string]$kit.version;source_commit=[string]$kit.source_commit
        base_policy_id=$BasePolicyId.ToString('B');base_mode=$policy.mode
        historical_supplemental='ACTIVE';sealed_023_supplemental='ACTIVE'
        provisional_policy_id=[string]$inputs.provisional.supplemental_policy_id
        provisional_policy_state=$(if($policy.provisional.Count -eq 1){'ALREADY_ACTIVE'}else{'NOT_DEPLOYED'})
        provisional_final_acceptance_evidence=[bool]$inputs.provisional.final_acceptance_evidence
        provisional_enforced_lifecycle_ready=[bool]$inputs.provisional.enforced_lifecycle_ready
        historical_onefile_native_members=[int]$inputs.provisional.historical_onefile_runtime_executable_count
        candidate_setup_sha256=Hash $inputs.setup;candidate_runtime_entry_sha256=[string]$inputs.runtime.entry_sha256
        native_recovery_sha256=Hash $inputs.recovery_exe;current_sealed_023_sha256=Hash $current.exe;current_runtime_mode=[string]$current.mode;current_runtime_path=[string]$current.exe
        current_pac_http_status=[int]$health.http_status;current_auto_config_url=[string]$health.auto_config_url
        enforced_base_prepared=$(if($prepared){$true}else{$policy.mode -eq 'ENFORCED'});enforced_base_cip_sha256=$(if($prepared){$prepared.cip_sha256}else{$null})
        destructive_action_performed=$false;policy_update_performed=$false
    }
    Write-Json $record $PreflightEvidencePath 12
    [pscustomobject]@{host=$hostInfo;kit=$kit;inputs=$inputs;policy=$policy;prepared=$prepared;current=$current;health=$health}
}

function Ensure-ProvisionalActive([object]$Context) {
    $state = Get-KnownPolicyState $Context.host.citool $Context.inputs $false
    if ($state.provisional.Count -eq 0) {
        Invoke-PolicyUpdate $Context.host.citool $Context.inputs.provisional_cip 'provisional supplemental'
    }
    $expectedMode = $state.mode
    Wait-PolicyState $Context.host.citool $Context.inputs $expectedMode $true 20
}

function Ensure-BaseEnforced([object]$Context) {
    $state = Get-KnownPolicyState $Context.host.citool $Context.inputs $true
    if ($state.mode -eq 'ENFORCED') { return $state }
    if (-not (Test-Path -LiteralPath $EnforcedCip -PathType Leaf)) { throw 'Prepared Enforced base CIP is missing.' }
    Invoke-PolicyUpdate $Context.host.citool $EnforcedCip 'dedicated base Audit -> Enforced'
    Wait-PolicyState $Context.host.citool $Context.inputs 'ENFORCED' $true 20
}

function Remove-Current023AfterRollback([object]$Current) {
    if (-not $Current -or [string]$Current.mode -notin @('INSTALLED','PORTABLE_RECOVERY')) {
        throw 'Current exact 0.2.3 state is missing or unsupported.'
    }

    Invoke-BoundedRollback ([string]$Current.exe) 20
    Stop-ExactProcesses ([string]$Current.exe)

    if ([string]$Current.mode -eq 'INSTALLED') {
        $uninstaller = [string]$Current.uninstaller
        if (-not $uninstaller -or -not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
            throw 'Installed exact sealed 0.2.3 uninstaller disappeared after preflight.'
        }
        $p = Start-Process -FilePath $uninstaller -WorkingDirectory $InstallRoot -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',("/LOG=$(Join-Path $EvidenceRoot 'sealed-023-pre-lifecycle-uninstall.log')")) -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Sealed 0.2.3 uninstall failed with exit code $($p.ExitCode)." }
    }

    Remove-Item -LiteralPath $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ([string]$Current.mode -eq 'INSTALLED' -and (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
        $left = @(Get-ChildItem -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) { Remove-Item -LiteralPath $InstallRoot -Force }
    }
    if (@(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'TCP 8082 is not free after exact current 0.2.3 rollback/cleanup.'
    }
}

function Install-Historical022UnderEnforced {
    $oldAppDir = $env:ARVECTUM_APP_DIR
    $oldNonInteractive = $env:ARVECTUM_NONINTERACTIVE
    try {
        $env:ARVECTUM_APP_DIR = $InstallRoot
        $env:ARVECTUM_NONINTERACTIVE = '1'
        $installBat = Join-Path $HistoricalRoot 'install.bat'
        $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -WorkingDirectory $HistoricalRoot -ArgumentList @('/d','/c',('"' + $installBat + '"')) -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "Historical 0.2.2 P0.4 install failed under Enforced with exit code $($p.ExitCode)." }
    } finally {
        $env:ARVECTUM_APP_DIR = $oldAppDir
        $env:ARVECTUM_NONINTERACTIVE = $oldNonInteractive
    }
    $historicalInstalled = Join-Path $InstallRoot 'Arvectum Proxy Launcher.exe'
    if (-not (Test-Path -LiteralPath $historicalInstalled -PathType Leaf) -or (Hash $historicalInstalled) -ne $ExpectedHistorical022AppSha256) { throw 'Historical install did not produce exact immutable 0.2.2 P0.4 bytes.' }
    $null = Wait-ExactProcess $historicalInstalled 15
    $historicalInstalled
}

function Invoke-Execute {
    $context = Invoke-Preflight
    $backup = Save-RecoveryBackup
    $destructiveStarted = $false
    $success = $false
    $ciStart = $null
    $enforcedRecord = [ordered]@{
        schema='arvectum.proxy.windows-app-control-enforced-lifecycle.v1';task='APL-WIN-014';created_utc=[DateTime]::UtcNow.ToString('o');result='BLOCK';environment='Enforced'
        base_policy_id=$BasePolicyId.ToString('B');supplemental_policy_id=[string]$context.inputs.provisional.supplemental_policy_id
        enterprise_bundle_manifest_sha256=Hash $context.inputs.bundle_path;provisional_trust_pack_manifest_sha256=Hash $context.inputs.provisional_path
        provisional_cip_sha256=Hash $context.inputs.provisional_cip;runtime_entry_sha256=[string]$context.inputs.runtime.entry_sha256
        uninstaller_sha256=[string]$context.inputs.provisional.reference_uninstaller_sha256
        fresh_install='NOT_RUN';repair='NOT_RUN';upgrade='NOT_RUN';uninstall='NOT_RUN';historical_022_install='NOT_RUN';historical_022_process='NOT_RUN'
        base_remained_enforced=$false;supplemental_remained_active=$false;code_integrity_scope='Arvectum-related Event ID 3077 since destructive lifecycle start';code_integrity_3077_blocks=-1
    }
    try {
        Write-Host 'Deploying rehearsal-only provisional supplemental...'
        $null = Ensure-ProvisionalActive $context
        Write-Host 'Ensuring dedicated base is Enforced...'
        $null = Ensure-BaseEnforced $context
        $clm = Assert-ConstrainedLanguage
        Write-Host "New PowerShell child language mode: $clm"

        $prearmPath = Join-Path $EvidenceRoot 'apl-win-014-native-recovery-prearm.json'
        $prearm = Invoke-NativeRecovery $context.inputs $backup $prearmPath $true
        if ([bool]$prearm.changes_network_state) { throw 'Native recovery PREARM was not non-mutating.' }
        Write-Host 'Native recovery PREARM under Enforced: PASS'

        $ciStart = [DateTime]::UtcNow
        $destructiveStarted = $true
        Remove-Current023AfterRollback $context.current

        Write-Host 'Installing exact immutable 0.2.2 P0.4 under Enforced...'
        $historicalInstalled = Install-Historical022UnderEnforced
        $enforcedRecord.historical_022_install = 'PASS'
        $enforcedRecord.historical_022_process = 'PASS'
        $null = Assert-NoArvectum3077 $ciStart 'historical 0.2.2 launch'

        Write-Host 'Running real 0.2.2 P0.4 -> 0.2.4 static-runtime upgrade...'
        Invoke-CandidateSetup $context.inputs (Join-Path $EvidenceRoot 'appcontrol-enforced-upgrade.log')
        $upgraded = Assert-CandidateInstalled $context.inputs
        Restore-DurableState $backup
        Start-Process -FilePath $upgraded.entry -WorkingDirectory $upgraded.runtime_root -ArgumentList @('--start') | Out-Null
        $null = Wait-PacHealth $upgraded.entry 35
        Invoke-BoundedRollback $upgraded.entry 20
        $enforcedRecord.upgrade = 'PASS'
        $null = Assert-NoArvectum3077 $ciStart 'cross-version upgrade'
        Invoke-Uninstall (Join-Path $EvidenceRoot 'appcontrol-enforced-upgrade-uninstall.log')

        Write-Host 'Running exact 0.2.4 fresh install...'
        Invoke-CandidateSetup $context.inputs (Join-Path $EvidenceRoot 'appcontrol-enforced-fresh-install.log')
        $fresh = Assert-CandidateInstalled $context.inputs
        Restore-DurableState $backup
        Start-Process -FilePath $fresh.entry -WorkingDirectory $fresh.runtime_root -ArgumentList @('--start') | Out-Null
        $null = Wait-PacHealth $fresh.entry 35
        Invoke-BoundedRollback $fresh.entry 20
        $enforcedRecord.fresh_install = 'PASS'

        Write-Host 'Injecting one exact runtime DLL/PYD loss and running repair...'
        $repairFile = @($context.inputs.runtime.files | Where-Object { [bool]$_.executable -and [string]$_.relative_path -ne 'Arvectum Proxy Launcher.exe' -and ([string]$_.relative_path).ToLowerInvariant().EndsWith('.dll') }) | Select-Object -First 1
        if (-not $repairFile) { $repairFile = @($context.inputs.runtime.files | Where-Object { [bool]$_.executable -and [string]$_.relative_path -ne 'Arvectum Proxy Launcher.exe' }) | Select-Object -First 1 }
        if (-not $repairFile) { throw 'No secondary executable runtime file available for repair injection.' }
        $repairPath = Join-Path $fresh.runtime_root ([string]$repairFile.relative_path)
        Remove-Item -LiteralPath $repairPath -Force
        if (Test-Path -LiteralPath $repairPath) { throw 'Repair injection failed to remove exact runtime file.' }
        Invoke-CandidateSetup $context.inputs (Join-Path $EvidenceRoot 'appcontrol-enforced-repair.log')
        $repaired = Assert-CandidateInstalled $context.inputs
        $repairedPath = Join-Path $repaired.runtime_root ([string]$repairFile.relative_path)
        if ((Hash $repairedPath) -ne ([string]$repairFile.sha256).ToLowerInvariant()) { throw 'Repair restored wrong runtime bytes.' }
        $enforcedRecord.repair = 'PASS'
        Restore-DurableState $backup
        Start-Process -FilePath $repaired.entry -WorkingDirectory $repaired.runtime_root -ArgumentList @('--start') | Out-Null
        $null = Wait-PacHealth $repaired.entry 35
        Invoke-BoundedRollback $repaired.entry 20
        $null = Assert-NoArvectum3077 $ciStart 'fresh/repair lifecycle'

        Invoke-Uninstall (Join-Path $EvidenceRoot 'appcontrol-enforced-final-uninstall.log')
        $enforcedRecord.uninstall = 'PASS'
        if (Test-Path -LiteralPath (Join-Path $InstallRoot 'runtime')) { throw 'Enforced uninstall left candidate runtime behind.' }
        $null = Assert-NoArvectum3077 $ciStart 'uninstall'

        Write-Host 'Running real native recovery rehearsal from clean product state...'
        Remove-Item -LiteralPath $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
        $nativeRawPath = Join-Path $EvidenceRoot 'apl-win-014-native-recovery-raw.json'
        $nativeRaw = Invoke-NativeRecovery $context.inputs $backup $nativeRawPath $false
        $rescueHealth = Wait-PacHealth $context.inputs.rescue_entry 35
        $policyAfterRecovery = Get-KnownPolicyState $context.host.citool $context.inputs $true
        if ($policyAfterRecovery.mode -ne 'ENFORCED') { throw 'Base is not Enforced after native recovery.' }
        $clmAfterRecovery = Assert-ConstrainedLanguage
        $recovery3077 = @(Get-Arvectum3077 $ciStart).Count
        if ($recovery3077 -ne 0) { throw "Native recovery rehearsal has $recovery3077 Arvectum-related Code Integrity 3077 block(s)." }

        $recoveryRecord = [ordered]@{
            schema='arvectum.proxy.apl-win-014-native-recovery-rehearsal.v1';task='APL-WIN-014';created_utc=[DateTime]::UtcNow.ToString('o');result='PASS';environment='Enforced/ConstrainedLanguage'
            base_policy_id=$BasePolicyId.ToString('B');supplemental_policy_id=[string]$context.inputs.provisional.supplemental_policy_id
            enterprise_bundle_manifest_sha256=Hash $context.inputs.bundle_path;provisional_trust_pack_manifest_sha256=Hash $context.inputs.provisional_path;provisional_cip_sha256=Hash $context.inputs.provisional_cip
            native_recovery_sha256=Hash $context.inputs.recovery_exe;runtime_entry_sha256=[string]$context.inputs.runtime.entry_sha256
            restores_exact_current_release=$true;restores_pac_connectivity=($rescueHealth.http_status -eq 200 -and $rescueHealth.auto_config_url -eq $PacUrl)
            base_remained_enforced=$true;supplemental_remained_active=$true;changes_base_to_audit=$false
            constrained_language_after_recovery=$clmAfterRecovery;code_integrity_scope='Arvectum-related Event ID 3077 since destructive lifecycle start';code_integrity_3077_blocks=$recovery3077
            native_recovery_raw_evidence_sha256=Hash $nativeRawPath
        }
        Write-Json $recoveryRecord $RecoveryEvidencePath 12

        $enforcedRecord.base_remained_enforced = $true
        $enforcedRecord.supplemental_remained_active = $true
        $enforcedRecord.code_integrity_3077_blocks = $recovery3077
        $enforcedRecord.result = 'PASS'
        Write-Json $enforcedRecord $EnforcedEvidencePath 14

        Write-Host 'Restoring installed exact 0.2.4 as final healthy stand state...'
        Invoke-BoundedRollback $context.inputs.rescue_entry 20
        Invoke-CandidateSetup $context.inputs (Join-Path $EvidenceRoot 'appcontrol-final-restore-install.log')
        $final = Assert-CandidateInstalled $context.inputs
        Restore-DurableState $backup
        Start-Process -FilePath $final.entry -WorkingDirectory $final.runtime_root -ArgumentList @('--start') | Out-Null
        $finalHealth = Wait-PacHealth $final.entry 35
        $finalPolicy = Get-KnownPolicyState $context.host.citool $context.inputs $true
        if ($finalPolicy.mode -ne 'ENFORCED') { throw 'Final base policy is not Enforced.' }
        $null = Assert-NoArvectum3077 $ciStart 'final healthy restoration'

        $result = [ordered]@{
            schema='arvectum.proxy.apl-win-014-candidate-result.v1';task='APL-WIN-014';created_utc=[DateTime]::UtcNow.ToString('o');result='PASS'
            version='0.2.4';historical_022_to_024='PASS';fresh_install='PASS';repair='PASS';uninstall='PASS';native_recovery_rehearsal='PASS'
            base_policy='ENFORCED';provisional_supplemental='ACTIVE';constrained_language='PASS';code_integrity_3077_blocks=0
            final_exact_runtime_sha256=Hash $final.entry;final_pac_http_status=[int]$finalHealth.http_status;final_auto_config_url=[string]$finalHealth.auto_config_url
            enforced_lifecycle_evidence=$EnforcedEvidencePath;native_recovery_rehearsal_evidence=$RecoveryEvidencePath;recovery_backup=$backup
        }
        Write-Json $result $ResultEvidencePath 12
        $success = $true
        return [pscustomobject]@{result=$result;inputs=$context.inputs;backup=$backup}
    }
    catch {
        $enforcedRecord.block_reason = [string]$_.Exception.Message
        $enforcedRecord.finished_utc = [DateTime]::UtcNow.ToString('o')
        if ($ciStart) { $enforcedRecord.code_integrity_3077_blocks = @(Get-Arvectum3077 $ciStart).Count }
        Write-Json $enforcedRecord $EnforcedEvidencePath 14
        throw
    }
    finally {
        if (-not $success -and $destructiveStarted -and $backup) {
            try {
                Write-Warning 'Acceptance blocked after destructive start; invoking exact native recovery. App Control is NOT weakened or returned to Audit.'
                $emergency = Join-Path $EvidenceRoot 'apl-win-014-native-recovery-emergency.json'
                $null = Invoke-NativeRecovery $context.inputs $backup $emergency $false
                $null = Wait-PacHealth $context.inputs.rescue_entry 35
                Write-Warning 'Emergency native recovery restored PAC connectivity. Rescue runtime is intentionally left running.'
            }
            catch { Write-Warning ("Emergency native recovery also failed: " + $_.Exception.Message) }
        }
    }
}

function Invoke-Recover {
    $null = Assert-AdminHostAndTools
    $null = Assert-KitIntegrity
    $inputs = Resolve-CandidateInputs
    $backup = Resolve-RecoveryBackup $RecoveryBackupDirectory
    $hostInfo = Assert-AdminHostAndTools
    $state = Get-KnownPolicyState $hostInfo.citool $inputs $false
    if ($state.mode -eq 'ENFORCED') {
        $provisionalId = Normalize-GuidText $inputs.provisional.supplemental_policy_id
        if (@($state.policies | Where-Object { $_.policy_id -eq $provisionalId -and $_.is_on_disk }).Count -ne 1) {
            throw 'SAFETY BLOCK: base is Enforced but exact provisional supplemental is not active; recovery will not guess or alter policy.'
        }
    }
    $evidence = Join-Path $EvidenceRoot 'apl-win-014-native-recovery-manual.json'
    $null = Invoke-NativeRecovery $inputs $backup $evidence $false
    $health = Wait-PacHealth $inputs.rescue_entry 35
    Write-Host 'APL-WIN-014 NATIVE RECOVERY: PASS'
    Write-Host "BASE POLICY: $($state.mode) (UNCHANGED)"
    Write-Host 'RESCUE RUNTIME: EXACT / RUNNING'
    Write-Host "PAC: $($health.http_status) $($health.auto_config_url)"
    Write-Host 'APP CONTROL POLICY MUTATION: NONE'
    Write-Host "EVIDENCE: $evidence"
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
if ($Mode -eq 'Recover') {
    Invoke-Recover
    exit 0
}

if ($Mode -eq 'Preflight') {
    $preflight = Invoke-Preflight
    Write-Host '================================================'
    Write-Host 'APL-WIN-014 0.2.4 APP CONTROL PREFLIGHT: PASS'
    Write-Host "BASE POLICY: $($preflight.policy.mode)"
    Write-Host 'HISTORICAL 0.2.2 SUPPLEMENTAL: ACTIVE'
    Write-Host 'SEALED 0.2.3 SUPPLEMENTAL: ACTIVE'
    Write-Host "PROVISIONAL 0.2.4: $(if($preflight.policy.provisional.Count -eq 1){'ALREADY ACTIVE'}else{'READY / NOT DEPLOYED'})"
    Write-Host "HISTORICAL 0.2.2 ONEFILE NATIVE HASHES: $([int]$preflight.inputs.provisional.historical_onefile_runtime_executable_count) READY"
    Write-Host 'NATIVE RECOVERY: EXACT / READY / NOT RUN'
    Write-Host "CURRENT EXACT 0.2.3 ($([string]$preflight.current.mode)) + PAC: HEALTHY"
    Write-Host 'NO APP CONTROL POLICY UPDATE PERFORMED'
    Write-Host 'NO DESTRUCTIVE ACTION PERFORMED'
    Write-Host "EVIDENCE: $PreflightEvidencePath"
    Write-Host '================================================'
    exit 0
}

Start-Transcript -LiteralPath $TranscriptPath -Force | Out-Null
try {
    $execution = Invoke-Execute
    Write-Host '================================================'
    Write-Host 'APL-WIN-014 0.2.4 REAL ENFORCED RESULT: PASS'
    Write-Host 'WINDOWS APP CONTROL: ENFORCED'
    Write-Host 'HISTORICAL 0.2.2 P0.4 -> EXACT 0.2.4: PASS'
    Write-Host 'EXACT 0.2.4 FRESH / REPAIR / UNINSTALL: PASS'
    Write-Host 'NATIVE RECOVERY REHEARSAL: PASS'
    Write-Host 'NEW POWERSHELL CHILD: CONSTRAINEDLANGUAGE'
    Write-Host 'ARVECTUM CODE INTEGRITY 3077 BLOCKS: 0'
    Write-Host 'FINAL EXACT 0.2.4 + PAC: HEALTHY'
    Write-Host "ENFORCED EVIDENCE: $EnforcedEvidencePath"
    Write-Host "RECOVERY EVIDENCE: $RecoveryEvidencePath"
    Write-Host "RESULT: $ResultEvidencePath"
    Write-Host '================================================'
}
catch {
    Write-Host '================================================' -ForegroundColor Red
    Write-Host 'APL-WIN-014 0.2.4 REAL ENFORCED RESULT: BLOCK' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'APP CONTROL WAS NOT WEAKENED OR RETURNED TO AUDIT.' -ForegroundColor Yellow
    Write-Host 'IF DESTRUCTIVE TESTING HAD STARTED, NATIVE RECOVERY WAS ATTEMPTED AUTOMATICALLY.' -ForegroundColor Yellow
    Write-Host "RESULT/EVIDENCE ROOT: $EvidenceRoot"
    Write-Host '================================================' -ForegroundColor Red
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
