import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')


class WindowsV1064WorkflowContractTests(unittest.TestCase):
    def test_candidate_workflow_is_manual_and_run_bound(self):
        workflow = read('.github/workflows/apl-win-014-v10-6-4-candidate.yml')
        self.assertIn('workflow_dispatch:', workflow)
        self.assertIn('source_commit:', workflow)
        self.assertIn('ref: ${{ inputs.source_commit }}', workflow)
        self.assertIn('apl-win-014-v10.6.4-candidate-${{ github.run_id }}-${{ github.run_attempt }}', workflow)
        self.assertNotIn('pull_request:', workflow)

    def test_candidate_path_has_one_application_build_authority(self):
        workflow = read('.github/workflows/apl-win-014-v10-6-4-candidate.yml')
        script = read('tools/build_apl_win_014_v10_6_4_candidate.ps1')
        self.assertEqual(script.count('tools\\clean_build_windows.ps1'), 1)
        self.assertNotIn('PyInstaller', workflow)
        self.assertIn('-UseExistingPayload', script)
        self.assertIn('-ApplicationExe', script)
        self.assertIn('-PortableZip', script)
        self.assertIn('-BuildResultPath', script)

    def test_existing_payload_mode_rejects_mixed_or_stale_bytes(self):
        builder = read('tools/build_windows_installer.ps1')
        for token in (
            'UseExistingPayload requires -ApplicationExe, -PortableZip, and -BuildResultPath.',
            'build-result source_commit does not match HEAD',
            'portable ZIP hash does not match build-result.json',
            'application hash does not match build-result.json',
            'Portable ZIP application bytes do not match the installer payload application.',
            'portable ZIP checksum does not match the installer payload application.',
        ):
            self.assertIn(token, builder)

    def test_candidate_evidence_requires_byte_identity(self):
        script = read('tools/build_apl_win_014_v10_6_4_candidate.ps1')
        for token in (
            'Installed application hash does not equal the frozen candidate application hash.',
            'Installer build manifest application hash does not equal frozen candidate application hash.',
            'Installer E2E did not use the sealed setup.',
            'application_equals_installed_application = $true',
            'manifest_application_equals_application = $true',
            'github_run_id = $runId',
            'github_run_attempt = $attempt',
            'WaitForExit(30000)',
            'Setup /HELP exceeded the 30-second non-interactive timeout.',
        ):
            self.assertIn(token, script)


if __name__ == '__main__':
    unittest.main()
