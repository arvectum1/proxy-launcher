from pathlib import Path
import re
import unittest

TEXT = Path("tools/windows_app_control_candidate_stand.ps1").read_text(encoding="utf-8-sig")

class RecoveredPortableCurrentStateContract(unittest.TestCase):
    def test_preflight_resolves_active_exact_current_runtime(self):
        self.assertIn("function Resolve-Current023Healthy", TEXT)
        self.assertIn("PORTABLE_RECOVERY", TEXT)
        self.assertIn("$current = Resolve-Current023Healthy", TEXT)
        self.assertIn("current_runtime_mode=[string]$current.mode", TEXT)
        self.assertIn("current_runtime_path=[string]$current.exe", TEXT)

    def test_execute_cleans_installed_or_portable_current_state(self):
        self.assertIn("function Remove-Current023AfterRollback", TEXT)
        self.assertIn("Remove-Current023AfterRollback $context.current", TEXT)
        self.assertIn("[string]$Current.mode -eq 'INSTALLED'", TEXT)
        self.assertIn("PORTABLE_RECOVERY", TEXT)

    def test_portable_state_does_not_require_installed_uninstaller(self):
        block = re.search(r"function Resolve-Current023Healthy \{(?P<body>.*?)\n\}\n\nfunction Assert-CandidateInstalled", TEXT, re.S)
        self.assertIsNotNone(block)
        body = block.group("body")
        self.assertIn("Get-NetTCPConnection -LocalPort 8082", body)
        self.assertIn("Hash $exe", body)
        self.assertIn("$mode = 'PORTABLE_RECOVERY'", body)
        self.assertIn("if ([IO.Path]::GetFullPath", body)

if __name__ == "__main__":
    unittest.main()
