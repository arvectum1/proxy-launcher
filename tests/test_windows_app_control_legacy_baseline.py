from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RECOVER = ROOT / "tools" / "windows_app_control_recover_0_2_2_baseline.ps1"
TRUST = ROOT / "tools" / "windows_app_control_legacy_baseline_trust_pack.ps1"
UPGRADE = ROOT / "tools" / "windows_app_control_upgrade_acceptance.ps1"
FINAL = ROOT / "tools" / "windows_app_control_local_gate_complete.ps1"
ALIAS = ROOT / "tools" / "windows_app_control_current_release_alias.ps1"
DOC = ROOT / "docs" / "evidence" / "APL_WIN_014_0_2_2_BASELINE_RECONCILIATION_2026-08-25.md"

COMMIT = "0ea08d9c815da36d0175f62db153de78f89731fc"
BLOB = "574d3dc5f90a116555e3a72ff3288c31c19d3dc7"
APP_SHA = "7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0"
QA_BLOB = "163e61cd2e1d8ff798289faf075775af8f9bbd41"
CURRENT_SETUP_SHA = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"


def test_recovery_is_bound_to_immutable_historical_package_and_never_rebuilds():
    text = RECOVER.read_text(encoding="utf-8")
    assert COMMIT in text
    assert BLOB in text
    assert QA_BLOB in text
    assert APP_SHA in text
    assert "15963815" in text
    assert "git archive" in text
    assert "hash-object" in text
    assert "cat-file" in text
    assert "This script NEVER rebuilds 0.2.2" in text
    assert "package_root" in text
    assert "application_relative_path" in text


def test_baseline_trust_pack_is_exact_hash_and_includes_historical_scripts():
    text = TRUST.read_text(encoding="utf-8")
    assert COMMIT in text
    assert BLOB in text
    assert APP_SHA in text
    assert "LegacyPackageExactHash" in text
    assert "New-CIPolicy -MultiplePolicyFormat -ScanPath $packageRoot -UserPEs -NoShadowCopy" in text
    assert "-Level Hash" in text
    assert "install.ps1" in text
    assert "uninstall.ps1" in text
    assert "Deployment: NOT PERFORMED" in text


def test_baseline_tools_never_deploy_remove_or_weaken_app_control():
    lowered = (RECOVER.read_text(encoding="utf-8") + TRUST.read_text(encoding="utf-8")).lower()
    assert "& $citool --update-policy" not in lowered
    assert "& $citool --remove-policy" not in lowered
    assert "verifiedandreputablepolicystate" not in lowered
    assert "set-ruleoption" not in lowered


def test_upgrade_gate_uses_recovered_legacy_baseline_as_canonical_mode():
    text = UPGRADE.read_text(encoding="utf-8")
    assert "LegacyClientZip" in text
    assert "BaselineManifestPath" in text
    assert "BaselineTrustPackDirectory" in text
    assert COMMIT in text
    assert BLOB in text
    assert APP_SHA in text
    assert "baseline_exact_historical_bytes" in text
    assert "baseline_gui_execution_under_enforcement" in text
    assert "real_cross_version_upgrade" in text
    assert "state_preserved" in text
    assert "post_upgrade_exact_bytes" in text
    assert "3077" in text
    assert "same-version repair is not accepted as upgrade evidence" in text


def test_current_release_alias_only_duplicates_exact_sealed_setup_bytes():
    text = ALIAS.read_text(encoding="utf-8")
    assert CURRENT_SETUP_SHA in text
    assert "Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe" in text
    assert "ArvectumProxyLauncher-Setup-0.2.3.exe" in text
    assert "Copy-Item -LiteralPath $canonical -Destination $alias" in text
    assert "Promoted artifact mutation: NONE" in text


def test_final_gate_wires_legacy_recovery_and_trust_evidence():
    text = FINAL.read_text(encoding="utf-8")
    assert "LegacyClientZip" in text
    assert "BaselineManifestPath" in text
    assert "BaselineTrustPackDirectory" in text
    assert "Historical 0.2.2 P0.4 -> exact 0.2.3" in text
    assert "windows_app_control_upgrade_acceptance.ps1" in text
    assert "windows_app_control_local_gate.ps1" in text
    assert "windows_app_control_current_release_alias.ps1" in text


def test_canonical_web_evidence_records_exact_baseline_and_local_boundary():
    text = DOC.read_text(encoding="utf-8")
    assert COMMIT in text
    assert BLOB in text
    assert QA_BLOB in text
    assert APP_SHA.upper() in text.upper()
    assert "CUSTOMER UPDATE INSTALLER: APPROVED" in text
    assert "77/77" in text
    assert "WEB RECONCILIATION: PASS" in text
    assert "LOCAL APP CONTROL ACCEPTANCE: PENDING" in text
