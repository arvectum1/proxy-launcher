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
            'test_citool_schema.ps1',
            'test_configci_xml_structure.ps1',
            'test_clm_contract.ps1',
            'test_clm_runspace.ps1',
            'expected_hashes.json',
            'SEALING_ONLY_CLASSIFICATION.md',
        }
        self.assertTrue(expected.issubset({path.name for path in TOOLS.iterdir()}))

    def test_production_scripts_are_noninteractive_and_do_not_invoke_ui_help(self):
        production = [path for path in TOOLS.glob('*.ps1') if not path.name.startswith('test_')]
        self.assertGreaterEqual(len(production), 7)
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
        self.assertIn('IsEnforced -eq $true', retirement)

    def test_fixture_set_is_complete(self):
        source_fixtures = {path.name for path in (ROOT / 'tools/bootstrap/apl-win-014/v10.6.3/fixtures').iterdir()}
        target_fixtures = {path.name for path in (TOOLS / 'fixtures').iterdir()}
        self.assertEqual(target_fixtures, source_fixtures)


if __name__ == '__main__':
    unittest.main()
