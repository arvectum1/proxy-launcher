from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECOVER = ROOT / "tools" / "windows_app_control_recover_0_2_2_baseline.ps1"
TRUST = ROOT / "tools" / "windows_app_control_legacy_baseline_trust_pack.ps1"
UPGRADE = ROOT / "tools" / "windows_app_control_upgrade_acceptance.ps1"
CANONICAL = ROOT / "tools" / "windows_app_control_enforced_acceptance.ps1"
FINAL = ROOT / "tools" / "windows_app_control_local_gate_complete.ps1"
ALIAS = ROOT / "tools" / "windows_app_control_current_release_alias.ps1"
DOC = ROOT / "docs" / "evidence" / "APL_WIN_014_0_2_2_BASELINE_RECONCILIATION_2026-08-25.md"

COMMIT = "0ea08d9c815da36d0175f62db153de78f89731fc"
BLOB = "574d3dc5f90a116555e3a72ff3288c31c19d3dc7"
APP_SHA = "7ef02652e31bbbd68833be599135cf59519c42b1f8a8febb580b3891ffc35ec0"
QA_BLOB = "163e61cd2e1d8ff798289faf075775af8f9bbd41"
CURRENT_SETUP_SHA = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"


class WindowsAppControlLegacyBaselineContractTests(unittest.TestCase):
    def test_recovery_is_bound_to_immutable_historical_package_and_never_rebuilds(self):
        text = RECOVER.read_text(encoding="utf-8")
        for expected in (COMMIT, BLOB, QA_BLOB, APP_SHA, "15963815", "git archive", "cat-file"):
            self.assertIn(expected, text)
        self.assertIn("This script NEVER rebuilds 0.2.2", text)
        self.assertIn("package_root", text)
        self.assertIn("application_relative_path", text)

    def test_recovery_supports_clean_acceptance_stand_without_git(self):
        text = RECOVER.read_text(encoding="utf-8")
        for expected in (
            "HistoricalPackageZipPath",
            "HistoricalQaEvidencePath",
            "Get-GitBlobSha1",
            '"blob $($item.Length)`0"',
            "DownloadedImmutableGitBlob",
            "git.exe and a working copy are",
        ):
            self.assertIn(expected, text)
        self.assertIn("requires BOTH -HistoricalPackageZipPath and -HistoricalQaEvidencePath", text)

    def test_baseline_trust_pack_is_exact_hash_and_includes_historical_scripts(self):
        text = TRUST.read_text(encoding="utf-8")
        for expected in (COMMIT, BLOB, APP_SHA, "LegacyPackageExactHash", "-Level Hash", "install.ps1", "uninstall.ps1"):
            self.assertIn(expected, text)
        self.assertIn("New-CIPolicy -MultiplePolicyFormat -ScanPath $packageRoot -UserPEs -NoShadowCopy", text)
        self.assertIn("Deployment: NOT PERFORMED", text)

    def test_baseline_tools_never_deploy_remove_or_weaken_app_control(self):
        lowered = (RECOVER.read_text(encoding="utf-8") + TRUST.read_text(encoding="utf-8")).lower()
        for forbidden in ("& $citool --update-policy", "& $citool --remove-policy", "verifiedandreputablepolicystate", "set-ruleoption"):
            self.assertNotIn(forbidden, lowered)

    def test_upgrade_gate_uses_recovered_legacy_baseline_as_canonical_mode(self):
        text = UPGRADE.read_text(encoding="utf-8")
        for expected in (
            "LegacyClientZip",
            "BaselineManifestPath",
            "BaselineTrustPackDirectory",
            COMMIT,
            BLOB,
            APP_SHA,
            "baseline_exact_historical_bytes",
            "baseline_gui_execution_under_enforcement",
            "real_cross_version_upgrade",
            "state_preserved",
            "post_upgrade_exact_bytes",
            "3077",
            "same-version repair is not accepted as upgrade evidence",
        ):
            self.assertIn(expected, text)

    def test_current_release_alias_only_duplicates_exact_sealed_setup_bytes(self):
        text = ALIAS.read_text(encoding="utf-8")
        for expected in (
            CURRENT_SETUP_SHA,
            "Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe",
            "ArvectumProxyLauncher-Setup-0.2.3.exe",
            "Copy-Item -LiteralPath $canonical -Destination $alias",
            "Promoted artifact mutation: NONE",
        ):
            self.assertIn(expected, text)

    def test_canonical_enforced_gate_consumes_legacy_recovery_and_trust_evidence(self):
        text = CANONICAL.read_text(encoding="utf-8")
        for expected in (
            "BaselineManifestPath",
            "BaselineTrustPackDirectory",
            COMMIT,
            BLOB,
            APP_SHA,
            "LegacyClientZip",
            "Historical 0.2.2 P0.4",
            "real_cross_version_upgrade",
        ):
            self.assertIn(expected, text)

    def test_final_gate_wires_readiness_then_canonical_enforced_acceptance(self):
        text = FINAL.read_text(encoding="utf-8")
        for expected in (
            "LegacyClientZip",
            "BaselineManifestPath",
            "BaselineTrustPackDirectory",
            "Historical 0.2.2 P0.4 -> exact current",
            "windows_app_control_enforced_readiness.ps1",
            "windows_app_control_enforced_acceptance.ps1",
            "windows_app_control_preverified_release.ps1",
        ):
            self.assertIn(expected, text)
        self.assertLess(text.index("& $readiness"), text.index("& $canonical"))
        for retired in (
            "windows_app_control_upgrade_acceptance.ps1",
            "windows_app_control_local_gate.ps1",
            "windows_app_control_current_release_alias.ps1",
        ):
            self.assertNotIn(retired, text)

    def test_canonical_web_evidence_records_exact_baseline_and_local_boundary(self):
        text = DOC.read_text(encoding="utf-8")
        for expected in (COMMIT, BLOB, QA_BLOB, "CUSTOMER UPDATE INSTALLER: APPROVED", "77/77", "WEB RECONCILIATION: PASS", "LOCAL APP CONTROL ACCEPTANCE: PENDING"):
            self.assertIn(expected, text)
        self.assertIn(APP_SHA.upper(), text.upper())


if __name__ == "__main__":
    unittest.main()
