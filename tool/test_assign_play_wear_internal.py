import hashlib
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / '.github' / 'scripts'))
import assign_play_wear_internal as assignment
from publish_play import BASE


class AssignWearInternalTests(unittest.TestCase):
    def test_assigns_existing_aab_only_to_wear_internal(self):
        content = b'existing-wear-aab'
        digest = hashlib.sha256(content).hexdigest()
        code = 213723113
        other_tracks = [{'track': 'production'}, {'track': 'internal'}]
        full_before = other_tracks + [{'track': 'wear:internal'}]
        with tempfile.NamedTemporaryFile() as bundle, tempfile.NamedTemporaryFile(mode='w+') as notes:
            bundle.write(content)
            bundle.flush()
            notes.write('Test Wear OS controls and status.')
            notes.flush()
            request = Mock(side_effect=[
                {'id': 'edit'},
                {'bundles': [{'versionCode': code, 'sha256': digest}]},
                {'tracks': full_before},
                {'releases': [{'versionCodes': [str(code)]}]},
                {},
                {'id': 'verify'},
                {'bundles': [{'versionCode': code, 'sha256': digest}]},
                {'tracks': other_tracks + [{'track': 'wear:internal', 'releases': []}]},
            ])
            published_track = {
                'track': 'wear:internal',
                'releases': [{'versionCodes': [str(code)], 'status': 'completed'}],
            }
            with patch.object(assignment, 'request', request), patch.object(
                assignment, 'track_state', return_value=published_track
            ), patch.object(assignment.urllib.request, 'urlopen'):
                assignment.assign('token', bundle.name, code, notes.name)

        self.assertEqual(request.call_args_list[3].args[1:3], (
            'PUT', f'{BASE}/edits/edit/tracks/wear:internal'
        ))
        self.assertEqual(request.call_args_list[3].args[3].decode().find('wear:internal') >= 0, True)
        self.assertFalse(any('/tracks/production' in str(call) for call in request.call_args_list))

    def test_refuses_a_bundle_not_already_in_the_play_library(self):
        with tempfile.NamedTemporaryFile() as bundle, tempfile.NamedTemporaryFile(mode='w+') as notes:
            bundle.write(b'not-uploaded')
            bundle.flush()
            notes.write('Internal testing.')
            notes.flush()
            request = Mock(side_effect=[{'id': 'edit'}, {'bundles': []}])
            with patch.object(assignment, 'request', request), self.assertRaisesRegex(
                RuntimeError, 'not present in Play'
            ):
                assignment.assign('token', bundle.name, 213723113, notes.name)
            self.assertFalse(any('/tracks/wear:internal' in str(call) for call in request.call_args_list))


if __name__ == '__main__':
    unittest.main()
