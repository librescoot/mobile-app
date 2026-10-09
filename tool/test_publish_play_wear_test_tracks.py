import hashlib
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / '.github' / 'scripts'))
import publish_play_wear_test_tracks as publisher
from publish_play import BASE


class PublishWearTestTracksTests(unittest.TestCase):
    def test_creates_closed_track_and_publishes_to_closed_and_open(self):
        content = b'existing-wear-aab'
        digest = hashlib.sha256(content).hexdigest()
        code = 213723113
        before = [
            {'track': 'production', 'releases': [{'versionCodes': ['213000000']}]},
            {'track': 'wear:internal', 'releases': [{'versionCodes': [str(code)]}]},
            {'track': 'wear:beta'},
        ]
        after = before + [{'track': 'wear:alpha', 'releases': []}]
        with tempfile.NamedTemporaryFile() as bundle, tempfile.NamedTemporaryFile(mode='w+') as notes:
            bundle.write(content)
            bundle.flush()
            notes.write('Test the Wear app.')
            notes.flush()
            request = Mock(side_effect=[
                {'id': 'edit'},
                {'bundles': [{'versionCode': code, 'sha256': digest}]},
                {'tracks': before},
                {'track': 'wear:alpha'},
                {'releases': [{'versionCodes': [str(code)]}]},
                {'releases': [{'versionCodes': [str(code)]}]},
                {},
                {'id': 'verify'},
                {'bundles': [{'versionCode': code, 'sha256': digest}]},
                {'tracks': after},
            ])
            response_context = Mock()
            response_context.__enter__ = Mock(return_value=None)
            response_context.__exit__ = Mock(return_value=False)
            urlopen = Mock(return_value=response_context)
            with patch.object(publisher, 'request', request), patch.object(
                publisher, 'track_state', side_effect=[
                    {'track': 'wear:alpha', 'releases': [{'versionCodes': [str(code)], 'status': 'completed'}]},
                    {'track': 'wear:beta', 'releases': [{'versionCodes': [str(code)], 'status': 'completed'}]},
                ]
            ), patch.object(publisher.urllib.request, 'urlopen', urlopen):
                publisher.publish('token', bundle.name, code, notes.name)

        self.assertEqual(request.call_args_list[3].args[1], 'POST')
        self.assertEqual(request.call_args_list[3].args[2], f'{BASE}/edits/edit/tracks')
        self.assertEqual(request.call_args_list[3].args[3],
                         b'{"track": "wear:alpha", "type": "CLOSED_TESTING", "formFactor": "WEAR"}')
        self.assertEqual(request.call_args_list[4].args[2], f'{BASE}/edits/edit/tracks/wear:alpha')
        self.assertEqual(request.call_args_list[5].args[2], f'{BASE}/edits/edit/tracks/wear:beta')
        self.assertEqual(urlopen.call_args.args[0].full_url, f'{BASE}/edits/verify')

    def test_refuses_to_continue_if_open_track_is_not_configured(self):
        with tempfile.NamedTemporaryFile() as bundle, tempfile.NamedTemporaryFile(mode='w+') as notes:
            bundle.write(b'existing')
            bundle.flush()
            notes.write('Test.')
            notes.flush()
            digest = hashlib.sha256(b'existing').hexdigest()
            request = Mock(side_effect=[
                {'id': 'edit'},
                {'bundles': [{'versionCode': 213723113, 'sha256': digest}]},
                {'tracks': [{'track': 'wear:internal'}]},
                {'track': 'wear:alpha'},
            ])
            with patch.object(publisher, 'request', request), self.assertRaisesRegex(
                RuntimeError, 'wear:beta is not configured'
            ):
                publisher.publish('token', bundle.name, 213723113, notes.name)
            self.assertFalse(any(':commit' in str(call) for call in request.call_args_list))


if __name__ == '__main__':
    unittest.main()
