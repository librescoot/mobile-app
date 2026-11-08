#!/usr/bin/env python3
"""Inspect iOS review submissions without changing App Store data."""
import json
import os
import tempfile
import urllib.parse

import testflight_notes as asc

app = '6811779595'
with tempfile.NamedTemporaryFile('w', suffix='.p8') as key:
    os.chmod(key.name, 0o600)
    key.write(os.environ['APPSTORE_PRIVATE_KEY'])
    key.flush()
    token = asc.mint_token(key.name, os.environ['APPSTORE_KEY_ID'], os.environ['APPSTORE_ISSUER_ID'])
    if asc.resolve_app(token, 'org.librescoot.mobile.unu') != app:
        raise RuntimeError('Unexpected App Store app')
    query = urllib.parse.urlencode({'filter[app]': app, 'filter[platform]': 'IOS', 'limit': 50})
    submissions = asc.request(token, 'GET', f'{asc.API}/reviewSubmissions?{query}')['data']
    for submission in submissions:
        sid = submission['id']
        items = asc.request(token, 'GET', f'{asc.API}/reviewSubmissions/{sid}/items?include=appStoreVersion&limit=100')
        versions = [{'id': item['id'], 'version': item.get('attributes', {}).get('versionString')}
                    for item in items.get('included', []) if item['type'] == 'appStoreVersions']
        print(json.dumps({'id': sid, 'state': submission['attributes']['state'],
                          'itemCount': len(items['data']), 'versions': versions}))
