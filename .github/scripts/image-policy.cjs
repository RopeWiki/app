'use strict';

// Only loaded from the publisher's default-branch checkout, never from a PR artifact.
const REPOSITORY = 'RopeWiki/app';
const WORKFLOW = '.github/workflows/build-and-test-images.yml';
const SHA = /^[a-f0-9]{40}$/;

// Stop publication with the supplied error message if a required condition fails.
function check(condition, message) {
  if (!condition) throw new Error(message);
}

// Verify the completed build, current source revision, and artifact metadata, then derive its image tag.
async function resolveBuild({ github, context }) {
  check(`${context.repo.owner}/${context.repo.repo}` === REPOSITORY, 'Unexpected repository');
  check(context.eventName === 'workflow_run', 'Only workflow_run may publish images');
  const event = context.payload.workflow_run;
  const repo = context.repo;
  const { data: run } = await github.rest.actions.getWorkflowRun({ ...repo, run_id: event.id });
  const { data: workflow } = await github.rest.actions.getWorkflow({ ...repo, workflow_id: 'build-and-test-images.yml' });
  check(run.repository.full_name === REPOSITORY && run.workflow_id === workflow.id && run.path === WORKFLOW,
    'Unexpected source workflow');
  check(run.status === 'completed' && run.conclusion === 'success', 'Build must have succeeded');
  check(run.run_attempt === event.run_attempt && run.head_sha === event.head_sha,
    'Build was rerun or changed; use the new completion event');
  check(SHA.test(run.head_sha), 'Invalid source SHA');
  check(Number.isSafeInteger(run.id) && Number.isSafeInteger(run.run_number) &&
    Number.isSafeInteger(run.run_attempt) && run.id > 0 && run.run_number > 0 && run.run_attempt > 0,
  'Invalid build identifiers');

  let pr = null;
  let kind;
  if (run.event === 'pull_request') {
    // workflow_run.pull_requests is often empty for forks. Resolve using API
    // metadata, not a PR number supplied in an untrusted artifact.
    check(run.head_repository?.owner?.login && run.head_branch, 'Missing source repository');
    const candidates = await github.paginate(github.rest.pulls.list, {
      ...repo, state: 'open', head: `${run.head_repository.owner.login}:${run.head_branch}`,
      base: 'master', per_page: 100,
    });
    const matches = candidates.filter(candidate => candidate.head.sha === run.head_sha &&
      candidate.head.repo?.id === run.head_repository.id &&
      candidate.base.repo.full_name === REPOSITORY && candidate.base.ref === 'master');
    check(matches.length === 1, 'Build must match exactly one current, open PR to master');
    ({ data: pr } = await github.rest.pulls.get({ ...repo, pull_number: matches[0].number }));
    check(pr.state === 'open' && pr.head.sha === run.head_sha &&
      pr.head.repo?.id === run.head_repository.id && pr.base.ref === 'master' &&
      pr.base.repo.full_name === REPOSITORY, 'PR changed while resolving build');
    kind = 'preview';
  } else {
    // Schedules and manual builds still test the site but do not move release tags.
    check(run.event === 'push' && run.head_branch === 'master' &&
      run.head_repository.full_name === REPOSITORY, 'Only master pushes publish release images');
    const { data: branch } = await github.rest.repos.getBranch({ ...repo, branch: 'master' });
    check(branch.commit.sha === run.head_sha, 'A newer master revision superseded this release');
    kind = 'release';
  }

  const artifacts = await github.paginate(github.rest.actions.listWorkflowRunArtifacts, {
    ...repo, run_id: run.id, per_page: 100,
  });
  const matching = artifacts.filter(artifact => artifact.name === `tested-images-${run.id}-${run.run_attempt}`);
  check(matching.length === 1 && !matching[0].expired, 'Missing or expired tested-image artifact for this attempt');
  const artifact = matching[0];
  check(/^sha256:[a-f0-9]{64}$/.test(artifact.digest), 'Artifact needs a GitHub SHA-256 digest');
  check(Number.isSafeInteger(artifact.id), 'Invalid artifact ID');
  return {
    run, pr,
    plan: {
      kind, runId: run.id, runAttempt: run.run_attempt, sha: run.head_sha,
      prNumber: pr?.number ?? null, artifactId: artifact.id, artifactDigest: artifact.digest,
      runUrl: `https://github.com/${REPOSITORY}/actions/runs/${run.id}/attempts/${run.run_attempt}`,
      tag: kind === 'preview'
        ? `pr-${pr.number}-${run.head_sha.slice(0, 12)}-run-${run.run_number}-attempt-${run.run_attempt}`
        : `sha-${run.head_sha.slice(0, 7)}`,
    },
  };
}

// Check public RopeWiki membership, requiring review if membership cannot be confirmed.
async function isPublicMember({ github, username, core }) {
  if (!username) return false;
  try {
    const result = await github.request('GET /orgs/{org}/public_members/{username}', {
      org: 'RopeWiki', username,
    });
    return result.status === 204;
  } catch (error) {
    // Unknown membership is never automatic authorization.
    if (error.status !== 404) core.warning(`Could not verify public org membership (HTTP ${error.status ?? 'unknown'}); requiring review`);
    return false;
  }
}

// Require a master-only environment and, for external previews, RopeWiki team reviewers.
async function validateEnvironment({ github, context, name, external }) {
  const { data: environment } = await github.rest.repos.getEnvironment({
    ...context.repo, environment_name: name,
  });
  check(environment.deployment_branch_policy?.custom_branch_policies === true &&
    environment.deployment_branch_policy.protected_branches === false,
  `${name} must explicitly restrict deployments to the master branch`);
  const policies = await github.paginate(github.rest.repos.listDeploymentBranchPolicies, {
    ...context.repo, environment_name: name, per_page: 100,
  });
  check(policies.length === 1 && policies[0].name === 'master' && policies[0].type === 'branch',
    `${name} must allow exactly the master branch (no tags or wildcards)`);
  if (external) {
    const rule = environment.protection_rules.find(item => item.type === 'required_reviewers');
    check(rule?.reviewers?.length > 0 && rule.reviewers.every(item => item.type === 'Team' &&
      item.reviewer.html_url.toLowerCase().startsWith('https://github.com/orgs/ropewiki/teams/')),
    'preview-external must require review exclusively by RopeWiki teams');
  }
}

// Select and validate the publishing environment, or skip events that do not publish images.
async function planPublication({ github, context, core }) {
  const event = context.payload.workflow_run;
  if (!['pull_request', 'push'].includes(event.event)) {
    core.info('Scheduled/manual site tests do not publish images');
    return null;
  }
  const { plan, run, pr } = await resolveBuild({ github, context });
  let member = false;
  if (pr) {
    // A member-authored PR does not authorize a new push triggered by an outsider.
    const users = [...new Set([pr.user.login, run.actor.login])];
    const membership = await Promise.all(users.map(username => isPublicMember({
      github, username, core,
    })));
    member = membership.every(Boolean);
  }
  plan.environment = plan.kind === 'release' ? 'image-releases' : member ? 'preview-members' : 'preview-external';
  plan.description = `${pr ? `PR #${pr.number}` : 'Master'} ${plan.sha.slice(0, 12)} / build ${plan.runId} attempt ${plan.runAttempt}`;
  await validateEnvironment({ github, context, name: plan.environment, external: plan.environment === 'preview-external' });
  return plan;
}

// Recheck the approved build, artifact metadata, and environment before publishing.
async function revalidatePublication({ github, context, plan }) {
  const current = (await resolveBuild({ github, context })).plan;
  for (const key of Object.keys(current)) {
    check(current[key] === plan[key], `Approved build changed: ${key}`);
  }
  check(['preview-members', 'preview-external', 'image-releases'].includes(plan.environment), 'Invalid publishing environment');
  await validateEnvironment({ github, context, name: plan.environment, external: plan.environment === 'preview-external' });
}

module.exports = { planPublication, revalidatePublication, resolveBuild, validateEnvironment };
