#!/usr/bin/env python3
"""Publish a verified existing Wear AAB to closed and open Wear test tracks."""

import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

from publish_play import BASE, request, track_state

CLOSED_TRACK = "wear:alpha"
OPEN_TRACK = "wear:beta"
TARGET_TRACKS = {CLOSED_TRACK, OPEN_TRACK}


def discard_edit(token, edit_id):
    req = urllib.request.Request(
        f"{BASE}/edits/{edit_id}",
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=30):
        pass


def other_tracks(tracks):
    return {
        item["track"]: item
        for item in tracks
        if item.get("track") not in TARGET_TRACKS
    }


def has_version(state, version_code):
    return any(
        str(version_code) in release.get("versionCodes", [])
        for release in state.get("releases", [])
    )


def ensure_closed_track(token):
    edit_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    tracks = request(token, "GET", f"{BASE}/edits/{edit_id}/tracks").get("tracks", [])
    if any(item.get("track") == CLOSED_TRACK for item in tracks):
        discard_edit(token, edit_id)
        return

    created = request(
        token,
        "POST",
        f"{BASE}/edits/{edit_id}/tracks",
        json.dumps({
            "track": CLOSED_TRACK,
            "type": "CLOSED_TESTING",
            "formFactor": "WEAR",
        }).encode(),
    )
    if created.get("track") != CLOSED_TRACK:
        discard_edit(token, edit_id)
        raise RuntimeError(f"Play did not create the expected Wear closed track: {created}")
    request(token, "POST", f"{BASE}/edits/{edit_id}:commit")

    verify_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    try:
        tracks_after = request(
            token, "GET", f"{BASE}/edits/{verify_id}/tracks"
        ).get("tracks", [])
        if not any(item.get("track") == CLOSED_TRACK for item in tracks_after):
            raise RuntimeError("Play did not retain the Wear closed-testing track")
    finally:
        discard_edit(token, verify_id)
    print(f"Created Wear closed-testing track {CLOSED_TRACK}")


def publish(token, bundle_path, version_code, notes_path):
    bundle = pathlib.Path(bundle_path).read_bytes()
    digest = hashlib.sha256(bundle).hexdigest()
    notes = pathlib.Path(notes_path).read_text(encoding="utf-8").strip()
    if not notes or len(notes) > 500:
        raise RuntimeError("Wear testing release notes must contain 1–500 characters")

    ensure_closed_track(token)
    edit_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    bundles = request(token, "GET", f"{BASE}/edits/{edit_id}/bundles").get("bundles", [])
    uploaded = next((item for item in bundles if item.get("versionCode") == version_code), None)
    if uploaded is None or uploaded.get("sha256") != digest:
        raise RuntimeError("the verified AAB is not present in Play's bundle library")
    tracks_before = request(token, "GET", f"{BASE}/edits/{edit_id}/tracks").get("tracks", [])
    known_tracks = {item["track"] for item in tracks_before}
    missing_tracks = {CLOSED_TRACK, OPEN_TRACK} - known_tracks
    if missing_tracks:
        raise RuntimeError(f"Wear testing tracks are missing: {', '.join(sorted(missing_tracks))}")

    changed = []
    for track in (CLOSED_TRACK, OPEN_TRACK):
        state = track_state(token, edit_id, track)
        if has_version(state, version_code):
            print(f"{track} already contains version {version_code}")
            continue
        release = {
            "track": track,
            "releases": [{
                "name": f"Wear OS test {version_code}",
                "status": "completed",
                "versionCodes": [str(version_code)],
                "releaseNotes": [{"language": "en-US", "text": notes}],
            }],
        }
        staged = request(
            token,
            "PUT",
            f"{BASE}/edits/{edit_id}/tracks/{track}",
            json.dumps(release).encode(),
        )
        codes = staged["releases"][0]["versionCodes"]
        if codes != [str(version_code)]:
            discard_edit(token, edit_id)
            raise RuntimeError(f"staged {track} has unexpected version codes: {codes}")
        changed.append(track)

    if changed:
        request(token, "POST", f"{BASE}/edits/{edit_id}:commit")
    else:
        discard_edit(token, edit_id)

    verify_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    try:
        verified_bundles = request(
            token, "GET", f"{BASE}/edits/{verify_id}/bundles"
        ).get("bundles", [])
        verified_bundle = next(
            (item for item in verified_bundles if item.get("versionCode") == version_code),
            None,
        )
        if verified_bundle is None or verified_bundle.get("sha256") != digest:
            raise RuntimeError("Play's committed bundle does not match the AAB")
        for track in (CLOSED_TRACK, OPEN_TRACK):
            state = track_state(token, verify_id, track)
            if not has_version(state, version_code):
                raise RuntimeError(f"version {version_code} is missing from {track}")
        tracks_after = request(
            token, "GET", f"{BASE}/edits/{verify_id}/tracks"
        ).get("tracks", [])
        if other_tracks(tracks_after) != other_tracks(tracks_before):
            raise RuntimeError("a Wear internal, phone, or production track changed")
    finally:
        discard_edit(token, verify_id)

    print(f"Published Wear AAB ({version_code}) to {CLOSED_TRACK} and {OPEN_TRACK}")
    print(f"AAB SHA-256: {digest}")
    print("Verified Wear internal, phone, and production tracks are unchanged")
    print("Closed-track email lists are managed in Play Console and are not exposed by the Publisher API")


def main():
    bundle_path, version_file, notes_path = sys.argv[1:4]
    version_code = int(pathlib.Path(version_file).read_text().strip())
    publish(os.environ["GOOGLE_OAUTH_ACCESS_TOKEN"], bundle_path, version_code, notes_path)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, urllib.error.URLError) as error:
        print(f"Wear test-track publication failed: {error}", file=sys.stderr)
        sys.exit(1)
