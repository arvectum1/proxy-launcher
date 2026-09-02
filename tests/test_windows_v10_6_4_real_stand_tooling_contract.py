import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools/bootstrap/apl-win-014/v10.6.4'


class WindowsV1064RealStandToolingContractTests(unittest.TestCase):
    def test_directory_contains_the_source_backed_tooling_set(self):
        expected = {
            'prepare_v10_6_4_bootstrap_on_demo.ps1',
            'install_v10_6_4_bootstrap_on_demo.ps1',
            'post_deploy_v10_6_4_verification.ps1',
            'capture_v10_6_4_post_install_reference.ps1',
            'prepare_v10_7_final_on_demo.ps1',
            'retire_v10_6_2_bootstrap_on_demo.ps1',
            'configci_xml_validation.ps1',
            'checksum_validation.ps1',
            'reference_collection_helpers.ps1',
            'test_citool_schema.ps1',
            'test_configci_xml_structure.ps1',
            'test_checksum_validation.ps1',
            'test_clm_contract.ps1',
            'test_clm_runspace.ps1',
            'test_reference_collection_helpers.ps1',
            'test_audit_mode_rejection.ps1',
            'test_pre_authoring_base_only.ps1',
            'test_bootstrap_policy_identity.ps1',
            'test_deploy_authoring_provenance.ps1',
            'expected_hashes.json',
            'SEALING_ONLY_CLASSIFICATION.md',
        }
        self.assertTrue(expected.issubset({path.name for path in TOOLS.iterdir()}))

    def test_production_scripts_are_noninteractive_and_do_not_invoke_ui_help(self):
        production = [path for path in TOOLS.glob('*.ps1') if not path.name.startswith('test_')]
        self.assertGreaterEqual(len(production), 9)
        for path in production:
            text = path.read_text(encoding='utf-8-sig')
            self.assertNotIn('Parameter(Mandatory', text, path.name)
            self.assertNotIn('/HELP', text, path.name)
            self.assertNotIn('/?', text, path.name)

    def test_real_stand_hashing_uses_certutil_and_old_candidate_hashes_are_absent(self):
        old_hashes = {
            'e9f06e948ec29a33599b25650c73dd413721bdb5a47bc84394664132c4cd15d3',
            'cffe1bef2262c0eae9c8739f55fb3b015a8080cc616aeac369d066bb7a55c925',
            'bef5eb352a46dfd62f7e3a3190af2d17922bfddbcb891fcbe6631f009177264f',
        }
        text = '\n'.join(
            path.read_text(encoding='utf-8-sig')
            for path in TOOLS.glob('*.ps1')
            if not path.name.startswith('test_')
        )
        self.assertIn('certutil.exe', text)
        self.assertNotIn('Get-FileHash', text)
        self.assertFalse(any(value in text for value in old_hashes))

    def test_seal_metadata_is_bound_to_each_authoring_handoff(self):
        seal = json.loads((TOOLS / 'expected_hashes.json').read_text(encoding='utf-8'))
        self.assertEqual(seal['harness_version'], 'V10.6.4')
        for name in ('prepare_v10_6_4_bootstrap_on_demo.ps1', 'capture_v10_6_4_post_install_reference.ps1', 'prepare_v10_7_final_on_demo.ps1'):
            text = (TOOLS / name).read_text(encoding='utf-8-sig')
            self.assertIn('candidate_source_commit', text, name)
        retirement = (TOOLS / 'retire_v10_6_2_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('-ConfirmRetirement', retirement)
        self.assertIn('ReplacementPolicyId', retirement)
        self.assertIn('expectedRetirePolicyId', retirement)
        self.assertIn('V10.6.2 target is not the expected enforced retirement state.', retirement)
        self.assertIn('V10.6.4 replacement policy is not uniquely active after retirement.', retirement)

    def test_policy_ids_and_repair_cache_are_exactly_bound(self):
        install = (TOOLS / 'install_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        post_deploy = (TOOLS / 'post_deploy_v10_6_4_verification.ps1').read_text(encoding='utf-8-sig')
        capture = (TOOLS / 'capture_v10_6_4_post_install_reference.ps1').read_text(encoding='utf-8-sig')
        seal = json.loads((TOOLS / 'expected_hashes.json').read_text(encoding='utf-8'))
        self.assertIn('PolicyId', install)
        self.assertIn('PolicyId', post_deploy)
        self.assertIn('BootstrapPolicyId', capture)
        self.assertEqual(seal['repair_cache_filename'], 'Arvectum Proxy Launcher Repair.exe')
        self.assertIn('Mandatory cached repair setup is missing', capture)
        self.assertIn('Mandatory cached repair setup hash', capture)
        self.assertIn('reference_collection_helpers.ps1', post_deploy)
        self.assertIn('Get-ClmPolicyEvidence', post_deploy)

    def test_generated_policies_share_structural_validation_and_v10_7_revalidates_capture(self):
        validator = (TOOLS / 'configci_xml_validation.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Test-ConfigCiSupplementalXml', validator)
        for name in ('prepare_v10_6_4_bootstrap_on_demo.ps1', 'prepare_v10_7_final_on_demo.ps1'):
            self.assertIn('Test-ConfigCiSupplementalXml', (TOOLS / name).read_text(encoding='utf-8-sig'))
        v107 = (TOOLS / 'prepare_v10_7_final_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Compare-ClmInventory', v107)
        self.assertIn('reference_collection_helpers.ps1', v107)
        self.assertIn('ExpectedPolicyVersion', validator)
        self.assertNotIn('[xml]', validator)
        self.assertNotIn('.SelectNodes(', validator)
        self.assertNotIn('.GetAttribute(', validator)
        checksum = (TOOLS / 'checksum_validation.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Get-ChecksumEvidenceHash', checksum)
        self.assertIn('Get-ChecksumEvidenceHash', v107)

    def test_cutover_evidence_and_base_options_are_fail_closed(self):
        install = (TOOLS / 'install_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        post_deploy = (TOOLS / 'post_deploy_v10_6_4_verification.ps1').read_text(encoding='utf-8-sig')
        capture = (TOOLS / 'capture_v10_6_4_post_install_reference.ps1').read_text(encoding='utf-8-sig')
        retirement = (TOOLS / 'retire_v10_6_2_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        helpers = (TOOLS / 'reference_collection_helpers.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Enabled:Allow Supplemental Policies', helpers)
        for text in (install, post_deploy, capture, retirement):
            self.assertIn('reference_collection_helpers.ps1', text)
        self.assertIn('AuthoringEvidencePath', install)
        self.assertIn('supplemental_policy_cip_sha256', install)
        self.assertIn('V1062AuthoringEvidencePath', retirement)
        self.assertIn('expectedRetirePolicyId', retirement)
        self.assertIn('capture_mode', capture)
        self.assertIn('base_policy_options', capture)

    def test_audit_mode_rejection_is_implemented_in_all_production_scripts(self):
        helpers = (TOOLS / 'reference_collection_helpers.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Audit Mode', helpers)
        self.assertIn('failing closed', helpers)
        self.assertIn('Test-ClmAuditModeRejection', helpers)
        self.assertIn('Test-ClmBasePolicyInvariant', helpers)
        production_files = [
            'prepare_v10_6_4_bootstrap_on_demo.ps1',
            'install_v10_6_4_bootstrap_on_demo.ps1',
            'post_deploy_v10_6_4_verification.ps1',
            'capture_v10_6_4_post_install_reference.ps1',
            'retire_v10_6_2_bootstrap_on_demo.ps1',
        ]
        for name in production_files:
            text = (TOOLS / name).read_text(encoding='utf-8-sig')
            self.assertIn('reference_collection_helpers.ps1', text, f'{name} must source helpers')
            self.assertTrue(
                'Test-ClmBasePolicyInvariant' in text or 'Test-ClmAuditModeRejection' in text or 'Test-ClmPolicyOptionsValid' in text,
                f'{name} must call at least one policy validation helper'
            )

    def test_retirement_hard_binds_exact_v10_6_2_policy_id(self):
        retire = (TOOLS / 'retire_v10_6_2_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("11b32707-8981-4fe6-a852-3175aa1ac2bb", retire)
        self.assertIn('expectedRetirePolicyId', retire)
        self.assertIn('RetirePolicyId -ine $expectedRetirePolicyId', retire)

    def test_reference_evidence_has_all_required_fields(self):
        capture = (TOOLS / 'capture_v10_6_4_post_install_reference.ps1').read_text(encoding='utf-8-sig')
        for field in ('files', 'unins000', 'processes', 'listeners', 'wininet', 'run_entries', 'code_integrity', 'policies'):
            self.assertIn(field, capture, f'Missing evidence field: {field}')
        self.assertIn('Get-ClmUninstallerEvidence', capture)
        self.assertIn('Get-ClmProcessEvidence', capture)
        self.assertIn('Get-ClmNetstatTcpListeners', capture)
        self.assertIn('Get-ClmOptionalRegistryValue', capture)
        self.assertIn('Get-ClmCodeIntegrityEvidence', capture)
        self.assertIn('Get-ClmPolicyEvidence', capture)

    def test_reference_collection_helpers_provide_pure_functions(self):
        helpers = (TOOLS / 'reference_collection_helpers.ps1').read_text(encoding='utf-8-sig')
        for func in ('Get-ClmRelativePath', 'Test-ClmPolicyOptionsValid', 'Get-ClmOptionalRegistryValue',
                      'Get-ClmNetstatTcpListeners', 'Get-ClmProcessEvidence', 'Get-ClmUninstallerEvidence',
                      'Get-ClmCodeIntegrityEvidence', 'Get-ClmPolicyEvidence', 'Compare-ClmInventory',
                      'Test-ClmAuditModeRejection', 'Test-ClmBasePolicyInvariant', 'Get-ClmLiveInventory',
                      'Resolve-ClmPolicyEvidence', 'Get-ClmBasePolicyEvidence'):
            self.assertIn(f'function {func}', helpers, f'Missing helper function: {func}')

    def test_authoring_evidence_includes_xml_identity(self):
        prepare = (TOOLS / 'prepare_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('supplemental_policy_xml', prepare)
        self.assertIn('supplemental_policy_xml_sha256', prepare)
        self.assertIn('bootstrap-authoring.v3', prepare)

    def test_deploy_verifies_xml_and_cip_authoring_identity(self):
        install = (TOOLS / 'install_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('supplemental_policy_xml', install)
        self.assertIn('supplemental_policy_xml_sha256', install)
        self.assertIn('XML SHA256 does not match authoring evidence', install)
        self.assertIn('authoring.v3', install)

    def test_post_deploy_emits_structured_audit_evidence(self):
        post_deploy = (TOOLS / 'post_deploy_v10_6_4_verification.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('base_policy=[ordered]', post_deploy)
        self.assertIn('supplemental_policy=[ordered]', post_deploy)
        self.assertIn('audit_mode=$false', post_deploy)
        self.assertIn('post-deploy-audit.v2', post_deploy)

    def test_configci_validator_proves_supplemental_structure(self):
        validator = (TOOLS / 'configci_xml_validation.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('PolicyID and BasePolicyID must differ', validator)
        self.assertIn('Settings>', validator)
        self.assertIn('SigningScenario', validator)
        self.assertIn('Value="12"', validator)

    def test_static_clm_contract_covers_real_paths_and_forbidden_methods(self):
        contract = (TOOLS / 'test_clm_contract.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("$_.Name -notlike 'test_*'", contract)
        for forbidden in (r'\.SelectNodes\(', r'\.GetAttribute\(', r'\.Trim\(', r'\.Substring\(', r'\[guid\]', r'\.Split\(', r'SHA256\]::Create', r'ReadAllBytes', r'ComputeHash', r'BitConverter'):
            self.assertIn(forbidden, contract)

    def test_fixture_set_is_complete(self):
        source_fixtures = {path.name for path in (ROOT / 'tools/bootstrap/apl-win-014/v10.6.3/fixtures').iterdir()}
        target_fixtures = {path.name for path in (TOOLS / 'fixtures').iterdir()}
        self.assertTrue(source_fixtures.issubset(target_fixtures))
        self.assertTrue({'sha256sums_reference_capture.txt', 'sha256sums_malformed.txt'}.issubset(target_fixtures))

    def test_v10_7_requires_expanded_capture_evidence(self):
        v107 = (TOOLS / 'prepare_v10_7_final_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('bootstrap_policy_id', v107)
        self.assertIn('base_policy_options', v107)
        self.assertIn('Audit Mode', v107)
        self.assertIn('bootstrap_policy_enforced', v107)
        self.assertIn('bootstrap_policy_authorized', v107)
        for field in ('files', 'unins000', 'processes', 'listeners', 'wininet', 'run_entries', 'code_integrity', 'policies'):
            self.assertIn(field, v107, f'V10.7 must require evidence field: {field}')

    def test_v10_7_revalidates_mandatory_sealed_files(self):
        v107 = (TOOLS / 'prepare_v10_7_final_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Live application hash does not match V10.6.4 seal', v107)
        self.assertIn('Live repair cache hash does not match V10.6.4 seal', v107)
        self.assertIn('Live $($entry.filename) hash does not match V10.6.4 seal', v107)
        self.assertIn('seal.files.application', v107)
        self.assertIn('seal.files.setup', v107)
        self.assertIn('seal.files.upgrade_helper', v107)
        self.assertIn('seal.files.uninstall_helper', v107)
        self.assertIn('seal.files.build_manifest', v107)

    def test_uninstaller_evidence_searches_install_root(self):
        capture = (TOOLS / 'capture_v10_6_4_post_install_reference.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Get-ClmUninstallerEvidence', capture)
        self.assertIn('InstallRoot', capture)
        self.assertIn('unins*.exe', (TOOLS / 'reference_collection_helpers.ps1').read_text(encoding='utf-8-sig'))

    def test_authoring_v3_schema_fields_are_required(self):
        prepare = (TOOLS / 'prepare_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('bootstrap-authoring.v3', prepare)
        self.assertIn('candidate_source_commit', prepare)
        self.assertIn('candidate_artifact_id', prepare)
        self.assertIn('supplemental_policy_xml', prepare)
        self.assertIn('supplemental_policy_xml_sha256', prepare)
        self.assertIn('supplemental_policy_cip', prepare)
        self.assertIn('supplemental_policy_cip_sha256', prepare)
        self.assertIn('supplemental_policy_friendly_name', prepare)
        self.assertIn('supplemental_policy_version', prepare)
        self.assertIn('deployment', prepare)
        self.assertIn('NOT PERFORMED', prepare)

    def test_deploy_validates_candidate_source_commit(self):
        install = (TOOLS / 'install_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('candidate_source_commit', install)
        self.assertIn('seal.candidate_source_commit', install)
        self.assertIn('Authoring candidate_source_commit mismatch', install)

    def test_deploy_validates_candidate_artifact_id(self):
        install = (TOOLS / 'install_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('candidate_artifact_id', install)
        self.assertIn('seal.candidate_artifact_id', install)
        self.assertIn('Authoring candidate_artifact_id mismatch', install)

    def test_deploy_validates_all_authoring_fields_before_mutation(self):
        install = (TOOLS / 'install_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Authoring evidence schema mismatch', install)
        self.assertIn('Authoring base_policy_id mismatch', install)
        self.assertIn('Authoring supplemental_policy_id mismatch', install)
        self.assertIn('Authoring supplemental_policy_friendly_name mismatch', install)
        self.assertIn('Authoring supplemental_policy_version mismatch', install)
        self.assertIn('Authoring evidence deployment state is not NOT PERFORMED', install)
        self.assertIn('Authoring evidence CIP hash does not match', install)
        self.assertIn('XML SHA256 does not match authoring evidence', install)

    def test_prepare_script_uses_base_only_validation(self):
        prepare = (TOOLS / 'prepare_v10_6_4_bootstrap_on_demo.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('Get-ClmBasePolicyEvidence', prepare)
        self.assertIn('Test-ClmBasePolicyInvariant', prepare)
        self.assertNotIn('Get-ClmPolicyEvidence', prepare)

    def test_capture_records_observed_bootstrap_identity(self):
        capture = (TOOLS / 'capture_v10_6_4_post_install_reference.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('bootstrap_policy_id=$bootstrapPolicy.policy_id', capture)
        self.assertIn('bootstrap_policy_base_id=$bootstrapPolicy.base_policy_id', capture)
        self.assertIn('bootstrap_policy_friendly_name=$bootstrapPolicy.friendly_name', capture)
        self.assertIn('bootstrap_policy_version=$bootstrapPolicy.version', capture)
        self.assertIn('bootstrap_policy_options=$bootstrapPolicy.policy_options', capture)

    def test_resolve_clm_policy_evidence_enforces_bootstrap_friendly_name(self):
        helpers = (TOOLS / 'reference_collection_helpers.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('ExpectedBootstrapFriendlyName', helpers)
        self.assertIn('Bootstrap FriendlyName mismatch', helpers)
        self.assertIn('Bootstrap BasePolicyID mismatch', helpers)
        self.assertIn('Bootstrap policy not uniquely present', helpers)

    def test_new_behavioral_tests_exist(self):
        self.assertTrue((TOOLS / 'test_pre_authoring_base_only.ps1').exists())
        self.assertTrue((TOOLS / 'test_bootstrap_policy_identity.ps1').exists())
        self.assertTrue((TOOLS / 'test_deploy_authoring_provenance.ps1').exists())


if __name__ == '__main__':
    unittest.main()
