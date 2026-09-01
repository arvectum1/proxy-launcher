# APL-WIN-014 V10.6.3 Artifact Identity Status

Status: NOT APPROVED FOR REAL-STAND CUTOVER.

The immutable `apl-win-014-v10.6.3-bootstrap-transfer` release remains preserved as engineering evidence and must not be deleted or changed. It is superseded by V10.6.4 because its setup and loose application payload were selected from separate build invocations. Equal source commits do not prove equal application bytes for hash-based App Control.

V10.6.4 must build the application once, compile setup from that verified payload, prove the installed application hash equals the frozen payload hash, and publish only those bytes.
