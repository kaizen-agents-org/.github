import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runScout, validateFindings } from '../automations/scout-api-client.mjs';
import { flattenPaginated, openAiModel } from '../automations/scout-api-client.mjs';

const valid = (count = 1) => ({ findings: Array.from({ length: count }, (_, i) => ({
  title: `Improve bounded behavior ${i}`,
  body: 'This is a sufficiently detailed bounded finding supported by default-branch evidence.',
  evidence: 'docs/scout-contract.md: section Required behaviour',
})), skipped: [] });

const base = () => ({ target: 'owner/repo', intakeLabel: 'kaizen', labels: ['kaizen', 'team:maintenance'], openIssueLimit: 4, wipLimit: 4, creationLimit: 1, model: { baseUrl: 'http://gateway.test/v1', name: 'scout' } });

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

test('intake label is explicit and independent of label order', async () => {
  const d = deps({ state: { openIssues: [{ title: 'x' }], openPullRequests: [] } });
  const config = { ...base(), labels: ['team:maintenance', 'kaizen'], intakeLabel: 'kaizen', openIssueLimit: 1 };
  const result = await runScout(config, d);
  assert.equal(d.calls.model, 0); assert.equal(result.filed.length, 0);
  await assert.rejects(() => runScout({ ...base(), intakeLabel: undefined }, deps()), /intakeLabel/);
});

test('WIP limit stops before model call', async () => {
  const d = deps({ state: { openIssues: [], openPullRequests: [{ title: 'x' }] } });
  const result = await runScout({ ...base(), wipLimit: 1 }, d);
  assert.equal(d.calls.model, 0); assert.equal(result.filed.length, 0);
});

test('WIP limit is rechecked immediately before creation', async () => {
  const d = deps();
  let calls = 0;
  d.github.openState = async () => {
    calls += 1;
    return { openIssues: [], duplicateIssues: [], openPullRequests: calls > 1 ? [{ title: 'new PR' }] : [] };
  };
  const result = await runScout({ ...base(), wipLimit: 1 }, d);
  assert.equal(d.calls.creates.length, 0);
  assert.match(result.skipped[0].reason, /WIP/);
});

test('overlapping runs serialize the final duplicate and creation claim', async () => {
  const lockPath = join(tmpdir(), `scout-test-${process.pid}-${Date.now()}.lock`);
  const finding = valid().findings[0];
  const state = { openIssues: [], openPullRequests: [] };
  const calls = { creates: 0, active: 0, maxActive: 0 };
  const github = {
    openState: async () => ({ openIssues: [...state.openIssues], duplicateIssues: [...state.openIssues], openPullRequests: [] }),
    verifyLabels: async () => true,
    defaultBranchContext: async () => ({ defaultBranch: 'main', content: 'README content' }),
    createIssue: async () => {
      calls.creates += 1; calls.active += 1; calls.maxActive = Math.max(calls.maxActive, calls.active);
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 10));
      state.openIssues.push({ title: finding.title }); calls.active -= 1;
      return 'https://github.test/issues/1';
    }
  };
  const dependencies = { github, model: async () => ({ findings: [finding], skipped: [] }) };
  const config = { ...base(), creationLimit: 1, lockPath };
  const results = await Promise.all([runScout(config, dependencies), runScout(config, dependencies)]);
  assert.equal(calls.creates, 1);
  assert.equal(calls.maxActive, 1);
  assert.equal(results.filter((result) => result.filed.length === 1).length, 1);
  assert.equal(fs.existsSync(lockPath), false);
});

test('paginated results flatten every page for label and duplicate callers', () => {
  const pages = [Array.from({ length: 100 }, (_, i) => ({ name: `label-${i}` })), [{ name: 'kaizen' }]];
  assert.equal(flattenPaginated(pages).length, 101);
  assert.equal(flattenPaginated(pages).at(-1).name, 'kaizen');
});

test('schema and JSON-only instructions remain when constrained decoding is disabled', async () => {
  const originalFetch = globalThis.fetch;
  let request;
  globalThis.fetch = async (_url, options) => {
    request = JSON.parse(options.body);
    return { ok: true, json: async () => ({ choices: [{ message: { content: JSON.stringify(valid()) } }] }) };
  };
  try {
    await openAiModel({ baseUrl: 'http://gateway.test/v1', name: 'scout', request: 'inspect', constrainedDecoding: false });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(request.response_format, undefined);
  assert.match(request.messages[0].content, /Return only valid JSON/);
  assert.match(request.messages[0].content, /findings/);
  assert.match(request.messages[0].content, /evidence/);
});

test('schema and JSON-only instructions remain after response-format fallback', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (_url, options) => {
    requests.push(JSON.parse(options.body));
    if (requests.length === 1) return { ok: false, status: 422 };
    return { ok: true, json: async () => ({ choices: [{ message: { content: JSON.stringify(valid()) } }] }) };
  };
  try {
    await openAiModel({ baseUrl: 'http://gateway.test/v1', name: 'scout', request: 'inspect' });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(requests.length, 2);
  assert.equal(requests[1].response_format, undefined);
  assert.match(requests[1].messages[0].content, /Return only valid JSON/);
  assert.match(requests[1].messages[0].content, /scout findings schema/);
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
