# V10.6.4 sealing-only validator

`validate_v10_6_4_candidate.ps1` validates an already-downloaded immutable GitHub artifact. It does not author, install, update, remove, or execute App Control policies and must not be used as a real-stand deployment script.

It is noninteractive and uses the Windows built-in `certutil.exe -hashfile ... SHA256` parser so hashing remains usable in Windows PowerShell 5.1 ConstrainedLanguage mode. The caller supplies all GitHub artifact identity values; each is compared fail-closed with `expected_hashes.json` before candidate contents are accepted.
