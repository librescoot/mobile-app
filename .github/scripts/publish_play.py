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
    parser.add_argument(
        "--notes-file",
        help="single-language release notes for every locale",
    )
    parser.add_argument(
        "--notes-language",
        default="en-US",
        help="language code for --notes-file (default en-US)",
    )
    parser.add_argument(
        "--notes-dir",
        help="per-locale changelog root, keyed by version name",
    )
    parser.add_argument(
        "--notes-version",
        help="version name selecting <locale>/changelogs/<version>.txt under --notes-dir",
    )
    args = parser.parse_args()

    if bool(args.notes_file) == bool(args.notes_dir):
        parser.error("pass either --notes-file or --notes-dir/--notes-version")
    if args.notes_dir and not args.notes_version:
        parser.error("--notes-dir requires --notes-version")

    token = os.environ["GOOGLE_OAUTH_ACCESS_TOKEN"]
    with open(args.aab, "rb") as file:
        bundle = file.read()
    digest = hashlib.sha256(bundle).hexdigest()
    release_notes = collect_notes(args)
    if not release_notes:
        raise RuntimeError("no release notes found")
    for note in release_notes:
        if len(note["text"]) > 500:
            raise RuntimeError(
                f"release notes for {note['language']} exceed 500 characters "
                f"({len(note['text'])})"
            )

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
                "releaseNotes": release_notes,
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
    print(f"Release notes languages: {', '.join(n['language'] for n in release_notes)}")


def collect_notes(args):
    if args.notes_file:
        with open(args.notes_file, encoding="utf-8") as file:
            return [{"language": args.notes_language, "text": file.read()}]

    root = os.path.join(args.notes_dir, "en-US", "changelogs", f"{args.notes_version}.txt")
    if not os.path.isfile(root):
        raise RuntimeError(f"missing required en-US notes: {root}")
    notes = []
    for locale in sorted(os.listdir(args.notes_dir)):
        path = os.path.join(args.notes_dir, locale, "changelogs", f"{args.notes_version}.txt")
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as file:
            notes.append({"language": locale, "text": file.read()})
    return notes


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError) as error:
        print(f"Play publication failed: {error}", file=sys.stderr)
        sys.exit(1)
