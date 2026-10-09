#!/usr/bin/env python3
"""Upload verified Wear OS screenshots to every existing Play listing locale."""

import base64
import hashlib
import json
import os
import pathlib
import struct
import sys
import urllib.error
import urllib.request

from publish_play import BASE, request

SCREENSHOTS = pathlib.Path("distribution/wearable-screenshots/en-US")
IMAGE_LIMIT = 8


def digests(data):
    return {
        hashlib.sha1(data).hexdigest(),
        hashlib.sha1(data).hexdigest().upper(),
        base64.b64encode(hashlib.sha1(data).digest()).decode(),
        hashlib.sha256(data).hexdigest(),
        hashlib.sha256(data).hexdigest().upper(),
    }


def api(token, method, url, body=None, content_type="application/json"):
    return request(token, method, url, body, content_type)


def upload(token, edit_id, language, content):
    url = (
        f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
        f"/applications/org.librescoot.mobile.unu/edits/{edit_id}"
        f"/listings/{language}/wearScreenshots?uploadType=media"
    )
    return api(token, "POST", url, content, "image/png")


def publish(token, screenshots=SCREENSHOTS):
    files = sorted(screenshots.glob("*.png"))
    if not files or len(files) > IMAGE_LIMIT:
        raise RuntimeError(f"provide 1–{IMAGE_LIMIT} PNG screenshots in {screenshots}")

    payloads = []
    for path in files:
        data = path.read_bytes()
        if len(data) > 8 * 1024 * 1024:
            raise RuntimeError(f"{path} exceeds Play's 8 MB screenshot limit")
        if len(data) < 29 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise RuntimeError(f"{path} is not a valid PNG")
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", data[16:29])
        if color_type not in (0, 2) or bit_depth not in (8, 16):
            raise RuntimeError(f"{path} must be opaque RGB/grayscale PNG without transparency")
        if width != height or not 384 <= width <= 3840:
            raise RuntimeError(f"{path} must be square with sides 384–3840 px")
        payloads.append((path.name, data, digests(data)))

    edit = request(token, "POST", f"{BASE}/edits", b"{}")['id']
    try:
        listings = request(token, "GET", f"{BASE}/edits/{edit}/listings").get("listings", [])
        languages = sorted({item["language"] for item in listings})
        if not languages:
            raise RuntimeError("Play returned no localized store listings")

        # Check every locale before uploading anything; never replace existing images.
        plans = []
        for language in languages:
            response = request(
                token, "GET",
                f"{BASE}/edits/{edit}/listings/{language}/wearScreenshots",
            )
            existing = response.get("images", [])
            hashes = {
                value for item in existing
                for value in (item.get("sha1"), item.get("sha256")) if value
            }
            remaining = [
                (name, data, checksums) for name, data, checksums in payloads
                if not checksums.intersection(hashes)
            ]
            if len(existing) + len(remaining) > IMAGE_LIMIT:
                raise RuntimeError(
                    f"{language} already has {len(existing)} Wear screenshots; "
                    f"adding {len(remaining)} would exceed Play's limit of {IMAGE_LIMIT}. "
                    "No existing images were removed."
                )
            plans.append((language, existing, remaining))

        for language, existing, remaining in plans:
            for name, data, _ in remaining:
                result = upload(token, edit, language, data)
                if not result.get("url"):
                    raise RuntimeError(f"Play did not return an uploaded image URL for {language}/{name}")
                print(f"Uploaded {name} to {language} Wear listing")
            print(f"{language}: {len(existing)} existing, {len(remaining)} uploaded")

        request(token, "POST", f"{BASE}/edits/{edit}:commit")
    except Exception:
        # A failed edit is not committed, so uncommitted image uploads are discarded.
        raise

    verify = request(token, "POST", f"{BASE}/edits", b"{}")['id']
    for language in languages:
        result = request(
            token, "GET",
            f"{BASE}/edits/{verify}/listings/{language}/wearScreenshots",
        )
        images = result.get("images", [])
        hashes = {
            value for image in images
            for value in (image.get("sha1"), image.get("sha256")) if value
        }
        missing = [
            name for name, _, checksums in payloads
            if not checksums.intersection(hashes)
        ]
        if missing:
            raise RuntimeError(f"{language} Wear listing is missing uploaded screenshots: {missing}")
        if len(images) > IMAGE_LIMIT:
            raise RuntimeError(f"{language} Wear listing exceeds Play's screenshot limit")
        print(f"Verified {language}: {len(images)} Wear screenshots")
    print(f"Committed Wear screenshots for {len(languages)} listing locale(s)")


def main():
    token = os.environ["GOOGLE_OAUTH_ACCESS_TOKEN"]
    publish(token)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, urllib.error.URLError) as error:
        print(f"Wear screenshot upload failed: {error}", file=sys.stderr)
        sys.exit(1)
