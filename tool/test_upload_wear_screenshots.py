import base64
import hashlib
import pathlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / '.github' / 'scripts'))
import upload_wear_screenshots as uploader


def png(width=454, height=454, color_type=2):
    return b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>IIBBBBB', width, height, 8, color_type, 0, 0, 0)


class WearScreenshotUploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = pathlib.Path(self.temp.name)
        for name, data in [('01.png', png()), ('02.png', png(455, 455))]:
            (self.directory / name).write_bytes(data)

    def tearDown(self):
        self.temp.cleanup()

    def fake_request(self, *, existing=None, limit=None):
        state = {'committed': False, 'uploaded': [], 'images': existing or {}}
        locales = ['en-US', 'de-DE']
        def request(token, method, url, body=None, content_type='application/json'):
            if method == 'POST' and url.endswith('/edits'):
                return {'id': 'verify' if state['committed'] else 'edit'}
            if url.endswith('/listings') and method == 'GET':
                return {'listings': [{'language': locale} for locale in locales]}
            if '/wearScreenshots' in url and method == 'GET':
                language = url.split('/listings/')[1].split('/')[0]
                return {'images': state['images'].get(language, [])}
            if '/wearScreenshots?uploadType=media' in url and method == 'POST':
                self.assertEqual(content_type, 'image/png')
                language = url.split('/listings/')[1].split('/')[0]
                state['uploaded'].append((url, body, content_type))
                state['images'].setdefault(language, []).append({
                    'sha1': base64.b64encode(hashlib.sha1(body).digest()).decode(),
                    'sha256': hashlib.sha256(body).hexdigest(),
                })
                return {'url': f'https://example/image-{len(state["uploaded"])}'}
            if url.endswith(':commit'):
                state['committed'] = True
                return {}
            raise AssertionError((method, url))
        return Mock(side_effect=request), state

    def test_checked_in_store_screenshots_meet_play_limits(self):
        screenshots = sorted(uploader.SCREENSHOTS.glob('*.png'))
        self.assertEqual(len(screenshots), 3)
        for screenshot in screenshots:
            data = screenshot.read_bytes()
            self.assertLessEqual(len(data), 8 * 1024 * 1024)
            width, height, bit_depth, color_type, _, _, _ = struct.unpack('>IIBBBBB', data[16:29])
            self.assertEqual((width, height), (454, 454))
            self.assertEqual(color_type, 2)
            self.assertEqual(bit_depth, 8)

    def test_uploads_to_each_locale_and_commits_once(self):
        request, state = self.fake_request()
        with patch.object(uploader, 'request', request):
            uploader.publish('token', self.directory)
        uploads = [call for call in request.call_args_list if '/wearScreenshots?uploadType=media' in call.args[2]]
        self.assertEqual(len(uploads), 4)
        self.assertEqual(sum(call.args[2].endswith(':commit') for call in request.call_args_list), 1)

    def test_upload_is_idempotent_for_existing_identical_screenshots(self):
        data = (self.directory / '01.png').read_bytes()
        sha = base64.b64encode(hashlib.sha1(data).digest()).decode()
        existing = {'en-US': [{'sha1': sha}], 'de-DE': []}
        request, state = self.fake_request(existing=existing)
        with patch.object(uploader, 'request', request):
            uploader.publish('token', self.directory)
        uploads = [call for call in request.call_args_list if '/wearScreenshots?uploadType=media' in call.args[2]]
        self.assertEqual(len(uploads), 3)

    def test_does_not_remove_existing_images_when_limit_would_be_exceeded(self):
        existing = {'en-US': [{'sha1': str(i)} for i in range(7)], 'de-DE': []}
        request, state = self.fake_request(existing=existing)
        with patch.object(uploader, 'request', request):
            with self.assertRaisesRegex(RuntimeError, 'exceed Play'):
                uploader.publish('token', self.directory)
        self.assertFalse(any('/wearScreenshots?uploadType=media' in call.args[2] for call in request.call_args_list))
        self.assertFalse(any(call.args[2].endswith(':commit') for call in request.call_args_list))

    def test_rejects_transparency_and_invalid_aspect_or_size(self):
        (self.directory / '02.png').write_bytes(png(color_type=6))
        with self.assertRaisesRegex(RuntimeError, 'without transparency'):
            uploader.publish('token', self.directory)
        (self.directory / '02.png').write_bytes(png(width=383))
        with self.assertRaisesRegex(RuntimeError, 'square'):
            uploader.publish('token', self.directory)


if __name__ == '__main__':
    unittest.main()
