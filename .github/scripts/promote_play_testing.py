#!/usr/bin/env python3
"""Promote one explicitly selected internal phone build to existing closed testing."""

import argparse
import json
import os

from publish_play import BASE, request, track_state


def promote(token, code):
    edit = request(token, 'POST', f'{BASE}/edits', b'{}')['id']
    source = track_state(token, edit, 'internal')
    production = track_state(token, edit, 'production')
    matches = [release for release in source.get('releases', []) if release.get('versionCodes') == [str(code)] and release.get('status') == 'completed']
    if len(matches) != 1:
        raise RuntimeError('the selected build must be the sole version in one completed internal release')
    release = dict(matches[0])
    release['name'] = f'Wearable companion testing ({code})'
    release['status'] = 'completed'
    staged = request(token, 'PUT', f'{BASE}/edits/{edit}/tracks/alpha', json.dumps({'track': 'alpha', 'releases': [release]}).encode())
    if staged.get('releases') != [release]:
        raise RuntimeError('staged closed-testing release differs from the selected internal release')
    request(token, 'POST', f'{BASE}/edits/{edit}:commit')
    verify = request(token, 'POST', f'{BASE}/edits', b'{}')['id']
    if track_state(token, verify, 'alpha').get('releases') != [release]:
        raise RuntimeError('closed-testing release verification failed')
    if track_state(token, verify, 'internal') != source or track_state(token, verify, 'production') != production:
        raise RuntimeError('internal or production track changed during promotion')
    print(f'Promoted phone build {code} from internal to alpha; production and internal unchanged')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version-code', type=int, required=True)
    args = parser.parse_args()
    promote(os.environ['GOOGLE_OAUTH_ACCESS_TOKEN'], args.version_code)


if __name__ == '__main__':
    main()
