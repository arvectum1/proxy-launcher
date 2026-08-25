from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UPGRADE = ROOT / "tools" / "windows_app_control_upgrade_acceptance.ps1"
FINAL = ROOT / "tools" / "windows_app_control_local_gate_complete.ps1"


def test_upgrade_gate_requires_distinct_baseline_and_exact_hashes():
    text = UPGRADE.read_text(encoding="utf-8")
    assert "BaselineSetupSha256" in text
    assert "BaselineApplicationSha256" in text
    assert "BaselineVersion" in text
    assert "BaselineSupplementalPolicyId" in text
    assert "BaselineManifestPath" in text
    assert "BaselineTrustPackDirectory" in text
    assert "same-version repair is not accepted as upgrade evidence" in text
    assert "real_cross_version_upgrade" in text
    assert "post_upgrade_exact_bytes" in text
    assert "state_preserved" in text


def test_upgrade_gate_requires_active_enforced_app_control():
    text = UPGRADE.read_text(encoding="utf-8")
    assert "CiTool" in text
    assert "-lp -json" in text
    assert "is_enforced" in text
    assert "is_on_disk" in text
    assert "Base App Control policy is not enforced/on-disk" in text
    assert "Baseline supplemental policy is not active/on-disk" in text
    assert "Current supplemental policy is not active/on-disk" in text


def test_upgrade_gate_does_not_deploy_or_weaken_policy():
    text = UPGRADE.read_text(encoding="utf-8").lower()
    assert "& $citool --update-policy" not in text
    assert "& $citool --remove-policy" not in text
    assert "verifiedandreputablepolicystate" not in text
    assert "set-ruleoption" not in text


def test_upgrade_gate_checks_code_integrity_blocks_and_post_state():
    text = UPGRADE.read_text(encoding="utf-8")
    assert "Microsoft-Windows-CodeIntegrity/Operational" in text
    assert "3077" in text
    assert "no_upgrade_enforcement_blocks" in text
    assert "app_control_remained_enforced" in text
    assert "post_upgrade_uninstall" in text


def test_upgrade_gate_uses_real_recovered_0_2_2_as_canonical_baseline():
    text = UPGRADE.read_text(encoding="utf-8")
    assert "LegacyClientZip" in text
    assert "0ea08d9c815da36d0175f62db153de78f89731fc" in text
    assert "574d3dc5f90a116555e3a72ff3288c31c19d3dc7" in text
    assert "baseline_exact_historical_bytes" in text
    assert "baseline_gui_execution_under_enforcement" in text


def test_final_gate_cannot_pass_without_upgrade_and_current_release_subgates():
    text = FINAL.read_text(encoding="utf-8")
    assert "windows_app_control_upgrade_acceptance.ps1" in text
    assert "windows_app_control_local_gate.ps1" in text
    assert "upgrade_gate = 'NOT_RUN'" in text
    assert "current_release_gate = 'NOT_RUN'" in text
    assert "$final.upgrade_gate = 'PASS'" in text
    assert "$final.current_release_gate = 'PASS'" in text
    assert "if ($final.result -ne 'PASS')" in text
    assert "Historical 0.2.2 P0.4 -> exact 0.2.3 cross-version upgrade: PASS" in text


def test_final_gate_is_host_only_and_does_not_manage_app_control_policy():
    text = FINAL.read_text(encoding="utf-8")
    lowered = text.lower()
    assert "IsolatedAcceptanceEnvironment" in text
    assert "dedicated/isolated Windows 11 acceptance host" in text
    assert "LegacyClientZip" in text
    assert "--update-policy" not in lowered
    assert "--remove-policy" not in lowered
    assert "VerifiedAndReputablePolicyState" not in text
