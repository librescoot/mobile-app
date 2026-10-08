#!/usr/bin/env python3
"""Explicitly provision watch bundle IDs or profiles without rotating certificates."""

import argparse
import base64
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
import urllib.parse

from testflight_notes import API, mint_token, request

GROUP = "group.org.librescoot.mobile.unu.watch"
TARGETS = {
    "org.librescoot.mobile.unu.watch": ("Librescoot Watch", "Librescoot Watch App Store CI"),
    "org.librescoot.mobile.unu.watch.widget": (
        "Librescoot Watch Widget", "Librescoot Watch Widget App Store CI"
    ),
}


def listing(api, resource, **filters):
    query = urllib.parse.urlencode({f"filter[{key}]": value for key, value in filters.items()})
    return api("GET", f"/{resource}?{query}&limit=200")["data"]


def bundle(api, identifier):
    matches = listing(api, "bundleIds", identifier=identifier)
    if len(matches) > 1:
        raise RuntimeError(f"ambiguous bundle ID: {identifier}")
    return matches[0] if matches else None


def register(api):
    for identifier, (name, _) in TARGETS.items():
        item = bundle(api, identifier)
        if item is None:
            item = api("POST", "/bundleIds", {"data": {
                "type": "bundleIds",
                "attributes": {"name": name, "identifier": identifier, "platform": "IOS"},
            }})["data"]
        capabilities = api("GET", f"/bundleIds/{item['id']}/bundleIdCapabilities")["data"]
        if not any(cap["attributes"]["capabilityType"] == "APP_GROUPS" for cap in capabilities):
            api("POST", "/bundleIdCapabilities", {"data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": "APP_GROUPS"},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": item["id"]}}},
            }})
        print(f"Registered {identifier} with App Groups capability")
    print(f"In Certificates, Identifiers & Profiles, associate {GROUP} with BOTH watch IDs.")
    print("App Group creation and association require the Apple developer portal; then run the profiles phase.")


def validate_profile(profile, identifier, certificate_fingerprint):
    result = subprocess.run(
        ["security", "cms", "-D"],
        input=base64.b64decode(profile["attributes"]["profileContent"]),
        capture_output=True, check=True,
    )
    decoded = plistlib.loads(result.stdout)
    entitlements = decoded.get("Entitlements", {})
    if entitlements.get("application-identifier", "").split(".", 1)[-1] != identifier:
        raise RuntimeError(f"profile has the wrong bundle ID for {identifier}")
    if GROUP not in entitlements.get("com.apple.security.application-groups", []):
        raise RuntimeError(f"associate {GROUP} with {identifier} in the developer portal first")
    if entitlements.get("get-task-allow") is True:
        raise RuntimeError("expected a distribution profile")
    fingerprints = {hashlib.sha1(cert).hexdigest().upper() for cert in decoded.get("DeveloperCertificates", [])}
    if certificate_fingerprint not in fingerprints:
        raise RuntimeError("profile does not contain the imported CI certificate")
    if profile["attributes"].get("profileState") != "ACTIVE":
        raise RuntimeError("profile is not active")


def profiles(api):
    from verify_signing_profiles import keychain_fingerprints

    imported = keychain_fingerprints(None, "Apple Distribution")
    phone_profiles = listing(api, "profiles", name="Librescoot App Store CI", profileType="IOS_APP_STORE", profileState="ACTIVE")
    if len(phone_profiles) != 1:
        raise RuntimeError("expected exactly one active phone CI profile")
    certificates = api("GET", f"/profiles/{phone_profiles[0]['id']}/certificates")["data"]
    matches = [(cert, hashlib.sha1(base64.b64decode(cert["attributes"]["certificateContent"])).hexdigest().upper()) for cert in certificates]
    matches = [(cert, fingerprint) for cert, fingerprint in matches if fingerprint in imported]
    if len(matches) != 1:
        raise RuntimeError("expected exactly one phone profile certificate matching the imported CI identity")
    certificate, fingerprint = matches[0]
    for identifier, (_, name) in TARGETS.items():
        item = bundle(api, identifier)
        if item is None:
            raise RuntimeError(f"register {identifier} first")
        existing = listing(api, "profiles", name=name, profileType="IOS_APP_STORE")
        if len(existing) > 1:
            raise RuntimeError(f"ambiguous profile name: {name}")
        created = not existing
        profile = existing[0] if existing else api("POST", "/profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": item["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]},
            },
        }})["data"]
        try:
            validate_profile(profile, identifier, fingerprint)
        except Exception:
            # Never delete an existing profile; discard only an invalid profile created here.
            if created:
                api("DELETE", f"/profiles/{profile['id']}")
            raise
        print(f"Validated {identifier}: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["register", "profiles"], required=True)
    parser.add_argument("--apply", action="store_true", help="authorize account resource creation")
    args = parser.parse_args()
    if not args.apply:
        parser.error("account changes require --apply")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".p8") as key:
        key.write(os.environ["APPSTORE_PRIVATE_KEY"])
        key.flush()
        token = mint_token(key.name, os.environ["APPSTORE_KEY_ID"], os.environ["APPSTORE_ISSUER_ID"])
    def api(method, path, body=None):
        return request(token, method, API + path, json.dumps(body).encode() if body is not None else None)
    (register if args.phase == "register" else profiles)(api)


if __name__ == "__main__":
    main()
