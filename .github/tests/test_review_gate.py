import copy
import importlib.util
import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError


SPEC = importlib.util.spec_from_file_location(
    "review_gate", Path(__file__).parents[1] / "scripts" / "review_gate.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)

CREATED = "2026-10-01T10:00:00Z"
REVIEWED = "2026-10-02T10:00:00Z"
REPLIED = "2026-10-03T10:00:00Z"
NOW = gate.timestamp("2026-10-10T10:00:00Z")


def pr(number=1):
    return {"number": number, "node_id": f"pr-{number}", "state": "open",
            "user": {"login": "author"}, "created_at": CREATED, "updated_at": CREATED,
            "head": {"sha": "a" * 40}, "base": {"ref": "master"}}


def comment(user, date, identifier=1, body="Comment", **extra):
    return {"id": identifier, "node_id": f"comment-{identifier}", "user": {"login": user},
            "created_at": date, "updated_at": date, "body": body, **extra}


def review(user="writer", state="APPROVED", date=REVIEWED, identifier=1, body=""):
    return {"id": identifier, "node_id": f"review-{identifier}", "user": {"login": user},
            "submitted_at": date, "state": state, "body": body}


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.args = {"pr": pr(), "reviews": [], "comments": [], "inline": [],
                     "timeline": [], "observation": None,
                     "can_write": lambda user: user in {"author", "writer", "writer2"}, "now": NOW}

    def check(self, state, reason=None):
        result = gate.evaluate(**self.args)
        self.assertEqual(result[0], state, result)
        if reason:
            self.assertIn(reason, result[1])

    def test_external_author_can_pass_with_writer_approval(self):
        self.args["pr"]["user"]["login"] = "outsider"
        self.args["reviews"] = [review()]
        self.check("success", "Approved")

    def test_reader_approval_does_not_count(self):
        self.args["pr"]["user"]["login"] = "outsider"
        self.args["reviews"] = [review("reader")]
        self.check("pending", "write access")

    def test_any_latest_writer_change_request_blocks_approval(self):
        self.args["reviews"] = [review(), review("writer2", "CHANGES_REQUESTED", identifier=2)]
        self.check("pending")

    def test_latest_review_replaces_previous_including_comment_and_dismissal(self):
        for state in ["COMMENTED", "DISMISSED", "CHANGES_REQUESTED"]:
            with self.subTest(state=state):
                self.args["pr"]["user"]["login"] = "outsider"
                self.args["reviews"] = [review(state=state, date=REPLIED, identifier=2), review()]
                self.check("pending")

    def test_later_approval_replaces_change_request(self):
        self.args["reviews"] = [review(state="CHANGES_REQUESTED"), review(date=REPLIED, identifier=2)]
        self.check("success", "Approved")

    def test_pending_review_does_not_replace_approval(self):
        pending = review(state="PENDING", date=None, identifier=2)
        self.args["reviews"] = [review(), pending]
        self.check("success", "Approved")

    def test_self_approval_does_not_count(self):
        self.args["reviews"] = [review("author", date=REPLIED)]
        self.args["allow_expiry"] = False
        self.check("pending", "daily")

    def test_author_may_wait_seven_days_without_any_reviews(self):
        self.check("success", "Lack of engagement")

    def test_seven_day_boundary_is_exact(self):
        self.args["now"] = gate.timestamp(CREATED) + gate.WAIT - timedelta(microseconds=1)
        self.check("pending", "Seven quiet days")
        self.args["now"] += timedelta(microseconds=1)
        self.check("success")

    def test_event_cannot_promote_expired_pending_gate(self):
        self.args["allow_expiry"] = False
        self.check("pending", "daily 4am Pacific")

    def test_last_activity_by_anyone_other_than_author_blocks(self):
        self.args["comments"] = [comment("reader", REPLIED)]
        self.check("pending", "most recent")

    def test_lack_of_engagement_can_pass_with_answered_change_request(self):
        self.args["reviews"] = [review(state="CHANGES_REQUESTED", body="Please change this")]
        self.args["comments"] = [comment("author", REPLIED)]
        self.check("success", "Lack of engagement")

    def test_general_response_must_follow_each_writer_comment(self):
        self.args["comments"] = [comment("writer", REVIEWED), comment("author", REPLIED, 2),
                                 comment("writer2", "2026-10-04T10:00:00Z", 3)]
        self.check("pending", "general comment")

    def test_inline_feedback_needs_reply_in_same_thread(self):
        self.args["inline"] = [comment("writer", REVIEWED)]
        self.args["comments"] = [comment("author", REPLIED, 2)]
        self.check("pending", "review thread")
        self.args["inline"].append(comment("author", REPLIED, 3, in_reply_to_id=1))
        self.check("success")

    def test_other_thread_reply_does_not_answer_feedback(self):
        self.args["inline"] = [comment("writer", REVIEWED),
                               comment("author", REPLIED, 2, in_reply_to_id=999)]
        self.check("pending", "review thread")

    def test_drafted_feedback_is_timed_from_publication(self):
        self.args["inline"] = [comment("writer", CREATED, publishedAt=REPLIED),
                               comment("author", REVIEWED, 2, in_reply_to_id=1)]
        self.check("pending", "review thread")

    def test_reviewer_followup_requires_another_author_reply(self):
        self.args["inline"] = [comment("writer", CREATED),
                               comment("author", REVIEWED, 2, in_reply_to_id=1),
                               comment("writer", REPLIED, 3, in_reply_to_id=1)]
        self.check("pending", "review thread")

    def test_empty_author_response_does_not_count(self):
        self.args["comments"] = [comment("writer", REVIEWED), comment("author", REPLIED, 2, body=" ")]
        self.check("pending", "general comment")

    def test_review_summary_and_inline_comment_both_need_responses(self):
        self.args["reviews"] = [review(state="COMMENTED", body="General feedback")]
        self.args["inline"] = [comment("writer", REVIEWED),
                               comment("author", REPLIED, 2, in_reply_to_id=1)]
        self.check("pending", "general comment")
        self.args["comments"] = [comment("author", REPLIED, 3)]
        self.check("success")

    def test_editor_is_last_actor_instead_of_original_author(self):
        edited = comment("author", CREATED, updated_at=REPLIED,
                         lastEditedAt=REPLIED, editor={"login": "reader"})
        self.args["comments"] = [edited]
        self.check("pending", "most recent")

    def test_edit_by_reviewer_requires_fresh_response(self):
        self.args["comments"] = [comment("writer", CREATED, updated_at=REPLIED,
                                        lastEditedAt=REPLIED, editor={"login": "writer"}),
                                 comment("author", REVIEWED, 2)]
        self.check("pending", "general comment")

    def test_maintainer_edit_of_author_reply_is_not_an_author_response(self):
        self.args["comments"] = [comment("writer", REVIEWED),
                                 comment("author", CREATED, 2, updated_at=REPLIED,
                                         lastEditedAt=REPLIED, editor={"login": "writer"})]
        self.check("pending", "general comment")

    def test_editing_reviewers_comment_is_not_an_author_reply(self):
        self.args["comments"] = [comment("writer", CREATED, updated_at=REPLIED,
                                        lastEditedAt=REPLIED, editor={"login": "author"})]
        self.check("pending", "general comment")

    def test_unknown_latest_activity_stays_pending(self):
        self.args["pr"]["updated_at"] = REPLIED
        self.check("pending", "cannot be attributed")

    def test_push_observation_uses_actual_update_time_not_commit_date(self):
        self.args["pr"]["updated_at"] = REPLIED
        self.args["observation"] = {"updated_at": REPLIED, "actor": "author"}
        self.args["timeline"] = [{"event": "committed", "author": {"date": CREATED}}]
        self.args["now"] = NOW - timedelta(seconds=1)
        self.check("pending", "Seven quiet days")
        self.args["now"] = NOW
        self.check("success")

    def test_stale_push_observation_cannot_authorize_newer_activity(self):
        self.args["pr"]["updated_at"] = REPLIED
        self.args["observation"] = {"updated_at": CREATED, "actor": "author"}
        self.check("pending", "cannot be attributed")

    def test_timeline_activity_counts_and_timestamp_ties_are_conservative(self):
        self.args["comments"] = [comment("author", REPLIED)]
        self.args["timeline"] = [{"event": "labeled", "created_at": REPLIED,
                                  "actor": {"login": "reader"}}]
        self.check("pending", "most recent")


class ApiTests(unittest.TestCase):
    def api(self):
        with patch.dict("os.environ", {"GITHUB_REPOSITORY": "RopeWiki/app"}):
            return gate.GitHub()

    def test_all_pages_are_fetched(self):
        api = self.api()
        with patch.object(api, "request", side_effect=[list(range(100)), [100]]) as request:
            self.assertEqual(len(api.pages("/items")), 101)
            self.assertIn("page=2", request.call_args.args[1])

    def test_editor_lookup_preserves_numeric_rest_ids_and_batches(self):
        api = self.api()
        items = [comment("author", CREATED, i) for i in range(101)]
        def response(method, path, body):
            return {"data": {"nodes": [{"id": node_id, "lastEditedAt": None, "editor": None}
                                       for node_id in body["variables"]["ids"]]}}
        with patch.object(api, "request", side_effect=response) as request:
            api.add_editors(items)
            self.assertEqual(request.call_count, 2)
            self.assertEqual(items[-1]["id"], 100)

    def test_permission_roles_and_missing_users(self):
        for role in ["write", "maintain", "admin", "read", "triage", "none"]:
            api = self.api()
            with patch.object(api, "request", return_value={"permission": role}) as request:
                self.assertEqual(api.can_write("person"), role in {"write", "maintain", "admin"})
                api.can_write("person")
                self.assertEqual(request.call_count, 1)
        api = self.api()
        with patch.object(api, "request", side_effect=HTTPError("", 404, "", {}, None)):
            self.assertFalse(api.can_write("missing"))
        with patch.object(api, "request", side_effect=HTTPError("", 403, "", {}, None)):
            with self.assertRaises(HTTPError):
                api.can_write("unknown")

    def test_observations_only_accept_current_trusted_events(self):
        api = self.api()
        current = pr()
        event = {"pull_request": copy.deepcopy(current), "sender": {"login": "author"}}
        with patch.object(api, "pages", return_value=[]), patch.object(api, "request") as request:
            result = api.observation(current, "pull_request_target", event)
            self.assertEqual(result["actor"], "author")
            self.assertEqual(request.call_args.args[2]["conclusion"], "neutral")
            event["pull_request"]["head"]["sha"] = "b" * 40
            self.assertIsNone(api.observation(current, "pull_request_target", event))
            self.assertIsNone(api.observation(current, "workflow_run", event))

    def test_observation_conflicts_and_untrusted_apps_are_conservative(self):
        api = self.api()
        runs = [{"app": {"slug": "github-actions"}, "external_id": "review-gate-activity:1",
                 "output": {"text": json.dumps({"updated_at": CREATED, "actor": actor})}}
                for actor in ["author", "reader"]]
        with patch.object(api, "pages", return_value=runs):
            self.assertEqual(api.observation(pr(), "schedule", {})["actor"], "")
        runs[0]["app"]["slug"] = "untrusted"
        with patch.object(api, "pages", return_value=runs[:1]):
            self.assertIsNone(api.observation(pr(), "schedule", {}))


class FakeApi:
    prefix = "/repos/RopeWiki/app"
    def __init__(self):
        self.prs = [pr()]
        self.statuses = []
        self.previous = []
        self.reviews = []
        self.error = False
        self.changed = False
        self.reads = 0

    def pages(self, path, **params):
        if path.endswith("/statuses"):
            return self.previous
        if path == self.prefix + "/pulls":
            return copy.deepcopy(self.prs)
        if path.endswith("/reviews"):
            if self.error:
                raise RuntimeError("API unavailable")
            return self.reviews
        return []

    def request(self, method, path):
        self.reads += 1
        result = copy.deepcopy(next(p for p in self.prs if path.endswith(f"/{p['number']}")))
        if self.changed and self.reads % 2 == 0:
            result["updated_at"] = REPLIED
        return result

    def observation(self, *args):
        return None

    def add_editors(self, *args):
        pass

    def can_write(self, user):
        return user in {"author", "writer"}

    def status(self, sha, state, reason, url):
        self.statuses.append((sha, state, reason))


class RunnerTests(unittest.TestCase):
    def run_gate(self, api, event="schedule"):
        with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
            return gate.run(api, event, {}, NOW, "https://example.com/run")

    def test_only_daily_or_manual_run_promotes_pending_elapsed_gate(self):
        for event, expected in [("schedule", "success"), ("workflow_dispatch", "success"),
                                ("workflow_run", "pending"), ("pull_request_target", "pending")]:
            api = FakeApi()
            self.assertFalse(self.run_gate(api, event))
            self.assertEqual(api.statuses[-1][1], expected)

    def test_events_preserve_eligible_pass_and_approve_immediately(self):
        api = FakeApi()
        api.previous = [{"context": gate.CONTEXT, "state": "success"}]
        self.run_gate(api, "issue_comment")
        self.assertEqual(api.statuses[-1][1], "success")
        api.previous = []
        api.reviews = [review()]
        self.run_gate(api, "workflow_run")
        self.assertEqual(api.statuses[-1][1], "success")

    def test_api_failure_revokes_old_success_and_reports_failed_workflow(self):
        api = FakeApi()
        api.previous = [{"context": gate.CONTEXT, "state": "success"}]
        api.error = True
        self.assertTrue(self.run_gate(api))
        self.assertTrue(all(s[1] == "pending" for s in api.statuses))

    def test_mid_evaluation_update_never_posts_success(self):
        api = FakeApi()
        api.changed = True
        self.assertTrue(self.run_gate(api))
        self.assertEqual(api.statuses[-1][1], "pending")

    def test_shared_sha_requires_every_pr_to_qualify(self):
        api = FakeApi()
        other = pr(2)
        other["user"]["login"] = "outsider"
        api.prs.append(other)
        self.run_gate(api)
        self.assertEqual(api.statuses[-1][1], "pending")
        self.assertEqual(len(api.statuses), 2)


if __name__ == "__main__":
    unittest.main()
