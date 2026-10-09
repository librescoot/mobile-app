#!/usr/bin/env python3
"""Upload an AAB to Play's bundle library without assigning it to a track."""

import hashlib
import os
import pathlib
import sys
import urllib.error
import urllib.request

from publish_play import BASE, UPLOAD, request


def discard_edit(token, edit_id):
    req = urllib.request.Request(
        f"{BASE}/edits/{edit_id}",
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=30):
        pass


def upload_bundle(token, bundle_path, version_code):
    bundle = pathlib.Path(bundle_path).read_bytes()
    digest = hashlib.sha256(bundle).hexdigest()

    edit_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    original_tracks = request(token, "GET", f"{BASE}/edits/{edit_id}/tracks").get("tracks", [])
    uploaded = request(
        token,
        "POST",
        f"{UPLOAD}/edits/{edit_id}/bundles?uploadType=media",
        bundle,
        "application/octet-stream",
    )
    if uploaded.get("versionCode") != version_code:
        raise RuntimeError(
            f"uploaded version code {uploaded.get('versionCode')} != expected {version_code}"
        )
    if uploaded.get("sha256") != digest:
        raise RuntimeError("Play returned a different SHA-256 for the uploaded AAB")
    request(token, "POST", f"{BASE}/edits/{edit_id}:commit")

    verify_id = request(token, "POST", f"{BASE}/edits", b"{}")["id"]
    try:
        bundles = request(token, "GET", f"{BASE}/edits/{verify_id}/bundles").get("bundles", [])
        verified = next((item for item in bundles if item.get("versionCode") == version_code), None)
        if verified is None or verified.get("sha256") != digest:
            raise RuntimeError("committed Play bundle library entry does not match the AAB")
        tracks = request(token, "GET", f"{BASE}/edits/{verify_id}/tracks").get("tracks", [])
        if tracks != original_tracks:
            raise RuntimeError("a Play testing or production track changed during the upload")
    finally:
        discard_edit(token, verify_id)

    print(f"Uploaded AAB {pathlib.Path(bundle_path).name} ({version_code}) to Play's bundle library only")
    print(f"AAB SHA-256: {digest}")
    print("Verified all Play tracks are unchanged; no release was created")


def main():
    bundle_path, version_file = sys.argv[1:3]
    version_code = int(pathlib.Path(version_file).read_text().strip())
    upload_bundle(os.environ["GOOGLE_OAUTH_ACCESS_TOKEN"], bundle_path, version_code)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, urllib.error.URLError) as error:
        print(f"Play bundle-library upload failed: {error}", file=sys.stderr)
        sys.exit(1)
