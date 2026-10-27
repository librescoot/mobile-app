#!/usr/bin/env python3
"""Submit the prepared initial iOS App Store version for review."""
import json
import os
import tempfile
import urllib.parse

import testflight_notes as asc

APP = '6811779595'
VERSION = '1.3.0'
BUILD = '215260239'


def send(token, method, resource, data):
    return asc.request(token, method, f'{asc.API}/{resource}', json.dumps({'data': data}).encode())['data']


def main():
    with tempfile.NamedTemporaryFile('w', suffix='.p8') as key:
        os.chmod(key.name, 0o600)
        key.write(os.environ['APPSTORE_PRIVATE_KEY'])
        key.flush()
        token = asc.mint_token(key.name, os.environ['APPSTORE_KEY_ID'], os.environ['APPSTORE_ISSUER_ID'])
        if asc.resolve_app(token, 'org.librescoot.mobile.unu') != APP:
            raise RuntimeError('Unexpected App Store app')
        versions = asc.request(token, 'GET', f'{asc.API}/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=20')['data']
        matches = [v for v in versions if v['attributes']['versionString'] == VERSION]
        if len(matches) != 1:
            raise RuntimeError('Expected exactly one App Store version 1.3.0')
        version = matches[0]
        state = version['attributes']['appStoreState']
        if state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE', 'PENDING_APPLE_RELEASE', 'READY_FOR_SALE'):
            print(f'App Store version {VERSION} already submitted: {state}')
            return
        if state != 'PREPARE_FOR_SUBMISSION':
            raise RuntimeError(f'Unexpected App Store version state: {state}')
        vid = version['id']
        build = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/build')['data']
        if build['attributes']['version'] != BUILD or build['attributes']['processingState'] != 'VALID':
            raise RuntimeError('Attached build is not the intended valid production build')
        query = urllib.parse.urlencode({'filter[app]': APP, 'filter[platform]': 'IOS', 'limit': 50})
        submissions = asc.request(token, 'GET', f'{asc.API}/reviewSubmissions?{query}')['data']
        active = [s for s in submissions if s['attributes']['state'] == 'READY_FOR_REVIEW']
        if len(active) > 1:
            raise RuntimeError('Multiple editable review submissions; refusing to choose')
        if active:
            submission = active[0]
        else:
            submission = send(token, 'POST', 'reviewSubmissions', {'type': 'reviewSubmissions',
                'attributes': {'platform': 'IOS'}, 'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}})
        sid = submission['id']
        items = asc.request(token, 'GET', f'{asc.API}/reviewSubmissions/{sid}/items?include=appStoreVersion&limit=100')
        included = items.get('included', [])
        if items['data'] and not any(i['id'] == vid and i['type'] == 'appStoreVersions' for i in included):
            raise RuntimeError('Existing review submission contains other items; refusing to change it')
        if not items['data']:
            send(token, 'POST', 'reviewSubmissionItems', {'type': 'reviewSubmissionItems', 'relationships': {
                'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sid}},
                'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}}})
        result = send(token, 'PATCH', f'reviewSubmissions/{sid}', {'type': 'reviewSubmissions', 'id': sid,
            'attributes': {'submitted': True}})
        print('Submitted review:', result['attributes']['state'])
        latest = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}')['data']
        print(f"App Store version {VERSION} state: {latest['attributes']['appStoreState']}")


if __name__ == '__main__':
    main()
