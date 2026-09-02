import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class WindowsV1064SealingContractTests(unittest.TestCase):
    def test_expected_hashes_pin_the_accepted_candidate(self):
        path = ROOT / 'tools/bootstrap/apl-win-014/v10.6.4/expected_hashes.json'
        data = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(data['candidate_source_commit'], '445d3e6a731c4406b8ecf6c12674b1fa074bd1e7')
        self.assertEqual(data['candidate_run_id'], '33559232176')
        self.assertEqual(data['candidate_run_attempt'], '1')
        self.assertEqual(data['candidate_artifact_id'], '9820644184')
        self.assertEqual(data['candidate_artifact_digest'], 'sha256:bbbe0da6fff3417c8000236036a052ed55f8a4ff5d589d8bd2f15187dd0281c9')
        self.assertEqual(data['files']['application']['sha256'], '559ae4d4a174ba03c0d649d04d6f494e89bade7f16acbeead8e3e7bec73fc932')
        self.assertEqual(data['files']['setup']['sha256'], '7e7640fe434067415840a154cfbeba0df443caf155fed38cff7ede1bc7d7d600')

    def test_validator_requires_all_identity_representations(self):
        script = (ROOT / 'tools/bootstrap/apl-win-014/v10.6.4/validate_v10_6_4_candidate.ps1').read_text(encoding='utf-8-sig')
        for token in ('SHA256SUMS.txt', 'candidate evidence run ID', 'candidate evidence source commit', "'application_sha256'", 'real-stand help probe', 'Candidate installed application identity is not true.'):
            self.assertIn(token, script)
        self.assertNotIn('clean_build_windows.ps1', script)
        self.assertNotIn('build_windows_installer.ps1', script)


if __name__ == '__main__':
    unittest.main()
