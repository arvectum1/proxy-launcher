from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / "tools" / "windows_app_control_enforced_acceptance.ps1"
FINAL = ROOT / "tools" / "windows_app_control_local_gate_complete.ps1"
PREVERIFIED = ROOT / "tools" / "windows_app_control_preverified_release.ps1"
READINESS = ROOT / "tools" / "windows_app_control_enforced_readiness.ps1"


class WindowsAppControlFinalLocalGateContractTests(unittest.TestCase):
    def test_canonical_gate_requires_real_historical_baseline_and_exact_current(self):
        text = CANONICAL.read_text(encoding="utf-8")
        for expected in (
            "0ea08d9c815da36d0175f62db153de78f89731fc",
            "574d3dc5f90a116555e3a72ff3288c31c19d3dc7",
            "7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0",
            "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414",
            "f8d98f987ce92dee7979b12b69a56d120ddb12244bebe2559bc51359a53f9c7a",
            "real_cross_version_upgrade",
            "post_upgrade_exact_bytes",
            "state_preserved",
        ):
            self.assertIn(expected, text)

    def test_canonical_gate_requires_true_enforcement_not_audit_mode(self):
        text = CANONICAL.read_text(encoding="utf-8")
        for expected in (
            "CiTool",
            "-lp -json",
            "is_enforced",
            "is_on_disk",
            "policy_options",
            "Enabled:Audit Mode",
            "real enforced acceptance is blocked",
            "Baseline supplemental policy is not active/on-disk",
            "Current supplemental policy is not active/on-disk",
        ):
            self.assertIn(expected, text)

    def test_canonical_gate_does_not_deploy_remove_or_weaken_policy(self):
        lowered = CANONICAL.read_text(encoding="utf-8").lower()
        for forbidden in (
            "--update-policy",
            "--remove-policy",
            "verifiedandreputablepolicystate",
            "set-ruleoption",
            "disable-windowsoptionalfeature",
        ):
            self.assertNotIn(forbidden, lowered)

    def test_canonical_gate_uses_canonical_setup_and_never_alias(self):
        text = CANONICAL.read_text(encoding="utf-8")
        helper = PREVERIFIED.read_text(encoding="utf-8")
        self.assertIn("Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe", helper)
        self.assertIn("retired compatibility Setup alias", helper)
        self.assertNotIn("ArvectumProxyLauncher-Setup-0.2.3.exe", text)

    def test_canonical_gate_does_not_use_gui_status_stdout(self):
        text = CANONICAL.read_text(encoding="utf-8")
        self.assertNotIn("--status", text)
        self.assertNotIn("system proxy:\\s*ENABLED", text)
        self.assertNotIn("-notmatch 'RUNNING'", text)
        for expected in (
            "Get-NetTCPConnection",
            "127.0.0.1:8082",
            "proxy.pac",
            "AutoConfigURL",
            "ExecutablePath",
        ):
            self.assertIn(expected, text)

    def test_start_is_asynchronous_and_rollback_has_timeout(self):
        text = CANONICAL.read_text(encoding="utf-8")
        self.assertIn("Intentionally no -Wait", text)
        self.assertIn("Start-Process -FilePath $Installed.exe -ArgumentList @('--start') -PassThru", text)
        self.assertIn("WaitForExit(20000)", text)

    def test_current_lifecycle_includes_repair_and_uninstall(self):
        text = CANONICAL.read_text(encoding="utf-8")
        for expected in (
            "current_clean_install_exact",
            "current_pac_http",
            "current_wininet_autoconfig",
            "current_rollback",
            "current_repair_from_missing_exe",
            "current_uninstall",
            "Arvectum Proxy Launcher Repair.exe",
        ):
            self.assertIn(expected, text)

    def test_canonical_gate_checks_code_integrity_blocks_and_post_state(self):
        text = CANONICAL.read_text(encoding="utf-8")
        for expected in (
            "Microsoft-Windows-CodeIntegrity/Operational",
            "3077",
            "arvectum_3077_block_events",
            "no_arvectum_enforcement_blocks",
            "app_control_remained_enforced",
        ):
            self.assertIn(expected, text)

    def test_preverified_release_is_exact_hash_bound_and_does_not_claim_microsoft_trust(self):
        text = PREVERIFIED.read_text(encoding="utf-8")
        for expected in (
            "67d379db11a238960b9324c8054e73790cf18b1eaa85db8c04a9226bb27bc58e",
            "47823585c42da54ab51dc2246583dc24d74d4ba6",
            "rel011_detached_signature_verified",
            "rel012_exact_release_verification",
            "rel013_publication_decision",
            "embedded_authenticode_claimed",
            "smartscreen_trust_claimed",
            "PREVERIFIED_EXACT_HASH_BOUND",
        ):
            self.assertIn(expected, text)
        self.assertNotIn("CRYPTO_PRO_CSPTEST_PATH", text)
        self.assertNotIn("csptest", text.lower())

    def test_final_wrapper_uses_readiness_barrier_before_canonical_gate(self):
        text = FINAL.read_text(encoding="utf-8")
        self.assertIn("windows_app_control_enforced_readiness.ps1", text)
        self.assertIn("windows_app_control_enforced_acceptance.ps1", text)
        self.assertLess(text.index("& $readiness"), text.index("& $canonical"))
        for expected in (
            "readiness_gate = 'NOT_RUN'",
            "$final.readiness_gate = 'PASS'",
            "upgrade_gate = 'NOT_RUN'",
            "current_release_gate = 'NOT_RUN'",
            "$final.upgrade_gate = 'PASS'",
            "$final.current_release_gate = 'PASS'",
        ):
            self.assertIn(expected, text)

    def test_readiness_blocks_known_unsafe_v03_referencefullhash_path(self):
        text = READINESS.read_text(encoding="utf-8")
        for expected in (
            "windows-app-control-enterprise-trust-pack.v1",
            "ReferenceFullHash",
            "PyInstaller onefile is prohibited",
            "packaging_layout=static-runtime",
            "runtime_complete",
            "installer_lifecycle_complete",
            "enforced_lifecycle_ready",
            "Enforced/ConstrainedLanguage",
            "restores_exact_current_release",
            "restores_pac_connectivity",
            "changes_base_to_audit",
            "issue #10",
        ):
            self.assertIn(expected, text)

    def test_readiness_never_manages_policy(self):
        lowered = READINESS.read_text(encoding="utf-8").lower()
        for forbidden in (
            "--update-policy",
            "--remove-policy",
            "set-ruleoption",
            "set-mppreference",
            "verifiedandreputablepolicystate",
        ):
            self.assertNotIn(forbidden, lowered)

    def test_final_wrapper_is_host_only_and_does_not_manage_policy(self):
        text = FINAL.read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertIn("IsolatedAcceptanceEnvironment", text)
        self.assertIn("dedicated/isolated Windows 11", text)
        for forbidden in ("--update-policy", "--remove-policy", "Set-RuleOption"):
            self.assertNotIn(forbidden.lower(), lowered)


if __name__ == "__main__":
    unittest.main()
