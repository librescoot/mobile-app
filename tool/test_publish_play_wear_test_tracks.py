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
    def test_creates_closed_track_separately_and_publishes_missing_channel(self):
        content = b'existing-wear-aab'
        digest = hashlib.sha256(content).hexdigest()
        code = 213723113
        other_tracks = [
            {'track': 'production', 'releases': [{'versionCodes': ['213000000']}]},
            {'track': 'wear:internal', 'releases': [{'versionCodes': [str(code)]}]},
        ]
        before_create = other_tracks + [{'track': 'wear:beta'}]
        after_create = before_create + [{'track': 'wear:alpha'}]
        with tempfile.NamedTemporaryFile() as bundle, tempfile.NamedTemporaryFile(mode='w+') as notes:
            bundle.write(content)
            bundle.flush()
            notes.write('Test the Wear app.')
            notes.flush()
            request = Mock(side_effect=[
                {'id': 'create-edit'},
                {'tracks': before_create},
                {'track': 'wear:alpha'},
                {},
                {'id': 'verify-create'},
                {'tracks': after_create},
                {'id': 'publish-edit'},
                {'bundles': [{'versionCode': code, 'sha256': digest}]},
                {'tracks': after_create},
                {'releases': [{'versionCodes': [str(code)]}]},
                {},
                {'id': 'verify-publish'},
                {'bundles': [{'versionCode': code, 'sha256': digest}]},
                {'tracks': other_tracks + [
                    {'track': 'wear:alpha', 'releases': [{'versionCodes': [str(code)]}]},
                    {'track': 'wear:beta', 'releases': [{'versionCodes': [str(code)]}]},
                ]},
            ])
            alpha_state = {'track': 'wear:alpha', 'releases': [{'versionCodes': [str(code)], 'status': 'completed'}]}
            beta_state = {'track': 'wear:beta', 'releases': [{'versionCodes': [str(code)], 'status': 'completed'}]}
            track_state = Mock(side_effect=[{'track': 'wear:alpha', 'releases': []}, beta_state, alpha_state, beta_state])
            response_context = Mock()
            response_context.__enter__ = Mock(return_value=None)
            response_context.__exit__ = Mock(return_value=False)
            urlopen = Mock(return_value=response_context)
            with patch.object(publisher, 'request', request), patch.object(
                publisher, 'track_state', track_state
            ), patch.object(publisher.urllib.request, 'urlopen', urlopen):
                publisher.publish('token', bundle.name, code, notes.name)

        self.assertEqual(request.call_args_list[2].args[1], 'POST')
        self.assertEqual(request.call_args_list[2].args[2], f'{BASE}/edits/create-edit/tracks')
        self.assertEqual(request.call_args_list[2].args[3],
                         b'{"track": "wear:alpha", "type": "CLOSED_TESTING", "formFactor": "WEAR"}')
        self.assertEqual(request.call_args_list[3].args[2], f'{BASE}/edits/create-edit:commit')
        self.assertEqual(request.call_args_list[9].args[2], f'{BASE}/edits/publish-edit/tracks/wear:alpha')
        self.assertFalse(any('/tracks/wear:beta' in call.args[2] and call.args[1] == 'PUT'
                             for call in request.call_args_list))
        self.assertEqual(urlopen.call_count, 2)

    def test_refuses_if_open_track_is_missing(self):
        with tempfile.NamedTemporaryFile() as bundle, tempfile.NamedTemporaryFile(mode='w+') as notes:
            bundle.write(b'existing')
            bundle.flush()
            notes.write('Test.')
            notes.flush()
            digest = hashlib.sha256(b'existing').hexdigest()
            request = Mock(side_effect=[
                {'id': 'edit'},
                {'tracks': [{'track': 'wear:alpha'}]},
                {'id': 'publish-edit'},
                {'bundles': [{'versionCode': 213723113, 'sha256': digest}]},
                {'tracks': [{'track': 'wear:alpha'}]},
            ])
            context = Mock()
            context.__enter__ = Mock(return_value=None)
            context.__exit__ = Mock(return_value=False)
            with patch.object(publisher, 'request', request), patch.object(
                publisher.urllib.request, 'urlopen', return_value=context
            ), self.assertRaisesRegex(RuntimeError, 'missing: wear:beta'):
                publisher.publish('token', bundle.name, 213723113, notes.name)
            self.assertFalse(any(':commit' in str(call) for call in request.call_args_list))


if __name__ == '__main__':
    unittest.main()
