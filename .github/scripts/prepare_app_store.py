#!/usr/bin/env python3
"""Prepare the existing initial App Store listing and attach a validated build."""

import argparse
import json
import os
import tempfile
import urllib.parse
from pathlib import Path

import testflight_notes as asc

APP_ID = '6811779595'
VERSION = '1.3.0'
PRIVACY = 'https://librescoot.org/privacy/mobile-app/'
SUPPORT = 'https://github.com/librescoot/mobile-app/issues'


def patch(token, resource, identifier, attributes=None, relationships=None):
    data = {'type': resource, 'id': identifier}
    if attributes is not None:
        data['attributes'] = attributes
    if relationships is not None:
        data['relationships'] = relationships
    return asc.request(token, 'PATCH', f'{asc.API}/{resource}/{identifier}',
                       json.dumps({'data': data}).encode())['data']


def configure_free_price(token, app):
    schedule = asc.request(token, 'GET', f'{asc.API}/apps/{app}/appPriceSchedule').get('data')
    if schedule:
        try:
            prices = asc.request(token, 'GET', f"{asc.API}/appPriceSchedules/{schedule['id']}/manualPrices?include=appPricePoint&limit=200")
        except RuntimeError as error:
            if ': 404 ' not in str(error) or '"code" : "NOT_FOUND"' not in str(error):
                raise
            prices = None
        if prices is not None:
            points = [p for p in prices.get('included', []) if p['type'] == 'appPricePoints']
            if len(prices['data']) != 1 or len(points) != 1 or float(points[0]['attributes']['customerPrice']) != 0:
                raise RuntimeError('Existing price schedule is not a single free base price; refusing to overwrite it')
            print('Existing free base price schedule verified')
            return
    query = urllib.parse.urlencode({'filter[territory]': 'USA', 'limit': 200})
    url = f'{asc.API}/apps/{app}/appPricePoints?{query}'
    free = []
    while url:
        page = asc.request(token, 'GET', url)
        free.extend(p for p in page['data'] if float(p['attributes']['customerPrice']) == 0)
        url = page.get('links', {}).get('next')
    if len(free) != 1:
        raise RuntimeError(f'Expected one free US price point; found {len(free)}')
    temporary_id = '${free-price}'
    payload = {'data': {'type': 'appPriceSchedules', 'relationships': {
        'app': {'data': {'type': 'apps', 'id': app}},
        'baseTerritory': {'data': {'type': 'territories', 'id': 'USA'}},
        'manualPrices': {'data': [{'type': 'appPrices', 'id': temporary_id}]} }},
        'included': [{'type': 'appPrices', 'id': temporary_id,
                      'attributes': {'startDate': None, 'endDate': None},
                      'relationships': {'appPricePoint': {'data': {'type': 'appPricePoints', 'id': free[0]['id']}}}}]}
    asc.request(token, 'POST', f'{asc.API}/appPriceSchedules', json.dumps(payload).encode())
    schedule = asc.request(token, 'GET', f'{asc.API}/apps/{app}/appPriceSchedule').get('data')
    if not schedule:
        raise RuntimeError('Free price schedule did not persist')
    print('Created free US base price schedule')


def prepare(token, build_number):
    app = asc.resolve_app(token, 'org.librescoot.mobile.unu')
    if app != APP_ID:
        raise RuntimeError(f'Unexpected App Store app id: {app}')
    versions = asc.request(token, 'GET', f'{asc.API}/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=20')['data']
    candidates = [v for v in versions if v['attributes'].get('appStoreState') == 'PREPARE_FOR_SUBMISSION']
    if len(candidates) != 1:
        raise RuntimeError('Expected exactly one editable iOS App Store version')
    version = candidates[0]
    vid = version['id']
    current = version['attributes']['versionString']
    if current not in ('1.0', VERSION):
        raise RuntimeError(f'Refusing to replace unexpected editable version {current}')
    build = asc.await_build(token, app, build_number, timeout=30)
    build_data = asc.request(token, 'GET', f'{asc.API}/builds/{build}?include=preReleaseVersion')
    pre = [p for p in build_data.get('included', []) if p['type'] == 'preReleaseVersions']
    if len(pre) != 1 or pre[0]['attributes'].get('version') != VERSION:
        raise RuntimeError('Build marketing version is not 1.3.0')
    if current != VERSION:
        patch(token, 'appStoreVersions', vid, {'versionString': VERSION, 'releaseType': 'AFTER_APPROVAL'})
    locales = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=200')['data']
    matches = [l for l in locales if l['attributes'].get('locale') == 'de-DE']
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one German version localization')
    description = Path('distribution/play/metadata/android/de-DE/full_description.txt').read_text()
    description = description.replace('Unter Android 11 und älter benötigt die Bluetooth-Suche außerdem eine Standortberechtigung und aktivierte Standortdienste. ', '')
    patch(token, 'appStoreVersionLocalizations', matches[0]['id'], {
        'description': description,
        'keywords': 'Scooter,unu,Bluetooth,Roller,Akku,Navigation,Librescoot',
        'supportUrl': SUPPORT,
        'marketingUrl': 'https://librescoot.org/',
    })
    infos = asc.request(token, 'GET', f'{asc.API}/apps/{app}/appInfos?limit=20')['data']
    editable = [i for i in infos if i['attributes'].get('appStoreState') == 'PREPARE_FOR_SUBMISSION']
    if len(editable) != 1:
        raise RuntimeError('Expected exactly one editable app information record')
    app_locales = asc.request(token, 'GET', f"{asc.API}/appInfos/{editable[0]['id']}/appInfoLocalizations?limit=200")['data']
    info_matches = [l for l in app_locales if l['attributes'].get('locale') == 'de-DE']
    if len(info_matches) != 1:
        raise RuntimeError('Expected exactly one German app information localization')
    patch(token, 'appInfoLocalizations', info_matches[0]['id'], {'privacyPolicyUrl': PRIVACY})
    patch(token, 'appInfos', editable[0]['id'], relationships={
        'primaryCategory': {'data': {'type': 'appCategories', 'id': 'UTILITIES'}}})
    patch(token, 'appStoreVersions', vid, {'copyright': '2026 Librescoot contributors'})
    patch(token, 'apps', app, {'contentRightsDeclaration': 'USES_THIRD_PARTY_CONTENT'})
    configure_free_price(token, app)
    asc.request(token, 'PATCH', f'{asc.API}/appStoreVersions/{vid}/relationships/build',
                json.dumps({'data': {'type': 'builds', 'id': build}}).encode())
    linked = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/build')['data']
    if linked['id'] != build:
        raise RuntimeError('App Store version build link did not persist')
    review = asc.request(token, 'GET', f'{asc.API}/appStoreVersions/{vid}/appStoreReviewDetail').get('data')
    if not review:
        beta = asc.request(token, 'GET', f'{asc.API}/apps/{app}/betaAppReviewDetail').get('data')
        if not beta:
            raise RuntimeError('Existing TestFlight review contact is unavailable')
        fields = beta['attributes']
        names = ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail', 'notes',
                 'demoAccountRequired', 'demoAccountName', 'demoAccountPassword')
        contact = {k: fields[k] for k in names if fields.get(k) is not None}
        if not all(contact.get(k) for k in names[:4]):
            raise RuntimeError('Existing TestFlight review contact is incomplete')
        asc.request(token, 'POST', f'{asc.API}/appStoreReviewDetails', json.dumps({'data': {
            'type': 'appStoreReviewDetails', 'attributes': contact,
            'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}},
        }}).encode())
    print(f'Prepared App Store version {VERSION}; linked valid build {build_number}; updated German listing, privacy URL and review contact')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-number', required=True)
    args = parser.parse_args()
    with tempfile.NamedTemporaryFile('w', suffix='.p8') as key:
        os.chmod(key.name, 0o600)
        key.write(os.environ['APPSTORE_PRIVATE_KEY'])
        key.flush()
        token = asc.mint_token(key.name, os.environ['APPSTORE_KEY_ID'], os.environ['APPSTORE_ISSUER_ID'])
        prepare(token, args.build_number)


if __name__ == '__main__':
    main()
