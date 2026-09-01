# APL-WIN-014 V10.6.4 Headless Initialization Contract

`setup.exe /HELP` is an interactive Inno Setup dialog and is not executed by
headless CI. It is not evidence of a usable non-interactive installer.

## CI_HEADLESS_INITIALIZATION

This check is `PASS` only when the exact sealed setup bytes are used by the
installer E2E and RC lifecycle E2E with these arguments:

```text
/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
```

The lifecycle evidence must prove successful PrepareToInstall, fresh install,
installed application SHA256 equality with the frozen application, repair,
upgrade, uninstall, portable transition, rollback/recovery, and Gate R6.
Every external lifecycle process has a five-minute fail-closed timeout.

## REAL_STAND_HELP_PROBE

This check remains `PENDING` until ARVECTUM-DEMO acceptance. An operator runs
the exact sealed `setup.exe /HELP`, manually closes the Inno Setup help dialog,
and records exit code 0 with no install root or runtime state created. CI must
not claim this probe passed and must not use UI automation.
