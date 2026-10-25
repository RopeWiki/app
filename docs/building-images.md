# Building and publishing images

Contributors can open a PR to `RopeWiki/app:master` from a branch in their own fork.
They do not need to push a branch into the RopeWiki repository or have a registry
account.

## Registry locations

GitHub Container Registry (**GHCR**, `ghcr.io`) and **Docker Hub** (`docker.io`) are
separate services. Both store images that Docker can run; a Docker image does not have
to be hosted on Docker Hub.

CI publishes both contributor previews and master-branch images to GHCR. The manually
invoked `publish.sh` is the only Docker Hub publishing path, for versioned and `latest`
production images.

## Contributor workflow

1. Open or update the PR. CI builds all five images and starts an empty site that it
   performs tests on. GitHub may first require a maintainer to approve running a fork's
   workflows.
2. A successful build uploads a `tested-images-RUN_ID-ATTEMPT` artifact. Artifacts
   expire after three days to limit storage; rerun **Build and Test Images** if approval
   takes longer.
3. Using code from the default branch, CI resolves the current PR and checks membership.
   If both the PR author and the original build actor are public RopeWiki members,
   publishing proceeds automatically. Otherwise, a member of a configured RopeWiki
   reviewer team must approve the `preview-external` environment using
   **Review deployments** on the publishing run. Rerunning an outsider's build as a
   member is not publishing approval.
4. Before approving, review the PR changes and the linked build/attempt in the policy
   job summary. Approval applies to those artifact bytes, commit, run, and attempt. A
   new commit or build attempt needs fresh approval. The publisher checks that the PR is
   still open and its head matches the build, then rechecks after approval; a mismatch
   stops publication. Ordinary fork workflow approval does not grant registry access.
5. Find the image tags and digests in the publisher's **Published images** summary.

Preview repositories are:

* `ghcr.io/ropewiki/backup_manager-preview`
* `ghcr.io/ropewiki/database-preview`
* `ghcr.io/ropewiki/mailserver-preview`
* `ghcr.io/ropewiki/reverse_proxy-preview`
* `ghcr.io/ropewiki/webserver-preview`

All five images use the same tag, for example `pr-199-2bb710ed0a01-run-117-attempt-2`.
No moving `latest` preview tag is published. The SHA in a PR tag identifies the PR head;
the images come from the CI-tested checkout, normally GitHub's PR merge revision. The
build attempt and artifact digest identify exactly which tested output was published.
Use the recorded registry digest when an immutable image reference is required.

## Trying the images

Follow [deployment setup](../playbooks/deployment.md) to configure a separate
development site and its passwords, directories, and empty database. Select the preview
images in the same shell before using the deployment tool:

```sh
export DOCKER_IMAGE_REGISTRY=ghcr.io/ropewiki
export DOCKER_IMAGE_SUFFIX=-preview
export DOCKER_IMAGE_TAG=pr-199-2bb710ed0a01-run-117-attempt-2
python3 deploy_tool.py dev dc pull
# Create/restore the development database as described in deployment.md, then:
python3 deploy_tool.py dev dc up -d --no-build
```

On PowerShell, set the same values with `$env:DOCKER_IMAGE_SUFFIX = '-preview'`, etc.
Use the matching contributor revision of the Compose configuration when the PR changes
runtime configuration. Preview approval permits publishing experimental code; it does
not make that code a reviewed production release.

## One-time administrator setup

Publishing is disabled until repository variable `IMAGE_PUBLISHING_ENABLED` equals
`true`. Configure the following before enabling it. Builds/tests continue to run while
publishing is disabled. No registry credentials belong in the build job.

### GitHub environments

Create these environments in **RopeWiki/app → Settings → Environments**:

| Environment        | Required reviewers                                                      | Purpose                                                      |
| ------------------ | ----------------------------------------------------------------------- | ------------------------------------------------------------ |
| `preview-members`  | None                                                                    | Automatic previews for public RopeWiki members               |
| `preview-external` | Someone on an approved RopeWiki team                                    | Approval for contributors without public RopeWiki membership |
| `image-releases`   | None; PRs merged to master should be built without additional approvals | Automatic GHCR publishing after a successful master build    |

For **all three environments**, disable
**Allow administrators to bypass configured protection rules** wherever GitHub offers
that setting. This ensures that configured approval rules also apply to administrators.
It matters especially for `preview-external`. Environments without approval rules have
no reviewer approval to bypass; do not add reviewers to `preview-members` just to expose
this setting.

For **all three environments**, choose **Selected branches and tags** and add exactly
one **branch** rule named `master`. Do not add a tag rule, wildcards, or PR merge refs.
The publisher runs on the default branch even when its source build ran on a fork. These
rules prevent jobs running on PR refs from deploying to these environments. They do not
restrict `GITHUB_TOKEN` permissions in jobs that do not use an environment. Protect
`master` and review changes to the publishing workflows/scripts as privileged code.

For **preview-external → Required reviewers**, add one or more
**GitHub teams in the RopeWiki organization**, for example `RopeWiki/image-reviewers`.
Create the team under **RopeWiki → Teams** if needed, include the members allowed to
authorize preview publication, and give it at least read access to `RopeWiki/app`.
Adding a team under **Required reviewers** lets one member of any listed team approve
that publishing job; approval from every team is not required. Do not add individual
users or outside reviewers: this implementation checks that the required reviewer
entries are exclusively RopeWiki teams.

The policy job verifies that the destination environment exists, restricts it to
`master`, and, for outsiders, requires only RopeWiki teams. Missing/misconfigured
environments stop publication instead of silently creating an environment with no
approval rules.

### Membership verification

Only **public RopeWiki membership** qualifies for automatic preview publication. The
policy checks GitHub's public membership endpoint for both the PR author and the
original build actor, using the workflow's normal `GITHUB_TOKEN`. No additional token,
secret, or membership environment is needed.

Contributors whose membership is private use the approval path, as do nonmembers. If the
API cannot verify public membership, publishing also requires approval. Repository
collaborator status alone does not qualify for automatic publication.

### GHCR access and visibility

Both preview and release jobs authenticate to `ghcr.io` using the automatically provided
`GITHUB_TOKEN` with `packages: write`. No registry secrets or variables need to be added
to any environment.

GHCR creates the five `*-preview` packages on their first successful push. Allow
`RopeWiki/app` to create packages in the RopeWiki organization. For any existing preview
or release package, open its **Package settings → Manage Actions access** and ensure
`RopeWiki/app` has **Write** access (or inherits it from the linked repository).

New GHCR packages are private by default. After the first approved preview is published,
change all five preview packages to **Public** in **Package settings** so contributors
can pull them without logging in. The first publishing run can succeed while they are
private; anonymous pulls become available after changing visibility. See
[GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Preview and release images use separate package names and fixed destinations in trusted
publishing code. `GITHUB_TOKEN` access is scoped to the repository's accessible
packages, not individually restricted by environment or image suffix; the
preview/release destination boundary is enforced by the trusted publisher.

### Master/release publishing

A push to `master`, including a PR merge, starts a fresh build and test run for that
master commit. After it succeeds, the publisher takes the images from that run's
uploaded artifact and pushes them to the five non-preview GHCR packages with tags
`sha-SHORT_SHA` and `github-master-latest`. It uses the same `GITHUB_TOKEN`
authentication as previews. Ensure RopeWiki/app has write access to those GHCR packages.

The publisher checks that the build's commit is still the current `master` when planning
publication and again after waiting for the publishing environment. If either check
finds a newer master commit, the publishing job fails. Release publishing jobs run one
at a time. These checks happen before the registry copy; if `master` advances after the
final check, an in-progress publication can still finish. Branch updates and registry
publication are not atomic. Scheduled and manually dispatched builds run the tests and
upload artifacts but do not publish images to a registry.

Once environments and package permissions are ready, set repository variable
**IMAGE_PUBLISHING_ENABLED=true**. Merge these workflows into `master` before expecting
`workflow_run` to trigger. Existing PRs need a new build using the new artifact-export
steps (merge/rebase master and push, or update the PR branch). Rerunning an old workflow
revision does not add the new export steps.

## Security boundaries and validation

The build runs contributor Dockerfiles/scripts on disposable GitHub-hosted runners with
a read-only token, no saved checkout credential, no registry credentials, and no OIDC
permission. Its artifacts are untrusted input even after the tests pass.

The publisher checks the source workflow ID/path, source repository, run attempt,
current PR head and fork, and the exact artifact ID and GitHub SHA-256 digest. It checks
these again after environment approval. It refuses duplicate/expired artifacts,
unexpected archive paths, symlinks, missing images, and oversized files. The build and
publisher do not share caches or runners.

Only default-branch scripts/actions execute in the publisher. It copies image archives
with `skopeo` and never runs their containers or scripts. Registry destinations and
image names are fixed by trusted code. Only the trusted publishing jobs have GHCR
package write permission; no CI job receives Docker Hub credentials.

Run the security regression tests locally with Node.js 20+ and Python 3.9+:

```sh
node --test .github/tests/image-policy.test.cjs
python3 -m unittest discover -s .github/tests -p 'test_*.py'
```

The same tests run in a separate prerequisite job before the image build. After initial
setup, verify one public member PR and one PR without public membership: the former
should publish automatically, the latter should wait for **Review deployments**, and
updating it while waiting should invalidate that older build. Test each image by digest
on a separate development machine.
