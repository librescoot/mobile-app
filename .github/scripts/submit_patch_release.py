#!/usr/bin/env python3
"""Prepare and submit the 1.3.1 iOS update using its exact processed build."""
import argparse
import json
import os
import tempfile
import urllib.parse

import testflight_notes as asc

APP = '6811779595'
VERSION = '1.3.1'


def send(token, method, path, data):
    return asc.request(token, method, f'{asc.API}/{path}', json.dumps({'data': data}).encode())['data']


def submit(token, build_number):
    if asc.resolve_app(token, 'org.librescoot.mobile.unu') != APP:
        raise RuntimeError('Unexpected App Store app')
    build_id = asc.await_build(token, APP, build_number, timeout=60)
    build_data = asc.request(token, 'GET', f'{asc.API}/builds/{build_id}?include=preReleaseVersion')
    pre = [item for item in build_data.get('included', []) if item['type'] == 'preReleaseVersions']
    if len(pre) != 1 or pre[0]['attributes'].get('version') != VERSION:
        raise RuntimeError('Build marketing version is not 1.3.1')
    versions = asc.request(token, 'GET', f'{asc.API}/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=50')['data']
    matches = [v for v in versions if v['attributes']['versionString'] == VERSION]
    if len(matches) > 1:
        raise RuntimeError('Multiple matching App Store versions')
    if not matches:
        if any(v['attributes']['appStoreState'] == 'PREPARE_FOR_SUBMISSION' for v in versions):
            raise RuntimeError('Another editable App Store version exists')
        version = send(token, 'POST', 'appStoreVersions', {
            'type': 'appStoreVersions',
            'attributes': {'platform': 'IOS', 'versionString': VERSION, 'releaseType': 'AFTER_APPROVAL'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}},
        })
    else:
        version = matches[0]
    vid = version['id']
    state = version['attributes']['appStoreState']
    if state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE', 'PENDING_APPLE_RELEASE', 'READY_FOR_SALE'):
        print(f'App Store {VERSION} already submitted: {state}')
        return
    if state != 'PREPARE_FOR_SUBMISSION':
        raise RuntimeError(f'Unexpected App Store version state: {state}')
    locales = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=200')['data']
    german = [item for item in locales if item['attributes']['locale'] == 'de-DE']
    if len(german) != 1:
        raise RuntimeError('Expected an inherited German listing; inspect before changing it')
    loc = german[0]['id']
    sets = asc.request(token, 'GET', f'{asc.API}/appStoreVersionLocalizations/{loc}/appScreenshotSets?include=appScreenshots&limit=50')
    images = [item for item in sets.get('included', []) if item['type'] == 'appScreenshots']
    if not images:
        raise RuntimeError('No inherited screenshots; refusing submission')
    send(token, 'PATCH', f'appStoreVersionLocalizations/{loc}', {
        'type': 'appStoreVersionLocalizations', 'id': loc,
        'attributes': {'whatsNew': 'Offizielle unu-Händler sind in der Werkstattliste erkennbar. App-Version und Buildnummer lassen sich unter Hilfe kopieren.'},
    })
    asc.request(token, 'PATCH', f'{asc.API}/appStoreVersions/{vid}/relationships/build',
                json.dumps({'data': {'type': 'builds', 'id': build_id}}).encode())
    linked = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/build')['data']
    if linked['id'] != build_id or linked['attributes']['processingState'] != 'VALID':
        raise RuntimeError('Attached build is not the intended valid build')
    review = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/appStoreReviewDetail').get('data')
    if not review:
        raise RuntimeError('Review contact not inherited; inspect before submission')
    query = urllib.parse.urlencode({'filter[app]': APP, 'filter[platform]': 'IOS', 'limit': 50})
    submissions = asc.request(token, 'GET', f'{asc.API}/reviewSubmissions?{query}')['data']
    active = [s for s in submissions if s['attributes']['state'] == 'READY_FOR_REVIEW']
    if len(active) > 1:
        raise RuntimeError('Multiple editable review submissions')
    submission = active[0] if active else send(token, 'POST', 'reviewSubmissions', {
        'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}},
    })
    sid = submission['id']
    items = asc.request(token, 'GET', f'{asc.API}/reviewSubmissions/{sid}/items?include=appStoreVersion&limit=100')
    if items['data'] and not any(i['id'] == vid and i['type'] == 'appStoreVersions' for i in items.get('included', [])):
        raise RuntimeError('Review submission contains other items')
    if not items['data']:
        send(token, 'POST', 'reviewSubmissionItems', {'type': 'reviewSubmissionItems', 'relationships': {
            'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sid}},
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}},
        }})
    result = send(token, 'PATCH', f'reviewSubmissions/{sid}', {
        'type': 'reviewSubmissions', 'id': sid, 'attributes': {'submitted': True},
    })
    latest = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}')['data']
    print(f"Submitted {VERSION} build {build_number}: review={result['attributes']['state']}, version={latest['attributes']['appStoreState']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-number', required=True)
    args = parser.parse_args()
    with tempfile.NamedTemporaryFile('w', suffix='.p8') as key:
        os.chmod(key.name, 0o600)
        key.write(os.environ['APPSTORE_PRIVATE_KEY'])
        key.flush()
        token = asc.mint_token(key.name, os.environ['APPSTORE_KEY_ID'], os.environ['APPSTORE_ISSUER_ID'])
        submit(token, args.build_number)


if __name__ == '__main__':
    main()
