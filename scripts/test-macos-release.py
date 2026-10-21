import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release-macos.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseTests(unittest.TestCase):
    def test_unsigned_release_refused_before_any_command(self):
        with patch.object(release, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Developer ID Application'):
                release.preflight({'CLEARMIC_SIGN_IDENTITY': '-'})
            run.assert_not_called()

    def test_missing_installer_identity_refused_before_any_command(self):
        with patch.object(release, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Developer ID Installer'):
                release.preflight({'CLEARMIC_SIGN_IDENTITY': 'Developer ID Application: Test'})
            run.assert_not_called()

    def test_dirty_checkout_cannot_be_submitted(self):
        with tempfile.NamedTemporaryFile() as key, patch.object(release, 'run', return_value=' M README.md') as run:
            env = {'CLEARMIC_SIGN_IDENTITY': 'Developer ID Application: Test',
                   'CLEARMIC_INSTALLER_IDENTITY': 'Developer ID Installer: Test',
                   'CLEARMIC_NOTARY_PROFILE': 'test', 'CLEARMIC_UPDATE_KEY': key.name}
            with self.assertRaisesRegex(RuntimeError, 'Commit source'):
                release.preflight(env)
            run.assert_called_once_with('git', 'status', '--porcelain', '--untracked-files=normal')

    def test_notarization_rejection_stops_pipeline(self):
        with patch.object(release, 'run', return_value='{"status":"Invalid","id":"rejected-id"}') as run:
            with self.assertRaisesRegex(RuntimeError, 'rejected-id'):
                release.notarize(Path('test.pkg'), 'test-profile')
            self.assertEqual(run.call_count, 1)

if __name__ == '__main__':
    unittest.main()
