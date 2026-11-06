import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / '.github' / 'scripts'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('submit_patch_release', SCRIPTS / 'submit_patch_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SubmitPatchReleaseTest(unittest.TestCase):
    def test_rejects_wrong_app_before_mutation(self):
        with patch.object(module.asc, 'resolve_app', return_value='wrong'), patch.object(module.asc, 'request') as request:
            with self.assertRaisesRegex(RuntimeError, 'Unexpected App Store app'):
                module.submit('token', '123')
            request.assert_not_called()

    def test_rejects_wrong_marketing_version_before_mutation(self):
        with patch.object(module.asc, 'resolve_app', return_value=module.APP), \
             patch.object(module.asc, 'await_build', return_value='build'), \
             patch.object(module.asc, 'request', return_value={'included': [
                 {'type': 'preReleaseVersions', 'attributes': {'version': '1.3.0'}},
             ]}) as request:
            with self.assertRaisesRegex(RuntimeError, 'marketing version'):
                module.submit('token', '123')
            self.assertEqual(request.call_count, 1)
            self.assertEqual(request.call_args.args[1], 'GET')


if __name__ == '__main__':
    unittest.main()
