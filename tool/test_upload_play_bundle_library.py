import hashlib
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / '.github' / 'scripts'))
import upload_play_bundle_library as uploader
from publish_play import BASE, UPLOAD


class BundleLibraryUploadTests(unittest.TestCase):
    def test_uploads_verified_bundle_without_changing_tracks(self):
        with tempfile.NamedTemporaryFile() as bundle:
            bundle.write(b'test-app-bundle')
            bundle.flush()
            digest = hashlib.sha256(b'test-app-bundle').hexdigest()
            tracks = [{'track': 'wear:beta'}, {'track': 'production'}]
            responses = [
                {'id': 'upload-edit'},
                {'tracks': tracks},
                {'versionCode': 213723113, 'sha256': digest},
                {},
                {'id': 'verify-edit'},
                {'bundles': [{'versionCode': 213723113, 'sha256': digest}]},
                {'tracks': tracks},
            ]
            request = Mock(side_effect=responses)
            response_context = Mock()
            response_context.__enter__ = Mock(return_value=None)
            response_context.__exit__ = Mock(return_value=False)
            urlopen = Mock(return_value=response_context)
            with patch.object(uploader, 'request', request), patch.object(
                uploader.urllib.request, 'urlopen', urlopen
            ):
                uploader.upload_bundle('token', bundle.name, 213723113)

        self.assertEqual(request.call_args_list[2].args[:3], (
            'token', 'POST',
            f'{UPLOAD}/edits/upload-edit/bundles?uploadType=media',
        ))
        self.assertEqual(request.call_args_list[2].args[4], 'application/octet-stream')
        self.assertEqual(request.call_args_list[3].args[2], f'{BASE}/edits/upload-edit:commit')
        self.assertEqual(request.call_args_list[6].args[2], f'{BASE}/edits/verify-edit/tracks')
        self.assertEqual(urlopen.call_args.args[0].full_url,
                         f'{BASE}/edits/verify-edit')

    def test_rejects_play_checksum_mismatch_before_commit(self):
        with tempfile.NamedTemporaryFile() as bundle:
            bundle.write(b'test-app-bundle')
            bundle.flush()
            request = Mock(side_effect=[
                {'id': 'upload-edit'},
                {'tracks': []},
                {'versionCode': 213723113, 'sha256': 'wrong'},
            ])
            with patch.object(uploader, 'request', request), self.assertRaisesRegex(
                RuntimeError, 'different SHA-256'
            ):
                uploader.upload_bundle('token', bundle.name, 213723113)
            self.assertFalse(any(':commit' in call.args[2] for call in request.call_args_list))


if __name__ == '__main__':
    unittest.main()
