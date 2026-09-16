#!/usr/bin/env python3
"""Fail early when the pinned provisioning profiles no longer match the imported
distribution certificate.

The profiles are selected by name in ExportOptions.plist, so a rotated or
re-exported certificate leaves them pointing at a certificate that no longer
exists. Xcode's own error for that arrives late, after the archive has already
run, and reads as a signing failure rather than a stale profile.
"""

import argparse
import base64
import hashlib
import os
import plistlib
import re
import subprocess
import sys

DEFAULT_PROFILES_DIR = "~/Library/MobileDevice/Provisioning Profiles"
CERT_PATTERN = "Apple Distribution"
PEM = re.compile(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", re.S)


def resolve_keychain(keychain):
    """Return the keychain arguments for `security`.

    Nothing is passed by default, so `security` searches the user's keychain
    search list. That is what the certificate import step configures, and it is
    the only reliable route: `security` resolves a keychain argument as a file
    path, while the import step creates `signing_temp.keychain-db` and puts the
    bare name `signing_temp.keychain` in the search list. Passing that name as an
    argument silently matches no certificate instead of failing, which would look
    exactly like a certificate import that did not take effect.
    """
    if not keychain:
        return []
    candidates = [keychain, f"{keychain}.keychain", f"{keychain}-db", f"{keychain}.keychain-db"]
    for candidate in candidates:
        if os.path.exists(os.path.expanduser(candidate)):
            return [os.path.expanduser(candidate)]
    raise RuntimeError(
        f"no keychain file at {keychain!r} or any of "
        f"{', '.join(repr(c) for c in candidates[1:])}; omit --keychain to search the "
        "user keychain search list instead"
    )


def keychain_fingerprints(keychain, pattern):
    result = subprocess.run(
        [
            "security",
            "find-certificate",
            "-a",
            "-p",
            "-c",
            pattern,
            *resolve_keychain(keychain),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"could not read {pattern!r} certificates from keychain {keychain!r}: "
            f"{result.stderr.strip()}"
        )
    fingerprints = set()
    for pem in PEM.findall(result.stdout):
        der = base64.b64decode("".join(pem.splitlines()[1:-1]))
        fingerprints.add(hashlib.sha1(der).hexdigest().upper())
    return fingerprints


def read_profile(path):
    result = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
    if result.returncode != 0:
        return None
    try:
        return plistlib.loads(result.stdout)
    except Exception:
        return None


def load_profiles(profiles_dir):
    profiles = []
    if not os.path.isdir(profiles_dir):
        raise RuntimeError(f"no provisioning profiles directory at {profiles_dir!r}")
    for name in sorted(os.listdir(profiles_dir)):
        if not name.endswith(".mobileprovision"):
            continue
        profile = read_profile(os.path.join(profiles_dir, name))
        if profile is not None:
            profiles.append(profile)
    return profiles


def fingerprint(profile):
    """SHA-1 fingerprints of the certificates embedded in a profile."""
    return {
        hashlib.sha1(cert).hexdigest().upper()
        for cert in profile.get("DeveloperCertificates", [])
    }


def check(bundle_id, profile_name, profiles, fingerprints):
    problems = []
    candidates = [p for p in profiles if p.get("Name") == profile_name]
    if not candidates:
        available = sorted({p.get("Name", "?") for p in profiles})
        return [
            f"no downloaded profile is named {profile_name!r}; available: "
            + (", ".join(repr(n) for n in available) if available else "(none)")
        ]

    for profile in candidates:
        identifier = profile.get("Entitlements", {}).get("application-identifier", "")
        if identifier and not identifier.split(".", 1)[-1] == bundle_id:
            problems.append(
                f"{profile_name!r} is for {identifier!r}, not bundle id {bundle_id!r}"
            )
        if profile.get("Entitlements", {}).get("get-task-allow") is True:
            problems.append(
                f"{profile_name!r} is a development profile "
                "(get-task-allow), not a distribution profile"
            )

        included = fingerprint(profile)
        if not (included & fingerprints):
            problems.append(
                f"{profile_name!r} contains no certificate that was imported "
                f"(profile has {sorted(included) or ['none']}, "
                f"imported {sorted(fingerprints)})"
            )

    if problems:
        return problems
    return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--keychain",
        help="specific keychain to read; defaults to the user keychain search list",
    )
    parser.add_argument("--profiles-dir", default=DEFAULT_PROFILES_DIR)
    parser.add_argument("--cert-pattern", default=CERT_PATTERN)
    parser.add_argument(
        "--require",
        action="append",
        required=True,
        metavar="BUNDLE_ID=PROFILE_NAME",
        help="a pinned profile that must exist and include the imported certificate",
    )
    args = parser.parse_args()

    requirements = []
    for item in args.require:
        bundle_id, _, profile_name = item.partition("=")
        if not bundle_id or not profile_name:
            parser.error(f"--require expects BUNDLE_ID=PROFILE_NAME, got {item!r}")
        requirements.append((bundle_id, profile_name))

    fingerprints = keychain_fingerprints(args.keychain, args.cert_pattern)
    if not fingerprints:
        raise RuntimeError(
            f"no {args.cert_pattern!r} certificate found in "
            f"{args.keychain or 'the keychain search list'}; "
            "the signing certificate import did not take effect"
        )
    print(f"imported {args.cert_pattern!r} certificate(s): {sorted(fingerprints)}")

    profiles = load_profiles(os.path.expanduser(args.profiles_dir))
    print(f"downloaded {len(profiles)} provisioning profile(s)")

    failures = []
    for bundle_id, profile_name in requirements:
        problems = check(bundle_id, profile_name, profiles, fingerprints)
        if problems:
            failures.extend(f"{bundle_id}: {problem}" for problem in problems)
        else:
            print(f"{bundle_id}: {profile_name!r} is valid for this certificate")

    if failures:
        for line in failures:
            print(f"signing check failed: {line}", file=sys.stderr)
        print(
            "Reissue the App Store provisioning profiles for this certificate, "
            "or update the pinned names in ExportOptions.plist and project.pbxproj.",
            file=sys.stderr,
        )
        sys.exit(1)
    print("signing profiles match the imported distribution certificate")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        print(f"signing check failed: {error}", file=sys.stderr)
        sys.exit(1)
