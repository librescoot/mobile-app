import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '.github/scripts'))
import publish_play as play


class PublicationTests(unittest.TestCase):
    def run_publish(self, requested='completed', staged=None, committed=None):
        bundle = b'test bundle'
        digest = hashlib.sha256(bundle).hexdigest()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'app.aab').write_bytes(bundle)
            (root / 'notes.txt').write_text('Release notes')
            argv = ['publish_play', '--aab', str(root / 'app.aab'), '--track', 'production',
                    '--name', '1.3.0', '--version-code', '123', '--status', requested,
                    '--notes-file', str(root / 'notes.txt')]
            edits = 0

            def request(token, method, url, body=None, content_type=None):
                nonlocal edits
                if method == 'POST' and url.endswith('/edits'):
                    edits += 1
                    return {'id': f'edit-{edits}'}
                if '/bundles?uploadType=' in url:
                    return {'versionCode': 123, 'sha256': digest}
                if url.endswith('/bundles'):
                    return {'bundles': [{'versionCode': 123, 'sha256': digest}]}
                if url.endswith(':commit'):
                    return {}
                if method == 'PUT':
                    data = json.loads(body)
                    self.assertEqual(data['releases'][0]['status'], requested)
                    data['releases'][0]['status'] = staged or requested
                    return data
                status = (committed or requested) if edits > 1 else 'draft'
                return {'releases': [{'versionCodes': ['123'], 'status': status}]}

            with patch.object(sys, 'argv', argv), patch.dict(os.environ, GOOGLE_OAUTH_ACCESS_TOKEN='test-token'), \
                    patch.object(play, 'request', side_effect=request):
                play.main()

    def test_public_rollout_verified(self):
        self.run_publish()

    def test_draft_verified(self):
        self.run_publish(requested='draft')

    def test_staged_status_mismatch_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'staged release status'):
            self.run_publish(staged='draft')

    def test_committed_status_mismatch_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'committed release status'):
            self.run_publish(committed='draft')


if __name__ == '__main__':
    unittest.main()
