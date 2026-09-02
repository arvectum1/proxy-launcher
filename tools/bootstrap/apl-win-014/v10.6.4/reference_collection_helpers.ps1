<# CLM-safe pure helper functions for V10.6.4 reference collection, validation, and reconciliation. #>
function Get-ClmRelativePath {
    [CmdletBinding()]
    param([string]$BasePath = '', [string]$FullPath = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($BasePath -eq '' -or $FullPath -eq '') { throw 'BasePath and FullPath are required.' }
    $base = $BasePath -replace '\\+$', ''
    if ($FullPath -imatch ('^' + [regex]::Escape($base) + '\\(.+)$')) { return $matches[1] }
    return $FullPath
}

function Test-ClmPolicyOptionsValid {
    [CmdletBinding()]
    param([string[]]$PolicyOptions = @(), [bool]$RequireSupplemental = $true, [string]$PolicyLabel = 'policy')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $hasSupplemental = $false
    $hasAuditMode = $false
    foreach ($opt in $PolicyOptions) {
        if ($opt -eq 'Enabled:Allow Supplemental Policies') { $hasSupplemental = $true }
        if ($opt -eq 'Enabled:Audit Mode') { $hasAuditMode = $true }
    }
    if ($hasAuditMode) { throw "$PolicyLabel is in Audit Mode; failing closed." }
    if ($RequireSupplemental -and -not $hasSupplemental) { throw "$PolicyLabel is missing Allow Supplemental Policies." }
    return $true
}

function Get-ClmOptionalRegistryValue {
    [CmdletBinding()]
    param([string]$Path = '', [string]$ValueName = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($Path -eq '' -or $ValueName -eq '') { throw 'Path and ValueName are required.' }
    try {
        $obj = Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop
        return [ordered]@{ present=$true; value=$obj.$ValueName }
    } catch {
        return [ordered]@{ present=$false; value=$null }
    }
}

function Get-ClmNetstatTcpListeners {
    [CmdletBinding()]
    param([string]$NetstatPath = '', [int]$TargetPort = 0)
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($NetstatPath -eq '') { throw 'NetstatPath is required.' }
    $listeners = @()
    $foundPort = $false
    $output = & $NetstatPath -ano 2>$null
    foreach ($line in $output) {
        if ($line -match '^\s*TCP\s+([0-9.]+):(\d+)\s+.*\s+LISTENING\s+(\d+)\s*$') {
            $port = [int]$matches[2]
            $entry = [ordered]@{ local_address=$matches[1]; local_port=$port; state='LISTENING'; pid=[int]$matches[3] }
            $listeners += $entry
            if ($TargetPort -gt 0 -and $port -eq $TargetPort) { $foundPort = $true }
        }
    }
    return [ordered]@{ tcp_8082_present=$foundPort; listeners=$listeners }
}

function Get-ClmProcessEvidence {
    [CmdletBinding()]
    param([string]$ProcessName = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($ProcessName -eq '') { throw 'ProcessName is required.' }
    $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    $evidence = @()
    foreach ($p in $procs) {
        $exePath = ''
        try { $exePath = $p.MainModule.FileName } catch { $exePath = '' }
        $evidence += [ordered]@{ pid=$p.Id; executable_path=$exePath; command_line_available=$false }
    }
    ,@($evidence)
}

function Get-ClmUninstallerEvidence {
    [CmdletBinding()]
    param([string]$InstallRoot = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($InstallRoot -eq '' -or -not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { throw 'InstallRoot is required and must exist.' }
    $certUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
    $found = @()
    Get-ChildItem -LiteralPath $InstallRoot -Filter 'unins*.exe' -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $hash = ''
        $out = & $certUtil -hashfile $_.FullName SHA256 2>$null
        $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' })
        if ($hashes.Count -eq 1) { $hash = $hashes[0] }
        $found += [ordered]@{ filename=$_.Name; relative_path=(Get-ClmRelativePath -BasePath $InstallRoot -FullPath $_.FullName); sha256=$hash; size=$_.Length }
    }
    if ($found.Count -eq 0) { throw 'No generated Inno uninstaller found under InstallRoot.' }
    if ($found.Count -gt 1) { throw "Multiple uninstallers found ($($found.Count)); failing closed." }
    return $found[0]
}

function Get-ClmCodeIntegrityEvidence {
    [CmdletBinding()]
    param([int]$MaxEvents = 10)
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    try {
        $events = @(Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents $MaxEvents -ErrorAction Stop)
        $entries = @()
        foreach ($evt in $events) {
            $entries += [ordered]@{ timestamp=$evt.TimeCreated.ToString('yyyy-MM-ddTHH:mm:ssZ'); event_id=$evt.Id; level=$evt.LevelDisplayName; message=$evt.Message }
        }
        return [ordered]@{ available=$true; error=$null; events=$entries }
    } catch {
        return [ordered]@{ available=$false; error=$_.Exception.Message; events=@() }
    }
}

function Get-ClmPolicyEvidence {
    [CmdletBinding()]
    param([string]$ExpectedBasePolicyId = '', [string]$ExpectedBootstrapPolicyId = '', [string]$ExpectedBootstrapFriendlyName = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($ExpectedBasePolicyId -eq '' -or $ExpectedBootstrapPolicyId -eq '') { throw 'Expected policy IDs are required.' }
    if (-not (Get-Command CiTool.exe -ErrorAction SilentlyContinue)) { throw 'CiTool.exe not found.' }
    $result = & CiTool.exe -lp -json 2>$null | ConvertFrom-Json
    if ($result.OperationResult -ne 0) { throw 'CiTool -lp returned non-zero OperationResult.' }
    $base = @($result.Policies | Where-Object { $_.PolicyID -eq $ExpectedBasePolicyId })
    $bootstrap = @($result.Policies | Where-Object { $_.PolicyID -eq $ExpectedBootstrapPolicyId })
    if ($base.Count -ne 1) { throw "Canonical Lab Base not uniquely present (found $($base.Count))." }
    if ($bootstrap.Count -ne 1) { throw "Bootstrap policy not uniquely present (found $($bootstrap.Count))." }
    if ($bootstrap[0].IsOnDisk -ne $true -or $bootstrap[0].IsEnforced -ne $true -or $bootstrap[0].IsAuthorized -ne $true) { throw 'Bootstrap policy is not OnDisk/Enforced/Authorized.' }
    Test-ClmPolicyOptionsValid -PolicyOptions @($base[0].PolicyOptions) -RequireSupplemental $true -PolicyLabel 'Canonical Lab Base'
    $bootstrapOptions = @($bootstrap[0].PolicyOptions)
    if ($bootstrapOptions.Count -gt 0) { Test-ClmPolicyOptionsValid -PolicyOptions $bootstrapOptions -RequireSupplemental $false -PolicyLabel 'Bootstrap supplemental policy' }
    return [ordered]@{
        base=[ordered]@{ policy_id=$base[0].PolicyID; base_policy_id=$base[0].BasePolicyID; friendly_name=$base[0].FriendlyName; is_on_disk=$base[0].IsOnDisk; is_enforced=$base[0].IsEnforced; is_authorized=$base[0].IsAuthorized; policy_options=@($base[0].PolicyOptions); audit_mode=$false }
        bootstrap=[ordered]@{ policy_id=$bootstrap[0].PolicyID; base_policy_id=$bootstrap[0].BasePolicyID; friendly_name=$bootstrap[0].FriendlyName; version=$bootstrap[0].Version; is_on_disk=$bootstrap[0].IsOnDisk; is_enforced=$bootstrap[0].IsEnforced; is_authorized=$bootstrap[0].IsAuthorized; policy_options=$bootstrapOptions; audit_mode=$false }
    }
}

function Compare-ClmInventory {
    [CmdletBinding()]
    param([array]$Expected = @(), [array]$Live = @())
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($Expected.Count -eq 0) { throw 'Expected inventory is empty.' }
    if ($Live.Count -ne $Expected.Count) { throw "Live inventory count ($($Live.Count)) does not match expected ($($Expected.Count))." }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        $e = $Expected[$i]; $l = $Live[$i]
        if ($l.relative_path -ine $e.relative_path) { throw ('Inventory drift at index {0}: path ''{1}'' vs ''{2}''.' -f $i, $l.relative_path, $e.relative_path) }
        if ($l.sha256 -ine $e.sha256) { throw ('Inventory drift at index {0}: hash mismatch for {1}.' -f $i, $l.relative_path) }
        if ("$($l.size)" -ne "$($e.size)") { throw ('Inventory drift at index {0}: size mismatch for {1}.' -f $i, $l.relative_path) }
    }
    return $true
}

function Test-ClmAuditModeRejection {
    [CmdletBinding()]
    param([string[]]$PolicyOptions = @(), [string]$PolicyLabel = 'policy')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $hasAuditMode = $false
    foreach ($opt in $PolicyOptions) { if ($opt -eq 'Enabled:Audit Mode') { $hasAuditMode = $true } }
    if ($hasAuditMode) { throw "$PolicyLabel is in Audit Mode; failing closed." }
    return $true
}

function Test-ClmBasePolicyInvariant {
    [CmdletBinding()]
    param([hashtable]$Policy = @{}, [string]$ExpectedPolicyId = '', [string]$ExpectedBasePolicyId = '', [string]$ExpectedFriendlyName = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($Policy.policy_id -ne $ExpectedPolicyId) { throw "PolicyID mismatch: expected $ExpectedPolicyId got $($Policy.policy_id)." }
    if ($Policy.base_policy_id -ne $ExpectedBasePolicyId) { throw "BasePolicyID mismatch: expected $ExpectedBasePolicyId got $($Policy.base_policy_id)." }
    if ($Policy.friendly_name -ne $ExpectedFriendlyName) { throw "FriendlyName mismatch: expected $ExpectedFriendlyName got $($Policy.friendly_name)." }
    if ($Policy.is_on_disk -ne $true) { throw 'Policy is not OnDisk.' }
    if ($Policy.is_enforced -ne $true) { throw 'Policy is not Enforced.' }
    if ($Policy.is_authorized -ne $true) { throw 'Policy is not Authorized.' }
    Test-ClmPolicyOptionsValid -PolicyOptions @($Policy.policy_options) -RequireSupplemental $true -PolicyLabel $ExpectedFriendlyName
    return $true
}

function Get-ClmLiveInventory {
    [CmdletBinding()]
    param([string]$InstallRoot = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($InstallRoot -eq '' -or -not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { throw 'InstallRoot is required and must exist.' }
    $certUtil = Join-Path $env:SystemRoot 'System32\certutil.exe'
    $inventory = @()
    Get-ChildItem -LiteralPath $InstallRoot -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relPath = Get-ClmRelativePath -BasePath $InstallRoot -FullPath $_.FullName
        $hash = ''
        $out = & $certUtil -hashfile $_.FullName SHA256 2>$null
        $hashes = @($out | Where-Object { $_ -match '^\s*[0-9A-Fa-f]{64}\s*$' } | ForEach-Object { $_ -replace '^\s+|\s+$','' })
        if ($hashes.Count -eq 1) { $hash = $hashes[0] }
        $inventory += [ordered]@{ relative_path=$relPath; sha256=$hash; size=$_.Length; is_pe=($_.Extension -in @('.exe','.dll','.sys','.ocx')) }
    }
    return $inventory
}
