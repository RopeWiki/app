# Review gate

`review-gate` implements Contributions item 2 in `CONTRIBUTING.md`. It publishes
a **commit status**, with `success` under a qualifying policy path and `pending`
otherwise. The workflow job is named `evaluate`; do not require that job instead.
The status links to the evaluation log, including the reason for each PR.

## Enable enforcement

1. Merge the workflows, script, and tests into `RopeWiki/app`'s `master` branch.
   The event listener and schedule must be on the default branch (`master`).
2. Run **Review Gate** manually from Actions to initialize existing open PRs.
3. In the `master` branch protection/ruleset, require a pull request and the
   `review-gate` status, selecting GitHub Actions as its expected source when
   offered. Keep the existing required CI checks.
4. Remove native required-approval rules.

The workflow files do not modify repository protection settings. No personal
access token, repository secret, or external scheduler is needed.

## Policy interpretation

- Write access is checked using current effective repository permissions,
  including write, maintain, and admin access, rather than author associations.
- Each writer's most recent submitted review determines their position.
  `COMMENTED` and `DISMISSED` replace earlier approval/change requests;
  unsubmitted draft reviews do not. The author's own reviews cannot approve
  their PR. An approval is not automatically discarded after a new push. A
  dismissed approval stops counting.
- For the seven-day alternative, a later nonempty author comment on the PR
  answers earlier general comments and review summaries. Inline comments require
  a later nonempty author reply in the same thread, including subsequent reviewer
  followups. A general reply cannot answer inline comments. Resolving a thread
  alone does not count as a reply. The Action checks that a response exists;
  reviewers and authors still judge its substance.
- The latest activity includes PR creation, comments, submitted reviews, edits,
  pushes, and timeline metadata events such as labels and review requests.
  Activity from bots counts too. CI/check/status updates do not count.
  Seven days means 168 elapsed hours, including across daylight saving changes.
- A neutral **Review gate activity #N** check records authenticated event actors
  and update timestamps for pushes/metadata changes. Commit timestamps cannot
  establish push time. If GitHub cannot establish the latest actor (for example,
  a historical push from before installation, a missing event, or deleted retained
  check data), the gate stays pending. An author comment makes the latest actor
  explicit and starts a new seven-day wait. Ties involving another actor within
  GitHub's one-second timestamp precision are treated conservatively.
- Commit statuses are shared by all PRs with the same head SHA. If several open
  PRs to `master` share a head, all must qualify before that SHA passes.

## Triggers and operation

PR and comment events reevaluate the policy, approve eligible reviewed PRs, and
revoke passes when the conditions stop holding. Review events first run a minimal
read-only **Review Gate Events** workflow; its completion wakes the trusted
evaluator. This handles fork PRs without giving their code a write token. The
evaluator checks out `master` explicitly and never uses event-workflow artifacts.

Pending seven-day gates are promoted once daily at **4:00 a.m.
America/Los_Angeles**, with daylight saving time handled by GitHub's timezone
schedule. Event runs preserve a still-valid seven-day pass. A manual run also
checks elapsed time and can be used after changing repository permissions.

All runs scan current open PRs to `master`, so queued event runs can coalesce
without losing a needed reevaluation. Missing activity attribution remains
pending. Metadata/API errors keep the status pending and fail the workflow for
diagnosis. Changes while evaluating are detected before posting a pass.

GitHub schedules are best effort: execution can be delayed or dropped under
load, and public-repository schedules can be disabled after 60 days without
repository activity. Event delivery and workflow startup are also asynchronous,
so a previously passing status can briefly remain visible after new activity.
An Action is not an atomic merge-time policy engine. A GitHub App with webhooks
and an external scheduler is the alternative if stronger operational guarantees
are needed.

See GitHub's [schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
and [required status checks documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging).

Run the policy tests with:

```sh
python3 -m unittest discover -s .github/tests -p 'test_*.py'
```
