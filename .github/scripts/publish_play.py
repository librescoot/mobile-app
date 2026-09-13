#!/usr/bin/env python3
"""Publish one verified Android App Bundle with a short-lived OAuth token."""

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

PACKAGE = "org.librescoot.mobile.unu"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"


def request(token, method, url, body=None, content_type="application/json"):
    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url}: {error.code} {detail}") from error


def track_state(token, edit_id, track):
    return request(token, "GET", f"{BASE}/edits/{edit_id}/tracks/{track}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--aab", required=True)
    parser.add_argument("--track", required=True, choices=("internal", "alpha", "beta", "production"))
    parser.add_argument("--name", required=True)
    parser.add_argument("--version-code", required=True, type=int)
    parser.add_argument("--notes-file", required=True)
    args = parser.parse_args()

    token = os.environ["GOOGLE_OAUTH_ACCESS_TOKEN"]
    with open(args.aab, "rb") as file:
        bundle = file.read()
    digest = hashlib.sha256(bundle).hexdigest()
    with open(args.notes_file, encoding="utf-8") as file:
        notes = file.read()
    if len(notes) > 500:
        raise RuntimeError("Google Play release notes exceed 500 characters")

    edit = request(token, "POST", f"{BASE}/edits", b"{}")
    edit_id = edit["id"]
    production_before = track_state(token, edit_id, "production")

    uploaded = request(
        token,
        "POST",
        f"{UPLOAD}/edits/{edit_id}/bundles?uploadType=media",
        bundle,
        "application/octet-stream",
    )
    if uploaded.get("versionCode") != args.version_code:
        raise RuntimeError(
            f"uploaded version code {uploaded.get('versionCode')} != expected {args.version_code}"
        )
    if uploaded.get("sha256") != digest:
        raise RuntimeError("Play returned a different SHA-256 for the uploaded AAB")

    release = {
        "track": args.track,
        "releases": [
            {
                "name": args.name,
                "status": "completed",
                "versionCodes": [str(args.version_code)],
                "releaseNotes": [{"language": "en-US", "text": notes}],
            }
        ],
    }
    staged = request(
        token,
        "PUT",
        f"{BASE}/edits/{edit_id}/tracks/{args.track}",
        json.dumps(release).encode(),
    )
    codes = staged["releases"][0]["versionCodes"]
    if codes != [str(args.version_code)]:
        raise RuntimeError(f"staged track has unexpected version codes: {codes}")
    request(token, "POST", f"{BASE}/edits/{edit_id}:commit")

    verify = request(token, "POST", f"{BASE}/edits", b"{}")
    verify_id = verify["id"]
    verified_track = track_state(token, verify_id, args.track)
    verified_codes = verified_track["releases"][0]["versionCodes"]
    bundles = request(token, "GET", f"{BASE}/edits/{verify_id}/bundles").get("bundles", [])
    verified_bundle = next((item for item in bundles if item.get("versionCode") == args.version_code), None)
    production_after = track_state(token, verify_id, "production")
    if verified_codes != [str(args.version_code)]:
        raise RuntimeError(f"committed track has unexpected version codes: {verified_codes}")
    if verified_bundle is None or verified_bundle.get("sha256") != digest:
        raise RuntimeError("committed bundle digest does not match the uploaded AAB")
    if args.track != "production" and production_after != production_before:
        raise RuntimeError("production track changed while publishing a testing build")

    print(f"Published {args.name} ({args.version_code}) to {args.track}")
    print(f"AAB SHA-256: {digest}")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError) as error:
        print(f"Play publication failed: {error}", file=sys.stderr)
        sys.exit(1)
