import hashlib
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / '.github' / 'scripts'))
import publish_play as publishing
import promote_play_testing as promotion


class WearPublicationTests(unittest.TestCase):
    def run_publication(self, *, has_wear=True, change_phone=False):
        phone = {'track': 'alpha', 'releases': [{'versionCodes': ['42']}]}
        production = {'track': 'production'}
        wear = {'track': 'wear:alpha'}
        state = {'committed': False, 'release': None}
        digest = hashlib.sha256(b'watch bundle').hexdigest()
        def api(token, method, url, body=None, content_type='application/json'):
            if method == 'POST' and url.endswith('/edits'):
                return {'id': 'verify' if state['committed'] else 'upload'}
            if method == 'GET' and url.endswith('/tracks/production'):
                return production
            if method == 'GET' and url.endswith('/tracks'):
                current_phone = {'track': 'alpha', 'releases': [{'versionCodes': ['43']}]} if change_phone and state['committed'] else phone
                return {'tracks': [production, current_phone] + ([wear] if has_wear else [])}
            if method == 'POST' and 'bundles?uploadType=media' in url:
                return {'versionCode': 99, 'sha256': digest}
            if method == 'PUT':
                self.assertTrue(url.endswith('/tracks/wear:alpha'))
                state['release'] = json.loads(body)
                return state['release']
            if url.endswith(':commit'):
                state['committed'] = True
                return {}
            if url.endswith('/tracks/wear:alpha'):
                return state['release']
            if url.endswith('/bundles'):
                return {'bundles': [{'versionCode': 99, 'sha256': digest}]}
            raise AssertionError((method, url))
        request = Mock(side_effect=api)
        with tempfile.TemporaryDirectory() as temp:
            bundle = pathlib.Path(temp) / 'watch.aab'
            bundle.write_bytes(b'watch bundle')
            notes = pathlib.Path(temp) / 'notes.txt'
            notes.write_text('Experimental watch testing')
            argv = ['publish_play.py', '--aab', str(bundle), '--track', 'wear:alpha', '--name', 'Watch', '--version-code', '99', '--notes-file', str(notes)]
            with patch.object(publishing, 'request', request), patch.dict(publishing.os.environ, {'GOOGLE_OAUTH_ACCESS_TOKEN': 'test'}), patch.object(sys, 'argv', argv):
                publishing.main()
        return request

    def test_wear_upload_targets_only_wear_track(self):
        calls = self.run_publication().call_args_list
        writes = [call.args for call in calls if call.args[1] == 'PUT']
        self.assertEqual(len(writes), 1)
        self.assertTrue(writes[0][2].endswith('/tracks/wear:alpha'))

    def test_missing_wear_track_blocks_publication(self):
        with self.assertRaisesRegex(RuntimeError, 'configure Wear OS closed track'):
            self.run_publication(has_wear=False)

    def test_phone_tracks_must_remain_unchanged(self):
        with self.assertRaisesRegex(RuntimeError, 'phone tracks changed'):
            self.run_publication(change_phone=True)


class PhonePromotionTests(unittest.TestCase):
    def api(self, codes=None):
        source = {'track': 'internal', 'releases': [{'name': 'Nightly', 'status': 'completed', 'versionCodes': codes or ['42']}]}
        state = {}
        def request(token, method, url, body=None):
            if method == 'PUT':
                self.assertTrue(url.endswith('/tracks/alpha'))
                state['alpha'] = json.loads(body)
                return state['alpha']
            return {'id': 'edit'}
        def track(token, edit, name):
            if name == 'internal':
                return source
            return state.get(name, {'track': name})
        return Mock(side_effect=request), Mock(side_effect=track)

    def test_promotes_only_the_exact_internal_phone_build(self):
        request, track = self.api()
        with patch.object(promotion, 'request', request), patch.object(promotion, 'track_state', track):
            promotion.promote('test', 42)
        writes = [call for call in request.call_args_list if call.args[1] == 'PUT']
        self.assertEqual(len(writes), 1)
        self.assertEqual(json.loads(writes[0].args[3])['releases'][0]['versionCodes'], ['42'])

    def test_rejects_a_different_or_multi_version_release(self):
        for codes in (['43'], ['42', '43']):
            request, track = self.api(codes)
            with patch.object(promotion, 'request', request), patch.object(promotion, 'track_state', track):
                with self.assertRaisesRegex(RuntimeError, 'sole version'):
                    promotion.promote('test', 42)
            self.assertFalse(any(call.args[1] == 'PUT' for call in request.call_args_list))


if __name__ == '__main__':
    unittest.main()
