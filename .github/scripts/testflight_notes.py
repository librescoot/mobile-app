#!/usr/bin/env python3
"""Publish TestFlight "What to Test" notes for a build that was just uploaded.

The upload action has no way to set these, so the notes are written through the
App Store Connect API afterwards: the build is resolved by its build number, and
the per-locale betaBuildLocalizations are created or updated.

JWT signing goes through openssl rather than a Python JWT library so the CI job
needs no extra dependencies.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_LOCALE = "en-US"
MAX_WHATS_NEW = 4000
JOSE_KEY_BYTES = 32
KEY_ENV = "APPSTORE_PRIVATE_KEY"


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_signature_to_jose(der):
    if not der or der[0] != 0x30:
        raise RuntimeError("openssl returned an unexpected signature encoding")
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    values = []
    for _ in range(2):
        if der[index] != 0x02:
            raise RuntimeError("openssl returned an unexpected integer encoding")
        length = der[index + 1]
        values.append(int.from_bytes(der[index + 2:index + 2 + length], "big"))
        index += 2 + length
    return b"".join(value.to_bytes(JOSE_KEY_BYTES, "big") for value in values)


def mint_token(key_path, key_id, issuer_id, ttl=900):
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + ttl, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload)
    )
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout
    return signing_input + "." + b64url(der_signature_to_jose(der))


def request(token, method, url, body=None):
    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url}: {error.code} {detail}") from error


def collect_notes(args):
    if args.notes_file:
        with open(args.notes_file, encoding="utf-8") as file:
            return {args.notes_language: file.read()}

    required = os.path.join(args.notes_dir, "en-US", "changelogs", f"{args.notes_version}.txt")
    if not os.path.isfile(required):
        raise RuntimeError(f"missing required en-US notes: {required}")
    notes = {}
    for locale in sorted(os.listdir(args.notes_dir)):
        path = os.path.join(args.notes_dir, locale, "changelogs", f"{args.notes_version}.txt")
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as file:
                notes[locale] = file.read()
    return notes


def resolve_app(token, bundle_id):
    result = request(token, "GET", f"{API}/apps?filter[bundleId]={bundle_id}&limit=1")
    data = result.get("data") or []
    if not data:
        raise RuntimeError(f"no app in App Store Connect has bundle id {bundle_id!r}")
    return data[0]["id"]


def await_build(token, app_id, build_number, timeout):
    url = (
        f"{API}/builds?filter[app]={app_id}&filter[version]={build_number}"
        "&limit=1&sort=-uploadedDate"
    )
    deadline = time.monotonic() + timeout
    seen = None
    while True:
        data = request(token, "GET", url).get("data") or []
        state = data[0]["attributes"]["processingState"] if data else None
        if state != seen:
            print(f"build {build_number}: {state or 'not yet listed'}")
            seen = state
        if state == "VALID":
            return data[0]["id"]
        if state in ("FAILED", "INVALID"):
            raise RuntimeError(f"build {build_number} was rejected by App Store Connect ({state})")
        if time.monotonic() >= deadline:
            raise RuntimeError(
                f"build {build_number} was still {state or 'missing'} after {timeout}s; "
                "notes were not published"
            )
        time.sleep(15)


def find_localization(token, build_id, locale):
    url = f"{API}/betaBuildLocalizations?filter[build]={build_id}&filter[locale]={locale}&limit=1"
    data = request(token, "GET", url).get("data") or []
    return data[0]["id"] if data else None


def write_notes(token, build_id, locale, text, dry_run):
    if dry_run:
        print(f"would set {locale} notes ({len(text)} chars)")
        return
    existing = find_localization(token, build_id, locale)
    if existing:
        body = json.dumps(
            {
                "data": {
                    "type": "betaBuildLocalizations",
                    "id": existing,
                    "attributes": {"whatsNew": text},
                }
            }
        ).encode()
        request(token, "PATCH", f"{API}/betaBuildLocalizations/{existing}", body)
        print(f"updated {locale} notes ({len(text)} chars)")
    else:
        body = json.dumps(
            {
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": locale, "whatsNew": text},
                    "relationships": {
                        "build": {"data": {"type": "builds", "id": build_id}}
                    },
                }
            }
        ).encode()
        request(token, "POST", f"{API}/betaBuildLocalizations", body)
        print(f"created {locale} notes ({len(text)} chars)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-id", default="org.librescoot.mobile.unu")
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--notes-file", help="single-language notes")
    parser.add_argument(
        "--notes-language",
        default=DEFAULT_LOCALE,
        help=f"locale for --notes-file (default {DEFAULT_LOCALE})",
    )
    parser.add_argument("--notes-dir", help="per-locale changelog root, keyed by version name")
    parser.add_argument(
        "--notes-version",
        help="version name selecting <locale>/changelogs/<version>.txt under --notes-dir",
    )
    parser.add_argument("--issuer-id", default=os.environ.get("APPSTORE_ISSUER_ID"))
    parser.add_argument("--key-id", default=os.environ.get("APPSTORE_KEY_ID"))
    parser.add_argument(
        "--private-key",
        help=f"path to the .p8 key; defaults to the {KEY_ENV} environment variable",
    )
    parser.add_argument("--timeout", type=int, default=900, help="seconds to await processing")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if bool(args.notes_file) == bool(args.notes_dir):
        parser.error("pass either --notes-file or --notes-dir/--notes-version")
    if args.notes_dir and not args.notes_version:
        parser.error("--notes-dir requires --notes-version")
    for name, value in (("--issuer-id", args.issuer_id), ("--key-id", args.key_id)):
        if not value:
            parser.error(f"{name} is required (or set the matching APPSTORE_* variable)")

    notes = collect_notes(args)
    if not notes:
        raise RuntimeError("no notes found")
    for locale, text in notes.items():
        if not text.strip():
            raise RuntimeError(f"notes for {locale} are empty")
        if len(text) > MAX_WHATS_NEW:
            raise RuntimeError(
                f"notes for {locale} exceed {MAX_WHATS_NEW} characters ({len(text)})"
            )

    temporary = None
    key_path = args.private_key
    if not key_path:
        key_content = os.environ.get(KEY_ENV)
        if not key_content:
            parser.error(f"pass --private-key or set {KEY_ENV}")
        handle = tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False)
        os.chmod(handle.name, 0o600)
        handle.write(key_content if key_content.endswith("\n") else key_content + "\n")
        handle.close()
        temporary = key_path = handle.name

    try:
        token = mint_token(key_path, args.key_id, args.issuer_id)
        app_id = resolve_app(token, args.bundle_id)
        build_id = await_build(token, app_id, args.build_number, args.timeout)
        for locale, text in sorted(notes.items()):
            write_notes(token, build_id, locale, text, args.dry_run)
    finally:
        if temporary:
            os.unlink(temporary)

    action = "Would publish" if args.dry_run else "Published"
    print(f"{action} What to Test for build {args.build_number}: {', '.join(sorted(notes))}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f"TestFlight notes failed: {error}", file=sys.stderr)
        sys.exit(1)
