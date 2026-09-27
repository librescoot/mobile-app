import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".github" / "scripts"))
import testflight_notes as notes


class ExternalDistributionTests(unittest.TestCase):
    def group_response(self, name="External Testing", internal=False):
        return {"data": [{"id": "group-1", "attributes": {
            "name": name, "isInternalGroup": internal,
        }}]}

    def detail_response(self, state="READY_FOR_BETA_SUBMISSION", notify=False):
        return {"data": {"id": "detail-1", "attributes": {
            "externalBuildState": state, "autoNotifyEnabled": notify,
        }}}

    def test_resolves_only_the_exact_external_group(self):
        with patch.object(notes, "request", return_value=self.group_response()) as request:
            self.assertEqual(notes.resolve_external_group("token", "app-1", "External Testing"),
                             ("group-1", "External Testing"))
            url = request.call_args.args[2]
            self.assertIn("filter%5Bapp%5D=app-1", url)
        with patch.object(notes, "request", return_value=self.group_response(internal=True)):
            with self.assertRaisesRegex(RuntimeError, "available external groups: \\[\\]"):
                notes.resolve_external_group("token", "app-1", "External Testing")

    def test_uses_sole_external_group_when_named_differently(self):
        with patch.object(notes, "request", return_value=self.group_response(name="Beta testers")):
            self.assertEqual(notes.resolve_external_group("token", "app-1", "External Testing"),
                             ("group-1", "Beta testers"))

    def test_refuses_to_guess_among_multiple_external_groups(self):
        data = {"data": [
            {"id": "group-1", "attributes": {"name": "Early access", "isInternalGroup": False}},
            {"id": "group-2", "attributes": {"name": "Preview", "isInternalGroup": False}},
        ]}
        with patch.object(notes, "request", return_value=data):
            with self.assertRaisesRegex(RuntimeError, "Early access.*Preview"):
                notes.resolve_external_group("token", "app-1", "External Testing")

    def test_searches_paginated_group_membership(self):
        with patch.object(notes, "request", side_effect=[
            {"data": [{"id": "other"}], "links": {"next": "https://next-page"}},
            {"data": [{"id": "build-1"}]},
        ]) as request:
            self.assertTrue(notes.group_has_build("token", "group-1", "build-1"))
            self.assertEqual(request.call_args.args[2], "https://next-page")

    def test_assigns_notifies_and_submits_when_unreviewed(self):
        membership = iter([False, True])
        calls = []

        def api(token, method, url, body=None):
            calls.append((method, url, json.loads(body) if body else None))
            if url.endswith("/buildBetaDetail"):
                return self.detail_response()
            if url.endswith("/relationships/builds") and method == "POST":
                return {}
            if "/relationships/builds?" in url:
                return {"data": [{"id": "build-1"}]} if next(membership) else {"data": []}
            if method == "PATCH":
                return self.detail_response(notify=True)
            if "/betaAppReviewSubmissions?" in url:
                return {"data": []}
            if method == "POST" and url.endswith("/betaAppReviewSubmissions"):
                return {"data": {"attributes": {"betaReviewState": "WAITING_FOR_REVIEW"}}}
            return self.group_response()

        with patch.object(notes, "request", side_effect=api):
            notes.publish_external("token", "build-1", "app-1", "External Testing", False)
        methods = [(method, url.split("?")[0]) for method, url, _ in calls]
        self.assertLess(
            methods.index(("POST", f"{notes.API}/betaGroups/group-1/relationships/builds")),
            methods.index(("POST", f"{notes.API}/betaAppReviewSubmissions")),
        )
        self.assertIn(("PATCH", f"{notes.API}/buildBetaDetails/detail-1"), methods)
        link = next(body for method, url, body in calls if method == "POST" and url.endswith("/relationships/builds"))
        self.assertEqual(link, {"data": [{"type": "builds", "id": "build-1"}]})
        submit = next(body for method, url, body in calls if method == "POST" and url.endswith("/betaAppReviewSubmissions"))
        self.assertEqual(submit["data"]["relationships"]["build"]["data"],
                         {"type": "builds", "id": "build-1"})

    def test_rerun_preserves_existing_membership_and_review(self):
        calls = []

        def api(token, method, url, body=None):
            calls.append((method, url))
            if url.endswith("/buildBetaDetail"):
                return self.detail_response(notify=True)
            if "/relationships/builds?" in url:
                return {"data": [{"id": "build-1"}]}
            if "/betaAppReviewSubmissions?" in url:
                return {"data": [{"attributes": {"betaReviewState": "APPROVED"}}]}
            return self.group_response()

        with patch.object(notes, "request", side_effect=api):
            notes.publish_external("token", "build-1", "app-1", "External Testing", False)
        self.assertEqual([method for method, _ in calls if method != "GET"], [])

    def test_waits_for_external_processing(self):
        with patch.object(notes, "request", side_effect=[
            self.detail_response(state="PROCESSING"), self.detail_response(),
        ]) as request, patch.object(notes.time, "sleep") as sleep:
            detail = notes.await_external_detail("token", "build-1")
            self.assertEqual(detail["attributes"]["externalBuildState"],
                             "READY_FOR_BETA_SUBMISSION")
            self.assertEqual(request.call_count, 2)
            sleep.assert_called_once_with(15)

    def test_fails_if_group_link_did_not_persist(self):
        with patch.object(notes, "request", side_effect=[
            self.group_response(), self.detail_response(notify=True),
            {"data": []}, {}, {"data": []},
        ]) as request:
            with self.assertRaisesRegex(RuntimeError, "was not assigned"):
                notes.publish_external("token", "build-1", "app-1", "External Testing", False)
            self.assertEqual(request.call_count, 5)

    def test_fails_on_blocked_build_and_rejected_review(self):
        for state in ("MISSING_EXPORT_COMPLIANCE", "BETA_REJECTED", "EXPIRED", "NOT_APPLICABLE"):
            with self.subTest(state=state), patch.object(notes, "request", side_effect=[
                self.group_response(), self.detail_response(state=state),
            ]) as request:
                with self.assertRaisesRegex(RuntimeError, state):
                    notes.publish_external("token", "build-1", "app-1", "External Testing", False)
                self.assertEqual(request.call_count, 2)

        with patch.object(notes, "request", side_effect=[
            self.group_response(), self.detail_response(notify=True),
            {"data": [{"id": "build-1"}]}, {"data": [{"id": "build-1"}]},
            {"data": [{"attributes": {"betaReviewState": "REJECTED"}}]},
        ]):
            with self.assertRaisesRegex(RuntimeError, "rejected by TestFlight"):
                notes.publish_external("token", "build-1", "app-1", "External Testing", False)

    def test_dry_run_does_not_change_distribution(self):
        with patch.object(notes, "request", return_value=self.group_response()) as request:
            notes.publish_external("token", "build-1", "app-1", "External Testing", True)
            self.assertEqual(request.call_count, 1)

    def test_external_group_is_opt_in_and_uses_fresh_token(self):
        args = ["testflight_notes.py", "--build-number", "123", "--notes-file", "notes.txt",
                "--issuer-id", "issuer", "--key-id", "key", "--private-key", "key.p8"]
        with patch.object(notes.sys, "argv", args), \
             patch.object(notes, "collect_notes", return_value={"en-US": "Test"}), \
             patch.object(notes, "mint_token", side_effect=["notes-token", "notes-token", "external-token"]) as mint, \
             patch.object(notes, "resolve_app", return_value="app-1"), \
             patch.object(notes, "await_build", return_value="build-1"), \
             patch.object(notes, "write_notes"), \
             patch.object(notes, "publish_external") as external:
            notes.main()
            self.assertEqual(mint.call_count, 1)
            external.assert_not_called()
            notes.sys.argv = args + ["--external-group", "External Testing"]
            notes.main()
            self.assertEqual(mint.call_count, 3)
            external.assert_called_once_with("external-token", "build-1", "app-1",
                                             "External Testing", False)


if __name__ == "__main__":
    unittest.main()
