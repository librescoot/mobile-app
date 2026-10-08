import base64
import hashlib
import pathlib
import plistlib
import sys
import unittest
from unittest.mock import Mock, patch

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / ".github" / "scripts"
sys.path.insert(0, str(SCRIPTS))
import configure_watch_signing as signing

CERT = b"CI distribution certificate"
FINGERPRINT = hashlib.sha1(CERT).hexdigest().upper()


class WatchSigningTests(unittest.TestCase):
    def test_registration_is_idempotent(self):
        api = Mock(side_effect=lambda method, path, body=None: {"data": (
            [{"id": "bundle"}] if path.startswith("/bundleIds?") else
            [{"attributes": {"capabilityType": "APP_GROUPS"}}]
        )})
        signing.register(api)
        self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    def test_registration_creates_only_watch_ids_and_group_capabilities(self):
        def respond(method, path, body=None):
            if method == "GET":
                return {"data": []}
            return {"data": {"id": "created-bundle"}}
        api = Mock(side_effect=respond)
        signing.register(api)
        writes = [call.args for call in api.call_args_list if call.args[0] == "POST"]
        ids = [body["data"]["attributes"]["identifier"] for _, path, body in writes if path == "/bundleIds"]
        self.assertEqual(ids, list(signing.TARGETS))
        capabilities = [body["data"]["attributes"]["capabilityType"] for _, path, body in writes if path == "/bundleIdCapabilities"]
        self.assertEqual(capabilities, ["APP_GROUPS", "APP_GROUPS"])

    def api(self, existing=False):
        def respond(method, path, body=None):
            if path.startswith("/profiles?") and "Librescoot+App+Store+CI" in path:
                return {"data": [{"id": "phone-profile"}]}
            if path == "/profiles/phone-profile/certificates":
                return {"data": [{"id": "ci-cert", "attributes": {
                    "certificateContent": base64.b64encode(CERT).decode(),
                }}]}
            if path.startswith("/bundleIds?"):
                return {"data": [{"id": "watch-bundle"}]}
            if path.startswith("/profiles?"):
                return {"data": [{"id": "existing-profile"}] if existing else []}
            if method == "POST" and path == "/profiles":
                self.assertEqual(body["data"]["relationships"]["certificates"]["data"], [{"type": "certificates", "id": "ci-cert"}])
                return {"data": {"id": "created-profile"}}
            if method == "DELETE":
                return {}
            raise AssertionError((method, path, body))
        return Mock(side_effect=respond)

    @patch("verify_signing_profiles.keychain_fingerprints", return_value={FINGERPRINT})
    @patch.object(signing, "validate_profile")
    def test_profiles_reuse_existing_certificate(self, validate, fingerprints):
        api = self.api()
        signing.profiles(api)
        self.assertEqual(validate.call_count, 2)
        self.assertFalse(any(call.args[0] == "DELETE" for call in api.call_args_list))

    @patch("verify_signing_profiles.keychain_fingerprints", return_value={FINGERPRINT})
    @patch.object(signing, "validate_profile", side_effect=RuntimeError("missing group"))
    def test_discards_only_invalid_profile_created_by_this_run(self, validate, fingerprints):
        api = self.api()
        with self.assertRaisesRegex(RuntimeError, "missing group"):
            signing.profiles(api)
        api.assert_any_call("DELETE", "/profiles/created-profile")

    @patch("verify_signing_profiles.keychain_fingerprints", return_value={FINGERPRINT})
    @patch.object(signing, "validate_profile", side_effect=RuntimeError("missing group"))
    def test_never_deletes_preexisting_profile(self, validate, fingerprints):
        api = self.api(existing=True)
        with self.assertRaisesRegex(RuntimeError, "missing group"):
            signing.profiles(api)
        self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    @patch("verify_signing_profiles.keychain_fingerprints", return_value={"different"})
    def test_certificate_mismatch_prevents_writes(self, fingerprints):
        api = self.api()
        with self.assertRaisesRegex(RuntimeError, "matching the imported CI identity"):
            signing.profiles(api)
        self.assertTrue(all(call.args[0] == "GET" for call in api.call_args_list))

    @patch.object(signing.subprocess, "run")
    def test_profile_entitlements_and_certificate_are_checked(self, run):
        identifier = next(iter(signing.TARGETS))
        decoded = {"Entitlements": {
            "application-identifier": "TEAM." + identifier,
            "com.apple.security.application-groups": [signing.GROUP],
            "get-task-allow": False,
        }, "DeveloperCertificates": [CERT]}
        profile = {"attributes": {"profileContent": "", "profileState": "ACTIVE"}}
        run.return_value.stdout = plistlib.dumps(decoded)
        signing.validate_profile(profile, identifier, FINGERPRINT)
        decoded["Entitlements"]["com.apple.security.application-groups"] = []
        run.return_value.stdout = plistlib.dumps(decoded)
        with self.assertRaisesRegex(RuntimeError, "developer portal"):
            signing.validate_profile(profile, identifier, FINGERPRINT)


if __name__ == "__main__":
    unittest.main()
