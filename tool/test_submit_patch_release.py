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

    def test_refuses_to_cancel_review_with_other_items(self):
        old = {'id': 'old'}
        replies = [
            {'data': [{'id': 'review', 'attributes': {'state': 'WAITING_FOR_REVIEW'}}]},
            {'data': [{'id': 'item1'}, {'id': 'item2'}], 'included': [
                {'type': 'appStoreVersions', 'id': 'old'},
            ]},
        ]
        with patch.object(module.asc, 'request', side_effect=replies), patch.object(module, 'send') as send:
            with self.assertRaisesRegex(RuntimeError, 'only iOS 1.3.1'):
                module.replace_waiting_version('token', old)
            send.assert_not_called()

    def test_resubmits_only_rejected_version_with_valid_replacement(self):
        version_id = 'version'
        calls = []

        def request(_token, method, url, data=None):
            calls.append((method, url))
            if '/builds/build?include=' in url:
                return {'included': [{'type': 'preReleaseVersions', 'attributes': {'version': '1.3.2'}}]}
            if '/apps/6811779595/appStoreVersions?' in url:
                return {'data': [{'id': version_id, 'attributes': {'versionString': '1.3.2', 'appStoreState': 'REJECTED'}}]}
            if '/appStoreVersionLocalizations?' in url:
                return {'data': [{'id': 'locale', 'attributes': {'locale': 'de-DE'}}]}
            if '/appScreenshotSets?' in url:
                return {'included': [{'type': 'appScreenshots', 'id': 'image'}]}
            if url.endswith('/relationships/build'):
                return {}
            if url.endswith('/build'):
                return {'data': {'id': 'build', 'attributes': {'processingState': 'VALID'}}}
            if url.endswith('/appStoreReviewDetail'):
                return {'data': {'id': 'contact'}}
            if '/reviewSubmissions?' in url:
                return {'data': [{'id': 'review', 'attributes': {'state': 'UNRESOLVED_ISSUES'}}]}
            if '/reviewSubmissions/review/items?' in url:
                return {'data': [{'id': 'item', 'attributes': {'state': 'REJECTED'}}],
                        'included': [{'type': 'appStoreVersions', 'id': version_id}]}
            if url.endswith('/appStoreVersions/version'):
                return {'data': {'attributes': {'appStoreState': 'WAITING_FOR_REVIEW'}}}
            raise AssertionError((method, url))

        def send(_token, method, path, data):
            calls.append((method, path))
            if path == 'reviewSubmissionItems/item':
                self.assertEqual(data['attributes'], {'resolved': True})
                return {'id': 'item'}
            if path == 'reviewSubmissions/review':
                self.assertEqual(data['attributes'], {'submitted': True})
                return {'attributes': {'state': 'WAITING_FOR_REVIEW'}}
            raise AssertionError(path)

        with patch.object(module.asc, 'resolve_app', return_value=module.APP), \
             patch.object(module.asc, 'await_build', return_value='build'), \
             patch.object(module.asc, 'request', side_effect=request), \
             patch.object(module, 'send', side_effect=send):
            module.submit('token', '216303109')
        self.assertIn(('PATCH', 'reviewSubmissionItems/item'), calls)
        self.assertIn(('PATCH', 'reviewSubmissions/review'), calls)
        self.assertFalse(any(method == 'DELETE' for method, _ in calls))

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
