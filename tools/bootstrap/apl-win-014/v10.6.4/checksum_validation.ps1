<# CLM-safe, fail-closed SHA256SUMS parser for named evidence files. #>
function Get-ChecksumEvidenceHash {
    [CmdletBinding()]
    param([string]$ChecksumPath = '', [string]$ExpectedFileName = '')
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if ($ChecksumPath -eq '' -or $ExpectedFileName -eq '' -or -not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) { throw 'Checksum evidence path and expected filename are required.' }
    $records = @()
    foreach ($line in Get-Content -LiteralPath $ChecksumPath -Encoding ASCII) {
        if ($line -match '^\s*([0-9A-Fa-f]{64})\s\s([^\s]+)\s*$') { $records += [ordered]@{ hash=$matches[1]; file=$matches[2] } } else { throw 'Checksum evidence is malformed.' }
    }
    if ($records.Count -ne 1 -or $records[0].file -ne $ExpectedFileName) { throw 'Checksum evidence does not exactly bind the expected file.' }
    $records[0].hash
}
