import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

scripts = Path(__file__).resolve().parents[1] / '.github/scripts'
sys.path.insert(0, str(scripts))
spec = importlib.util.spec_from_file_location('prepare_app_store', scripts / 'prepare_app_store.py')
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class FreePriceTests(unittest.TestCase):
    def test_create_free_schedule_with_only_free_price(self):
        calls = []
        def request(token, method, url, body=None):
            calls.append((method, url, json.loads(body) if body else None))
            if url.endswith('/appPriceSchedule'):
                return {'data': {'id': 'schedule'} if len(calls) > 1 else None}
            if '/appPricePoints?' in url:
                return {'data': [{'id': 'free', 'attributes': {'customerPrice': '0.00'}},
                                 {'id': 'paid', 'attributes': {'customerPrice': '0.99'}}]}
            if url.endswith('/appPriceSchedules'):
                return {'data': {'id': 'schedule'}}
            raise AssertionError(url)
        with patch.object(subject.asc, 'request', side_effect=request):
            subject.configure_free_price('token', 'app')
        body = next(data for method, _, data in calls if method == 'POST')
        self.assertEqual(body['included'][0]['relationships']['appPricePoint']['data']['id'], 'free')
        self.assertEqual(body['data']['relationships']['baseTerritory']['data']['id'], 'USA')

    def test_refuses_to_replace_paid_schedule(self):
        responses = [{'data': {'id': 'schedule'}}, {'data': [{'id': 'price'}],
                     'included': [{'type': 'appPricePoints', 'attributes': {'customerPrice': '0.99'}}]}]
        with patch.object(subject.asc, 'request', side_effect=responses) as request:
            with self.assertRaisesRegex(RuntimeError, 'refusing to overwrite'):
                subject.configure_free_price('token', 'app')
        self.assertEqual(request.call_count, 2)

    def test_existing_free_schedule_is_unchanged(self):
        responses = [{'data': {'id': 'schedule'}}, {'data': [{'id': 'price'}],
                     'included': [{'type': 'appPricePoints', 'attributes': {'customerPrice': '0'}}]}]
        with patch.object(subject.asc, 'request', side_effect=responses) as request:
            subject.configure_free_price('token', 'app')
        self.assertEqual(request.call_count, 2)

    def test_missing_free_price_is_rejected(self):
        with patch.object(subject.asc, 'request', side_effect=[{'data': None}, {'data': []}]):
            with self.assertRaisesRegex(RuntimeError, 'Expected one free'):
                subject.configure_free_price('token', 'app')


if __name__ == '__main__':
    unittest.main()
