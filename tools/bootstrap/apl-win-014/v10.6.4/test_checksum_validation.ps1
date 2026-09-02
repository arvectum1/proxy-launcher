<# Behavioral fixture test for the V10.7 CLM-safe checksum parser. #>
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'checksum_validation.ps1')
$fixtures = Join-Path $scriptDir 'fixtures'
if ((Get-ChecksumEvidenceHash -ChecksumPath (Join-Path $fixtures 'sha256sums_reference_capture.txt') -ExpectedFileName 'reference-capture.json') -ne ('a' * 64)) { throw 'Checksum parser did not return the expected SHA256.' }
$failedClosed = $false
try { Get-ChecksumEvidenceHash -ChecksumPath (Join-Path $fixtures 'sha256sums_malformed.txt') -ExpectedFileName 'reference-capture.json' | Out-Null } catch { $failedClosed = $true }
if (-not $failedClosed) { throw 'Checksum parser accepted a malformed checksum record.' }
Write-Host 'RESULT: PASS'
