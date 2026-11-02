# Contributing to this repository

Welcome to the RopeWiki app repository and thank you for your interest in contributing to it.

## Contributions

1. Any change to the master branch in this repository must be handled through a [Pull Request (PR)](https://docs.github.com/en/get-started/quickstart/contributing-to-projects).

1. No PR may be merged to the master branch except in one of the two situations below:
    1. Approved PR, where all the following are true:
        1. The PR is approved by a committer with write access to repository (see Reviews below for approval criteria) as their most recent review.
        1. No committer with write access has requested changes as their most recent review.
    1. Lack of engagement, where all the following are true:
        1. The PR author has write access to the repository.
        1. The most recent activity on the PR was from the author of the PR.
        1. Any and all comments from reviewers with write access to the repository have responses from the author of the PR.
        1. At least 7 days has elapsed since the most recent activity on the PR.

1. Small PRs are strongly preferred and reviewers are likely to decline to review a PR that is too large.  See the following resources for small PRs:
    - [Google eng practices: small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)
    - [Strategies For Small, Focused Pull Requests, Steve Hicks](https://artsy.github.io/blog/2021/03/09/strategies-for-small-focused-pull-requests/)
    - [The Art of Small Pull Requests, David Wilson](https://essenceofcode.com/2019/10/29/the-art-of-small-pull-requests/)

1. All PRs should be merged via "Squash and merge".

## Reviews

1. There is no expectation of review for a PR in the draft state (though review can be provided any way).

1. The master branch is expected to remain stable at all times.  Except in rare circumstances, merging a PR to master should mean the changes in the PR are ready to deploy to production.  Therefore, approving a PR should indicate that the reviewer believes the changes in the PR are ready to deploy to production.

1. PRs to the master branch are expected to pass [continuous integration (CI) tests](.github/workflows).

1. PRs to the master branch involving changes that are not covered by CI tests are expected to document why the author is confident the changes in the PR work properly.  This can usually be accomplished by briefly describing the verification exercise(s) the author performed (e.g., "changes rendered correctly with a local deployment"), though reviewers may ask for more detail or request additional verification.

1. After approving a PR from a contributor with write access to the repo, generally allow the author to merge the PR unless merging is urgent (e.g., required to fix a problem or for further development).

1. After approving a PR from a contributor without write access to the repo, the reviewer should either make a comment mentioning other reviewers they would like additional input from, or the reviewer should merge the PR.

1. When a reviewer approves a PR but also leaves comments, the author of the PR is expected to adjudicate those comments as the author sees fit before the PR is merged.  But, the reviewer is indicating that they trust the author to resolve these comments appropriately without further input from the reviewer.
