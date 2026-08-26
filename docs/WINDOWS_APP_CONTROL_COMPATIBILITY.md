# APL-WIN-014 — Windows application-control execution compatibility

Status: **REAL ENFORCED ACCEPTANCE PAUSED / PACKAGING HARDENING REQUIRED**

## Security boundary

Arvectum's Russian detached CryptoPro/Rutoken release signature proves release-set provenance and integrity. It is **not** Microsoft Authenticode execution trust. App Control for Business admission is a separate control plane.

Non-negotiable rules:

1. Do not disable or weaken App Control for Business, Smart App Control or Defender to make Arvectum run.
2. Do not change `VerifiedAndReputablePolicyState` from product tooling.
3. Do not represent detached Russian release evidence as Authenticode/SmartScreen trust.
4. Arvectum release tooling may generate customer trust artifacts but must not silently deploy or remove customer policy.
5. Any destructive Audit -> Enforced acceptance requires a separately proven recovery path that already ran successfully inside the actual Enforced language/runtime restrictions.

## Real ARVECTUM-DEMO result — 2026-08-26

The physical Windows 11 Enterprise acceptance stand **ARVECTUM-DEMO** exposed three production-significant gaps in the sealed `0.2.3` Windows packaging after the dedicated APL-WIN-014 base policy moved from Audit to Enforced.

### 1. PyInstaller `onefile` is not a deterministic App Control runtime

The exact `Arvectum Proxy Launcher.exe` was hash-authorized, but PyInstaller `onefile` extracted executable support files to `%TEMP%\_MEI...`. App Control blocked `python312.dll` first and the process failed with `Bad Image`.

The emergency recovery proved that exact hashes for the full `_MEI` DLL/PYD runtime were required before `0.2.3` could start under Enforced policy. Runtime discovery after cutover is not an acceptable production trust model.

**Canonical direction:** Windows production packaging must use PyInstaller `onedir` (static one-folder runtime). Every executable DLL/PYD/runtime artifact must exist in the release tree before deployment and be included in release hashes and the App Control trust pack. No `_MEI` runtime discovery is allowed for the enterprise profile.

### 2. The single-file Inno Setup loader is not covered by Setup-EXE trust alone

The exact sealed Setup EXE itself was admitted, but installation failed with **Error 4551** because Inno Setup executed an internal temporary loader/helper that was not authorized by App Control.

**Canonical direction:** the enterprise installer path must not depend on an untrusted executable copied to `%TEMP%`. The Inno profile must use an App-Control-compatible loader/layout and the complete installer execution set must be known before deployment.

### 3. PowerShell recovery was not valid under Enforced policy

The cutover's recovery path had passed Audit preflight, but after enforcement PowerShell entered `ConstrainedLanguage`. Recovery then failed on method invocation that was legal in FullLanguage.

**Canonical direction:** neither production maintenance nor emergency recovery may depend on unproven FullLanguage PowerShell after cutover. Recovery must be an independently testable artifact and must be rehearsed under Enforced/`ConstrainedLanguage` before a destructive transition is permitted.

## Current stand state

ARVECTUM-DEMO was recovered without weakening the base policy:

- dedicated APL-WIN-014 base remains **Enforced**;
- current supplemental remains active and was expanded with exact hashes from the observed `0.2.3` PyInstaller runtime solely as emergency stand recovery;
- exact portable `0.2.3` is running;
- PAC responds HTTP 200;
- temporary manual Windows proxy is off;
- WinINET PAC is restored to `http://127.0.0.1:8082/proxy.pac`;
- **acceptance remains paused**.

The emergency runtime-expanded supplemental is recovery evidence, not the production packaging design.

## Target enterprise packaging contract

### Static application runtime

The canonical Windows build must:

- use PyInstaller `onedir`, never `onefile`;
- publish a stable `runtime/` subtree in the portable package;
- include `runtime/Arvectum Proxy Launcher.exe` plus all DLL/PYD/support files required by that exact build;
- emit `RUNTIME_SHA256SUMS.txt` binding every file in the runtime tree;
- record runtime file count and a deterministic runtime-tree digest in `build-result.json`;
- install the same static runtime tree byte-for-byte.

### App Control trust pack

Canonical generator:

`tools/windows_app_control_enterprise_trust_pack.ps1`

The forward enterprise mode is `StaticRuntimeHash`. It must hash the complete static runtime tree plus every executable installer/maintenance artifact required by the lifecycle.

Generated supplemental XML must be sanitized so rule option 3 (`Enabled:Audit Mode`) is absent before conversion to `.cip`. The generator must preserve the customer base-policy relationship and must never deploy the policy itself.

The historical sealed `0.2.3` `ReferenceFullHash` profile is retained only as evidence of the old design. The real stand proved that scanning the installed tree was insufficient for a PyInstaller `onefile` runtime because `_MEI` files did not exist in that tree before launch.

### Installer and maintenance

Enterprise-compatible installation must satisfy all of these before APL-WIN-014 can resume:

- no hidden Setup loader/helper executable may appear only after launch and require ad-hoc trust;
- no `ExtractTemporaryFile(... .ps1)` + Windows PowerShell maintenance chain under Enforced policy;
- fresh install, repair, upgrade and uninstall must use only pre-authorized static artifacts and Windows/Inno primitives compatible with the effective policy;
- rollback must remain fail-closed when network recovery cannot be proven;
- durable `proxy_settings.json` and `no_proxy.txt` must survive upgrade/repair/uninstall as defined by the product lifecycle contract.

## Acceptance gate before another physical cutover

A physical Audit -> Enforced transition is prohibited until all items below are green in an isolated Windows acceptance environment:

1. static `onedir` runtime build and exact runtime-tree manifest;
2. enterprise installer execution without App Control event 3077 for Arvectum artifacts;
3. clean install and first start under Enforced;
4. PAC/listener/WinINET runtime proof without relying on GUI `--status` stdout;
5. repair under Enforced;
6. version-transition upgrade under Enforced;
7. uninstall under Enforced;
8. recovery artifact executed successfully while policy is already Enforced and PowerShell is in the actual effective language mode;
9. recovery restores exact current release, durable configuration and PAC without returning the base policy to Audit;
10. final cutover driver refuses to proceed without immutable Enforced-rehearsal evidence.

Only after this matrix passes may APL-WIN-014 return to ARVECTUM-DEMO.

## Managed Installer profile

A customer-governed Managed Installer remains a possible fleet profile when the customer's security model accepts it. It does not remove the requirement for Arvectum's own packages to have a deterministic, inspectable runtime layout. Self-generated/self-updated bytes must never be assumed trusted merely because the initial package came through a Managed Installer.

## Public/unmanaged Windows distribution

Public Smart App Control / SmartScreen trust remains a separate track from Russian release provenance and from organization-managed App Control for Business. Russian-first embedded code-signing research continues under the release-signing roadmap; international trust providers remain lower priority.

## Related evidence

- GitHub issue #10 — `[Win] APL-WIN-014 harden Enforced App Control packaging and recovery after ARVECTUM-DEMO incident`.
- `docs/evidence/APL_REL_014_OWNER_HOST_INCIDENT_2026-08-20.md` — earlier owner-host destructive acceptance boundary.
- `tools/windows_app_control_enforced_acceptance.ps1` — historical sealed `0.2.3` acceptance harness; it must not be rerun on the physical stand until this hardening work is complete.
