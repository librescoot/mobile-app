#!/usr/bin/env python3
"""Upload reviewed iOS simulator screenshots to the initial App Store listing."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import urllib.request

import testflight_notes as asc

APP = '6811779595'
VERSION = '1.3.0'


def post(token, resource, data):
    return asc.request(token, 'POST', f'{asc.API}/{resource}', json.dumps({'data': data}).encode())['data']


def upload(token, localization, display_type, file):
    sets = asc.request(token, 'GET', f'{asc.API}/appStoreVersionLocalizations/{localization}/appScreenshotSets?limit=200')['data']
    matches = [s for s in sets if s['attributes']['screenshotDisplayType'] == display_type]
    if len(matches) > 1:
        raise RuntimeError(f'Multiple screenshot sets for {display_type}')
    if matches:
        screen_set = matches[0]
        existing = asc.request(token, 'GET', f"{asc.API}/appScreenshotSets/{screen_set['id']}/appScreenshots?limit=200")['data']
        if existing:
            raise RuntimeError(f'Refusing to overwrite existing screenshots for {display_type}')
    else:
        screen_set = post(token, 'appScreenshotSets', {'type': 'appScreenshotSets',
            'attributes': {'screenshotDisplayType': display_type},
            'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': localization}}}})
    content = file.read_bytes()
    shot = post(token, 'appScreenshots', {'type': 'appScreenshots',
        'attributes': {'fileName': file.name, 'fileSize': len(content)},
        'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': screen_set['id']}}}})
    for op in shot['attributes']['uploadOperations']:
        headers = {h['name']: h['value'] for h in op['requestHeaders']}
        chunk = content[op['offset']:op['offset'] + op['length']]
        req = urllib.request.Request(op['url'], data=chunk, headers=headers, method=op['method'])
        with urllib.request.urlopen(req, timeout=120) as response:
            response.read()
    payload = {'data': {'type': 'appScreenshots', 'id': shot['id'], 'attributes': {
        'uploaded': True, 'sourceFileChecksum': hashlib.md5(content).hexdigest()}}}
    asc.request(token, 'PATCH', f"{asc.API}/appScreenshots/{shot['id']}", json.dumps(payload).encode())
    for _ in range(30):
        result = asc.request(token, 'GET', f"{asc.API}/appScreenshots/{shot['id']}")['data']
        state = result['attributes']['assetDeliveryState']['state']
        if state == 'COMPLETE':
            print(f'Uploaded {display_type}: {file.name}; Apple asset processing COMPLETE')
            return
        if state in ('FAILED', 'REJECTED'):
            raise RuntimeError(f'Screenshot processing failed: {state}')
        time.sleep(5)
    raise RuntimeError(f'Screenshot processing did not complete: {display_type}')


def main():
    with tempfile.NamedTemporaryFile('w', suffix='.p8') as key:
        os.chmod(key.name, 0o600)
        key.write(os.environ['APPSTORE_PRIVATE_KEY'])
        key.flush()
        token = asc.mint_token(key.name, os.environ['APPSTORE_KEY_ID'], os.environ['APPSTORE_ISSUER_ID'])
        if asc.resolve_app(token, 'org.librescoot.mobile.unu') != APP:
            raise RuntimeError('Unexpected App Store app')
        versions = asc.request(token, 'GET', f'{asc.API}/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=20')['data']
        versions = [v for v in versions if v['attributes']['versionString'] == VERSION and v['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION']
        if len(versions) != 1:
            raise RuntimeError('Expected one editable 1.3.0 version')
        localizations = asc.request(token, 'GET', f"{asc.API}/appStoreVersions/{versions[0]['id']}/appStoreVersionLocalizations?limit=200")['data']
        locales = [l for l in localizations if l['attributes']['locale'] == 'de-DE']
        if len(locales) != 1:
            raise RuntimeError('Expected one German listing')
        upload(token, locales[0]['id'], 'APP_IPHONE_61', Path('screenshots/iphone.jpg'))
        upload(token, locales[0]['id'], 'APP_IPAD_PRO_3GEN_129', Path('screenshots/ipad.jpg'))


if __name__ == '__main__':
    main()
