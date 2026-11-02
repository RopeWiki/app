'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { planPublication, revalidatePublication } = require('../scripts/image-policy.cjs');

function fixture() {
  const sha = 'a'.repeat(40);
  const state = {
    run: {
      id: 123, run_number: 17, run_attempt: 2, head_sha: sha, head_branch: 'feature',
      head_repository: { id: 99, full_name: 'contributor/app', owner: { login: 'contributor' } },
      repository: { full_name: 'RopeWiki/app' }, workflow_id: 42,
      path: '.github/workflows/build-and-test-images.yml', event: 'pull_request',
      status: 'completed', conclusion: 'success', actor: { login: 'contributor' },
      pull_requests: [], // The actual fork payload has no PR entries.
    },
    pr: {
      number: 199, state: 'open', user: { login: 'contributor' },
      head: { sha, repo: { id: 99 } }, base: { ref: 'master', repo: { full_name: 'RopeWiki/app' } },
    },
    artifact: { id: 456, name: 'tested-images-123-2', expired: false, digest: `sha256:${'b'.repeat(64)}` },
    environment: {
      deployment_branch_policy: { custom_branch_policies: true, protected_branches: false },
      protection_rules: [{ type: 'required_reviewers', reviewers: [
        { type: 'Team', reviewer: { html_url: 'https://github.com/orgs/RopeWiki/teams/image-reviewers' } },
      ] }],
    },
    branchPolicies: [{ name: 'master', type: 'branch' }],
    publicMembers: new Set(), memberError: null, membershipRequests: [], branchSha: sha,
  };
  const context = { repo: { owner: 'RopeWiki', repo: 'app' }, eventName: 'workflow_run',
    payload: { workflow_run: structuredClone(state.run) } };
  const github = {
    rest: {
      actions: {
        getWorkflowRun: async () => ({ data: state.run }),
        getWorkflow: async params => {
          assert.equal(params.workflow_id, 'build-and-test-images.yml');
          return { data: { id: 42 } };
        },
        listWorkflowRunArtifacts: 'artifacts',
      },
      pulls: { list: 'prs', get: async () => ({ data: state.pr }) },
      repos: {
        getBranch: async () => ({ data: { commit: { sha: state.branchSha } } }),
        getEnvironment: async () => ({ data: state.environment }),
        listDeploymentBranchPolicies: 'policies',
      },
    },
    paginate: async method => {
      if (method === 'artifacts') return state.artifacts ?? [state.artifact];
      if (method === 'prs') return state.prs ?? [state.pr];
      if (method === 'policies') return state.branchPolicies;
      throw new Error('Unexpected pagination');
    },
    request: async (endpoint, params) => {
      state.membershipRequests.push({ endpoint, params });
      if (state.memberError) throw Object.assign(new Error('membership unavailable'), { status: state.memberError });
      assert.equal(endpoint, 'GET /orgs/{org}/public_members/{username}');
      return { status: state.publicMembers.has(params.username) ? 204 : 404 };
    },
  };
  const core = { info() {}, warning() {} };
  return { state, context, github, core };
}

test('fork builds with empty PR metadata require outside approval and get a run-specific tag', async () => {
  const f = fixture();
  const plan = await planPublication(f);
  assert.equal(plan.environment, 'preview-external');
  assert.equal(plan.prNumber, 199);
  assert.equal(plan.tag, 'pr-199-aaaaaaaaaaaa-run-17-attempt-2');
  assert.equal(plan.artifactId, 456);
});

test('public members publish automatically from their own forks without an org credential', async () => {
  const f = fixture();
  f.state.publicMembers.add('contributor');
  assert.equal((await planPublication(f)).environment, 'preview-members');
  assert.deepEqual(f.state.membershipRequests, [{
    endpoint: 'GET /orgs/{org}/public_members/{username}',
    params: { org: 'RopeWiki', username: 'contributor' },
  }]);
});

test('membership errors fall back to review', async () => {
  const f = fixture();
  f.state.memberError = 403;
  assert.equal((await planPublication(f)).environment, 'preview-external');
});

test('member author cannot authorize an outsider-triggered push', async () => {
  const f = fixture();
  f.state.publicMembers.add('contributor');
  f.state.run.actor.login = 'outsider';
  assert.equal((await planPublication(f)).environment, 'preview-external');
});

test('member rerunning an outsider build is not publishing approval', async () => {
  const f = fixture();
  f.state.run.triggering_actor = { login: 'maintainer' };
  f.state.publicMembers.add('maintainer');
  assert.equal((await planPublication(f)).environment, 'preview-external');
});

for (const [name, mutate, message] of [
  ['failed build', f => { f.state.run.conclusion = 'failure'; }, /succeeded/],
  ['other workflow with the same name', f => { f.state.run.workflow_id = 43; }, /source workflow/],
  ['other repository', f => { f.context.repo.owner = 'attacker'; }, /repository/],
  ['non-workflow_run caller', f => { f.context.eventName = 'pull_request_target'; }, /workflow_run/],
  ['new source attempt', f => { f.state.run.run_attempt++; }, /rerun or changed/],
  ['closed PR', f => { f.state.pr.state = 'closed'; }, /PR changed/],
  ['new PR head', f => { f.state.pr.head.sha = 'c'.repeat(40); }, /current, open PR/],
  ['wrong fork', f => { f.state.pr.head.repo.id = 100; }, /current, open PR/],
  ['wrong base branch', f => { f.state.pr.base.ref = 'other'; }, /current, open PR/],
  ['ambiguous PR', f => { f.state.prs = [f.state.pr, structuredClone(f.state.pr)]; }, /exactly one/],
  ['old attempt artifact', f => { f.state.artifact.name = 'tested-images-123-1'; }, /artifact/],
  ['expired artifact', f => { f.state.artifact.expired = true; }, /expired/],
  ['missing digest', f => { delete f.state.artifact.digest; }, /digest/],
  ['duplicate artifacts', f => { f.state.artifacts = [f.state.artifact, f.state.artifact]; }, /artifact/],
  ['missing reviewer rule', f => { f.state.environment.protection_rules = []; }, /RopeWiki teams/],
  ['outside reviewer team', f => { f.state.environment.protection_rules[0].reviewers[0].reviewer.html_url = 'https://github.com/orgs/Other/teams/a'; }, /RopeWiki teams/],
  ['individual reviewer', f => { f.state.environment.protection_rules[0].reviewers[0].type = 'User'; }, /RopeWiki teams/],
  ['unrestricted environment', f => { f.state.environment.deployment_branch_policy = null; }, /restrict/],
  ['wildcard environment', f => { f.state.branchPolicies[0].name = '*'; }, /master branch/],
  ['master-named tag', f => { f.state.branchPolicies[0].type = 'tag'; }, /master branch/],
]) {
  test(`reject ${name}`, async () => {
    const f = fixture();
    mutate(f);
    await assert.rejects(() => planPublication(f), message);
  });
}

test('approval cannot follow new commits, attempts, or replacement artifacts', async () => {
  for (const mutate of [
    f => { f.state.pr.head.sha = 'd'.repeat(40); },
    f => { f.state.run.run_attempt++; },
    f => { f.state.artifact.id++; },
    f => { f.state.artifact.digest = `sha256:${'e'.repeat(64)}`; },
  ]) {
    const f = fixture();
    const plan = await planPublication(f);
    await revalidatePublication({ ...f, plan });
    mutate(f);
    await assert.rejects(() => revalidatePublication({ ...f, plan }));
  }
});

test('a missing environment fails instead of silently creating an unprotected one', async () => {
  const f = fixture();
  f.github.rest.repos.getEnvironment = async () => { throw Object.assign(new Error('missing environment'), { status: 404 }); };
  await assert.rejects(() => planPublication(f), /missing environment/);
});

test('master pushes retain the GHCR release route; stale master cannot move release tags', async () => {
  const f = fixture();
  f.state.run.event = 'push';
  f.context.payload.workflow_run.event = 'push';
  f.state.run.head_branch = 'master';
  f.state.run.head_repository.full_name = 'RopeWiki/app';
  const plan = await planPublication(f);
  assert.equal(plan.environment, 'image-releases');
  assert.equal(plan.kind, 'release');
  f.state.branchSha = 'f'.repeat(40);
  await assert.rejects(() => revalidatePublication({ ...f, plan }), /superseded/);
});

test('scheduled and manual tests do not publish', async () => {
  for (const event of ['schedule', 'workflow_dispatch']) {
    const f = fixture();
    f.context.payload.workflow_run.event = event;
    assert.equal(await planPublication(f), null);
  }
});
