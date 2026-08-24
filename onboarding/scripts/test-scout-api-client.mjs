import assert from 'node:assert/strict';
import test from 'node:test';
import { runScout, validateFindings } from '../automations/scout-api-client.mjs';

const valid = (count = 1) => ({ findings: Array.from({ length: count }, (_, i) => ({
  title: `Improve bounded behavior ${i}`,
  body: 'This is a sufficiently detailed bounded finding supported by default-branch evidence.',
  evidence: 'docs/scout-contract.md: section Required behaviour',
})), skipped: [] });

const base = () => ({ target: 'owner/repo', labels: ['kaizen', 'team:maintenance'], openIssueLimit: 4, wipLimit: 4, creationLimit: 1, model: { baseUrl: 'http://gateway.test/v1', name: 'scout' } });

function deps({ state = { openIssues: [], openPullRequests: [] }, response = valid(), labels = true } = {}) {
  const calls = { model: 0, creates: [] };
  return { calls, github: {
    openState: async () => ({ ...state, duplicateIssues: state.openIssues }),
    verifyLabels: async () => labels,
    defaultBranchContext: async () => ({ defaultBranch: 'main', content: 'README content' }),
    createIssue: async (_target, title, body, applied) => { calls.creates.push({ title, body, applied }); return 'https://github.test/issues/1'; }
  }, model: async () => { calls.model++; return response; } };
}

test('backlog limit stops before model call', async () => {
  const d = deps({ state: { openIssues: [{ title: 'x' }], openPullRequests: [] } });
  const result = await runScout({ ...base(), openIssueLimit: 1 }, d);
  assert.equal(d.calls.model, 0); assert.equal(result.filed.length, 0);
});

test('WIP limit stops before model call', async () => {
  const d = deps({ state: { openIssues: [], openPullRequests: [{ title: 'x' }] } });
  const result = await runScout({ ...base(), wipLimit: 1 }, d);
  assert.equal(d.calls.model, 0); assert.equal(result.filed.length, 0);
});

test('null and invalid schema roots are rejected', () => {
  assert.throws(() => validateFindings(null), /root/);
  assert.throws(() => validateFindings([]), /root/);
  assert.throws(() => validateFindings({ findings: [{ title: 'valid title', body: 'short', evidence: 'evidence' }] }), /body/);
});

test('duplicate open work is dropped and no issue is created', async () => {
  const finding = valid().findings[0];
  const d = deps({ state: { openIssues: [{ title: finding.title }], openPullRequests: [] } });
  const result = await runScout(base(), d);
  assert.equal(d.calls.model, 1); assert.equal(d.calls.creates.length, 0);
  assert.match(result.skipped[0].reason, /duplicate/);
});

test('an unlabelled open issue still suppresses duplicate work', async () => {
  const finding = valid().findings[0];
  const d = deps();
  d.github.openState = async () => ({ openIssues: [], duplicateIssues: [{ title: finding.title }], openPullRequests: [] });
  const result = await runScout(base(), d);
  assert.equal(d.calls.creates.length, 0);
  assert.match(result.skipped[0].reason, /duplicate/);
});

test('creation limit and configured labels are enforced', async () => {
  const d = deps({ response: valid(10) });
  const result = await runScout(base(), d);
  assert.equal(result.filed.length, 1); assert.deepEqual(d.calls.creates[0].applied, base().labels);
  assert.match(d.calls.creates[0].title, /^\[scout\] /); assert.match(d.calls.creates[0].body, /PR linkage requirement/);
  assert.match(d.calls.creates[0].body, /docs\/scout-contract\.md/);
});

test('a second equivalent finding is suppressed after the first create', async () => {
  const response = valid(2);
  response.findings[1].title = response.findings[0].title;
  const d = deps({ response });
  const result = await runScout({ ...base(), creationLimit: 2 }, d);
  assert.equal(d.calls.creates.length, 1);
  assert.match(result.skipped.at(-1).reason, /duplicate/);
});

test('missing configured label fails closed', async () => {
  const d = deps({ labels: false });
  const result = await runScout(base(), d);
  assert.equal(d.calls.model, 0); assert.equal(d.calls.creates.length, 0);
});

test('a no-op run reports why', async () => {
  const d = deps({ response: { findings: [], skipped: [{ reason: 'nothing bounded' }] } });
  const result = await runScout(base(), d);
  assert.equal(result.filed.length, 0); assert.equal(result.skipped[0].reason, 'nothing bounded');
});
