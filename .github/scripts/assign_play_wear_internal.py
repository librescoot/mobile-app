#!/usr/bin/env python3
"""Assign an existing verified Wear AAB to internal testing, without reuploading it."""

import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

from publish_play import BASE, request, track_state

TRACK = "wear:internal"


def unchanged_tracks(tracks):
    return {item["track"]: item for item in tracks if item.get("track") != TRACK}


def discard_edit(token, edit_id):
    req = urllib.request.Request(
        f"{BASE}/edits/{edit_id}",
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=30):
        pass


def assign(token, bundle_path, version_code, notes_path):
    bundle = pathlib.Path(bundle_path).read_bytes()
    digest = hashlib.sha256(bundle).hexdigest()
    notes = pathlib.Path(notes_path).read_text(encoding="utf-8").strip()
    if not notes or len(notes) > 500:
        raise RuntimeError("Wear internal release notes must contain 1–500 characters")

    edit_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    bundles = request(token, "GET", f"{BASE}/edits/{edit_id}/bundles").get("bundles", [])
    uploaded = next((item for item in bundles if item.get("versionCode") == version_code), None)
    if uploaded is None or uploaded.get("sha256") != digest:
        raise RuntimeError("the verified AAB is not present in Play's bundle library")
    tracks_before = request(token, "GET", f"{BASE}/edits/{edit_id}/tracks").get("tracks", [])

    release = {
        "track": TRACK,
        "releases": [{
            "name": f"Wear OS internal {version_code}",
            "status": "completed",
            "versionCodes": [str(version_code)],
            "releaseNotes": [{"language": "en-US", "text": notes}],
        }],
    }
    staged = request(
        token,
        "PUT",
        f"{BASE}/edits/{edit_id}/tracks/{TRACK}",
        json.dumps(release).encode(),
    )
    codes = staged["releases"][0]["versionCodes"]
    if codes != [str(version_code)]:
        raise RuntimeError(f"staged Wear internal track has unexpected version codes: {codes}")
    request(token, "POST", f"{BASE}/edits/{edit_id}:commit")

    verify_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    try:
        verified_track = track_state(token, verify_id, TRACK)
        verified_release = next(
            (item for item in verified_track.get("releases", [])
             if str(version_code) in item.get("versionCodes", [])),
            None,
        )
        if verified_release is None or verified_release.get("status") != "completed":
            raise RuntimeError("the Wear internal release was not committed as completed")
        verified_bundles = request(
            token, "GET", f"{BASE}/edits/{verify_id}/bundles"
        ).get("bundles", [])
        verified_bundle = next(
            (item for item in verified_bundles if item.get("versionCode") == version_code),
            None,
        )
        if verified_bundle is None or verified_bundle.get("sha256") != digest:
            raise RuntimeError("the internal release does not reference the expected AAB")
        tracks_after = request(token, "GET", f"{BASE}/edits/{verify_id}/tracks").get("tracks", [])
        if unchanged_tracks(tracks_after) != unchanged_tracks(tracks_before):
            raise RuntimeError("a track other than Wear internal changed during assignment")
    finally:
        discard_edit(token, verify_id)

    print(f"Assigned Wear AAB ({version_code}) to {TRACK}")
    print(f"AAB SHA-256: {digest}")
    print("Verified all other tracks are unchanged")


def main():
    bundle_path, version_file, notes_path = sys.argv[1:4]
    version_code = int(pathlib.Path(version_file).read_text().strip())
    assign(os.environ["GOOGLE_OAUTH_ACCESS_TOKEN"], bundle_path, version_code, notes_path)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, urllib.error.URLError) as error:
        print(f"Wear internal assignment failed: {error}", file=sys.stderr)
        sys.exit(1)
