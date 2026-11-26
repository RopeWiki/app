"""Publish the CONTRIBUTING.md gate using only trusted code and GitHub metadata."""

import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


CONTEXT = "review-gate"
BASE = "master"
WAIT = timedelta(days=7)


def timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def login(user):
    return (user or {}).get("login", "").lower()


def content_time(item):
    return max(timestamp(item[key]) for key in
               ("created_at", "submitted_at", "updated_at", "lastEditedAt", "publishedAt") if item.get(key))


def content_activity(item):
    """GitHub editors, rather than original authors, own subsequent edits."""
    actor = login(item.get("user"))
    if item.get("lastEditedAt"):
        actor = login(item.get("editor"))
    elif item.get("updated_at") and item.get("created_at") != item["updated_at"]:
        actor = ""  # Never attribute an unidentified edit to the original author.
    return content_time(item), actor


def evaluate(pr, reviews, comments, inline, timeline, observation, can_write,
             now, allow_expiry=True):
    """Return success/pending and a human-readable explanation of the policy."""
    author = login(pr["user"])
    submitted = [r for r in reviews if r.get("submitted_at") and r["state"] != "PENDING"]
    latest = {}
    for review in sorted(submitted, key=lambda r: (timestamp(r["submitted_at"]), r["id"])):
        reviewer = login(review.get("user"))
        if reviewer != author and can_write(reviewer):
            latest[reviewer] = review["state"]
    if "APPROVED" in latest.values() and "CHANGES_REQUESTED" not in latest.values():
        return "success", "Approved by a writer; no writer's latest review requests changes"

    if not can_write(author):
        return "pending", "Waiting for approval; the author does not have write access"

    # A general author response covers earlier general comments/review summaries.
    general = [*comments, *submitted]
    author_responses = [content_time(c) for c in general
                        if login(c.get("user")) == author and content_activity(c)[1] == author
                        and c.get("body", "").strip()]
    for comment in general:
        reviewer = login(comment.get("user"))
        if reviewer != author and can_write(reviewer) and comment.get("body", "").strip():
            if not any(reply > content_time(comment) for reply in author_responses):
                return "pending", "Waiting for an author response to a writer's general comment"

    # REST review replies point to the root comment, including replies to replies.
    threads = defaultdict(list)
    for comment in inline:
        threads[comment.get("in_reply_to_id", comment["id"])].append(comment)
    for thread in threads.values():
        replies = [content_time(c) for c in thread
                   if login(c.get("user")) == author and content_activity(c)[1] == author
                   and c.get("body", "").strip()]
        for comment in thread:
            reviewer = login(comment.get("user"))
            if reviewer != author and can_write(reviewer) and comment.get("body", "").strip():
                if not any(reply > content_time(comment) for reply in replies):
                    return "pending", "Waiting for an author reply in a writer's review thread"

    activity = [(timestamp(pr["created_at"]), author)]
    activity.extend(content_activity(c) for c in [*general, *inline])
    if pr.get("lastEditedAt"):
        activity.append((timestamp(pr["lastEditedAt"]), login(pr.get("editor"))))
    for event in timeline:
        # Commit dates are user-controlled and do not tell us who pushed or when.
        # Reviews and comments are already included with their edit timestamps.
        if event.get("created_at") and event["event"] not in {"committed", "reviewed", "commented"}:
            activity.append((timestamp(event["created_at"]), login(event.get("actor"))))
    if observation and observation.get("updated_at") == pr["updated_at"]:
        activity.append((timestamp(observation["updated_at"]), observation["actor"]))
    latest_time = max(time for time, _ in activity)
    # Metadata changes and pushes may not have historical actor information. An
    # observation from pull_request_target supplies it. Otherwise stay pending.
    if timestamp(pr["updated_at"]) > latest_time:
        return "pending", "Latest activity cannot be attributed; the author can leave a comment"
    if any(actor != author for time, actor in activity if time == latest_time):
        return "pending", "Waiting for the author to be the most recent participant"
    eligible_at = latest_time + WAIT
    if now < eligible_at:
        return "pending", f"Seven quiet days elapse at {eligible_at.isoformat()}"
    if not allow_expiry:
        return "pending", "Waiting for the daily 4am Pacific seven-day evaluation"
    return "success", "Lack of engagement: author has write access, replied, and waited seven days"


class GitHub:
    def __init__(self):
        self.root = os.environ.get("GITHUB_API_URL", "https://api.github.com")
        self.repo = os.environ["GITHUB_REPOSITORY"]
        self.prefix = f"/repos/{self.repo}"
        self.permissions = {}

    def request(self, method, path, body=None):
        request = Request(self.root + path, method=method,
                          data=json.dumps(body).encode() if body is not None else None,
                          headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}",
                                   "Accept": "application/vnd.github+json",
                                   "Content-Type": "application/json",
                                   "X-GitHub-Api-Version": "2022-11-28"})
        with urlopen(request, timeout=45) as response:
            return json.load(response)

    def pages(self, path, key=None, **params):
        items = []
        page = 1
        while True:
            data = self.request("GET", path + "?" + urlencode(dict(params, per_page=100, page=page)))
            batch = data[key] if key else data
            items.extend(batch)
            if len(batch) < 100:
                return items
            page += 1

    def can_write(self, user):
        if not user:
            return False
        if user not in self.permissions:
            try:
                data = self.request("GET", self.prefix + f"/collaborators/{quote(user)}/permission")
                self.permissions[user] = data["permission"] in {"write", "maintain", "admin"}
            except HTTPError as error:
                if error.code != 404:
                    raise
                self.permissions[user] = False
        return self.permissions[user]

    def add_editors(self, items):
        # All nodes and nested collections are paginated. nodes() is limited to 100.
        by_id = {item["node_id"]: item for item in items}
        ids = list(by_id)
        for offset in range(0, len(ids), 100):
            data = self.request("POST", "/graphql", {
                "query": """query($ids: [ID!]!) { nodes(ids: $ids) {
                  id
                  ... on PullRequest { lastEditedAt editor { login } }
                  ... on IssueComment { lastEditedAt editor { login } }
                  ... on PullRequestReview { lastEditedAt publishedAt editor { login } }
                  ... on PullRequestReviewComment { lastEditedAt publishedAt editor { login } }
                } }""",
                "variables": {"ids": ids[offset:offset + 100]},
            })
            if data.get("errors") or any(node is None for node in data["data"]["nodes"]):
                raise RuntimeError("Could not read all PR activity editors")
            for node in data["data"]["nodes"]:
                item = by_id[node.pop("id")]
                item.update(node)

    def observation(self, pr, event_name, event):
        """Keep push/metadata actors in a neutral check, separate from the gate.

        This also prevents backdated commits from bypassing the quiet period.
        Stale queued events must never describe a newer revision or update.
        """
        name = f"Review gate activity #{pr['number']}"
        path = self.prefix + f"/commits/{pr['head']['sha']}/check-runs"
        runs = self.pages(path, key="check_runs", check_name=name, filter="all")
        observed = []
        for run in runs:
            if (run.get("app", {}).get("slug") == "github-actions" and
                    run.get("external_id") == f"review-gate-activity:{pr['number']}"):
                record = json.loads(run["output"]["text"])
                if record.get("updated_at") == pr["updated_at"]:
                    observed.append(record)
        source = (event.get("pull_request") if event_name == "pull_request_target" else
                  event.get("issue") if event_name == "issue_comment" else None)
        if (source and source["number"] == pr["number"] and
                source["updated_at"] == pr["updated_at"] and
                (event_name != "pull_request_target" or source["head"]["sha"] == pr["head"]["sha"])):
            record = {"updated_at": source["updated_at"], "actor": login(event.get("sender"))}
            if record not in observed:
                self.request("POST", self.prefix + "/check-runs", {
                    "name": name, "head_sha": pr["head"]["sha"], "status": "completed",
                    "conclusion": "neutral", "external_id": f"review-gate-activity:{pr['number']}",
                    "output": {"title": "Last observed PR activity",
                               "summary": f"{record['updated_at']} by {record['actor'] or 'unknown'}",
                               "text": json.dumps(record)},
                })
                observed.append(record)
        if not observed:
            return None
        # GitHub timestamps have one-second precision. Conflicting observations
        # at the same timestamp cannot establish that the author acted last.
        actors = {record["actor"] for record in observed}
        return {"updated_at": pr["updated_at"], "actor": actors.pop() if len(actors) == 1 else ""}

    def status(self, sha, state, reason, url):
        self.request("POST", self.prefix + f"/statuses/{sha}", {
            "context": CONTEXT, "state": state, "description": reason[:140], "target_url": url,
        })


def run(api, event_name, event, now, run_url):
    # A status belongs to a commit, not a PR. Require *all* PRs sharing a head to
    # qualify so an approval on one PR cannot authorize another PR with that SHA.
    groups = defaultdict(list)
    for pr in api.pages(api.prefix + "/pulls", state="open", base=BASE):
        groups[pr["head"]["sha"]].append(pr)
    failed = False
    for sha, candidates in groups.items():
        try:
            previous = api.pages(api.prefix + f"/commits/{sha}/statuses")
        except Exception:
            api.status(sha, "pending", "Could not read previous gate status; see workflow logs", run_url)
            raise
        previous = next((s for s in previous if s["context"] == CONTEXT), None)
        # Only scheduled/manual runs promote a pending seven-day gate. Event
        # runs still revoke eligibility immediately and preserve a valid pass.
        allow_expiry = event_name in {"schedule", "workflow_dispatch"} or bool(
            previous and previous["state"] == "success")
        api.status(sha, "pending", "Reevaluating contribution policy", run_url)
        results = []
        for candidate in candidates:
            number = candidate["number"]
            path = api.prefix + f"/pulls/{number}"
            try:
                pr = api.request("GET", path)
                if pr["state"] != "open" or pr["base"]["ref"] != BASE or pr["head"]["sha"] != sha:
                    raise RuntimeError("PR changed while evaluating; rerun the gate")
                observation = api.observation(pr, event_name, event)
                reviews = api.pages(path + "/reviews")
                comments = api.pages(api.prefix + f"/issues/{number}/comments")
                inline = api.pages(path + "/comments")
                timeline = api.pages(api.prefix + f"/issues/{number}/timeline")
                api.add_editors([pr, *comments, *inline, *[r for r in reviews if r.get("submitted_at")]])
                result = evaluate(pr, reviews, comments, inline, timeline, observation,
                                  api.can_write, now, allow_expiry)
                current = api.request("GET", path)
                if any(current[key] != pr[key] for key in ("updated_at", "head", "base", "state")):
                    raise RuntimeError("PR changed while evaluating; rerun the gate")
                results.append(result)
                print(f"PR #{number}: {result[0]}: {result[1]}")
            except Exception as error:
                failed = True
                results.append(("pending", "Could not verify contribution policy; see workflow logs"))
                print(f"PR #{number}: {type(error).__name__}: {error}", file=sys.stderr)
        # Detect PRs opened/retargeted onto the same SHA during this evaluation.
        current_numbers = {p["number"] for p in api.pages(api.prefix + "/pulls", state="open", base=BASE)
                           if p["head"]["sha"] == sha}
        if current_numbers != {p["number"] for p in candidates}:
            results.append(("pending", "PR membership changed while evaluating; rerun the gate"))
        state, reason = next((r for r in results if r[0] == "pending"), results[0])
        api.status(sha, state, reason, run_url)
    return failed


if __name__ == "__main__":
    api = GitHub()
    if api.repo != "RopeWiki/app":
        raise SystemExit("The review gate is only configured for RopeWiki/app")
    with open(os.environ["GITHUB_EVENT_PATH"]) as source:
        event = json.load(source)
    url = (f"{os.environ['GITHUB_SERVER_URL']}/{api.repo}/actions/runs/"
           f"{os.environ['GITHUB_RUN_ID']}")
    sys.exit(1 if run(api, os.environ["GITHUB_EVENT_NAME"], event,
                     datetime.now(timezone.utc), url) else 0)
