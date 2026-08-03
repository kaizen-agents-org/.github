#!/usr/bin/env node

import assert from 'node:assert/strict';
import { reconcileScoutDuplicates } from './reconcile-scout-duplicates.mjs';

function issue(number, state, createdAt, targets = []) {
  return {
    number,
    state,
    createdAt,
    body: '',
    comments: targets.map((target) => ({
      body: `<!-- kaizen-scout-duplicate: canonical=#${target} -->\nDuplicate of #${target}.`,
    })),
  };
}

function createRunner(initialIssues) {
  const issues = new Map(initialIssues.map((candidate) => [candidate.number, structuredClone(candidate)]));
  const mutations = [];

  async function runGh(args) {
    await new Promise((resolve) => setImmediate(resolve));
    if (args[0] === 'api') {
      const match = args.at(-1).match(/\/issues\/(\d+)\/comments$/);
      assert(match, `unsupported fake gh api command: ${args.join(' ')}`);
      const candidate = issues.get(Number(match[1]));
      assert(candidate, `missing fake issue #${match[1]}`);
      return JSON.stringify([[...structuredClone(candidate.comments)]]);
    }
    const action = args[1];
    const number = Number(args[2]);
    const candidate = issues.get(number);
    assert(candidate, `missing fake issue #${number}`);
    if (action === 'view') return JSON.stringify(structuredClone(candidate));
    if (action === 'reopen') {
      candidate.state = 'OPEN';
      mutations.push(`reopen:${number}`);
      return '';
    }
    const bodyIndex = args.findIndex((argument) => argument === '--body' || argument === '--comment');
    const body = bodyIndex >= 0 ? args[bodyIndex + 1] : undefined;
    if (action === 'comment') {
      candidate.comments.push({ body });
      mutations.push(`comment:${number}`);
      return '';
    }
    if (action === 'close') {
      if (body) candidate.comments.push({ body });
      candidate.state = 'CLOSED';
      mutations.push(`close:${number}`);
      return '';
    }
    assert.fail(`unsupported fake gh command: ${args.join(' ')}`);
  }

  return { issues, mutations, runGh };
}

const repository = 'kaizen-agents-org/verifier';

{
  const runner = createRunner([
    issue(1, 'OPEN', '2026-08-01T00:00:00Z'),
    issue(2, 'OPEN', '2026-08-02T00:00:00Z'),
  ]);
  await assert.rejects(
    reconcileScoutDuplicates({ repo: repository, issueNumbers: [1, 2], runGh: runner.runGh }),
    /explicit reconciliation authorization is required/,
  );
  assert.deepEqual(runner.mutations, []);
}

{
  const runner = createRunner([
    issue(198, 'OPEN', '2026-08-04T01:00:00Z'),
    issue(197, 'OPEN', '2026-08-04T01:00:00Z'),
    issue(196, 'CLOSED', '2026-08-03T01:00:00Z'),
  ]);
  const result = await reconcileScoutDuplicates({
    repo: repository,
    issueNumbers: [198, 196, 197],
    authorized: true,
    runGh: runner.runGh,
  });
  assert.equal(result.canonical, 197, 'open state wins, then equal timestamps use the lowest number');
  assert.deepEqual(result.closed, [198]);
  assert.deepEqual(result.linked, [196]);
  assert.equal(runner.issues.get(197).state, 'OPEN');
}

{
  const runner = createRunner([
    issue(20, 'CLOSED', '2026-08-02T00:00:00Z'),
    issue(10, 'CLOSED', '2026-08-01T00:00:00Z'),
  ]);
  const result = await reconcileScoutDuplicates({
    repo: repository,
    issueNumbers: [20, 10],
    authorized: true,
    runGh: runner.runGh,
  });
  assert.equal(result.canonical, 10);
  assert.equal(result.reopened, true);
  assert.equal(runner.issues.get(10).state, 'OPEN');
  assert.deepEqual(runner.mutations, ['reopen:10', 'comment:20']);
}

{
  const runner = createRunner([
    issue(10, 'OPEN', '2026-08-02T00:00:00Z'),
    issue(20, 'OPEN', '2026-08-01T00:00:00Z'),
  ]);
  const result = await reconcileScoutDuplicates({
    repo: repository,
    issueNumbers: [10, 20],
    authorized: true,
    runGh: runner.runGh,
  });
  assert.equal(result.canonical, 20, 'the earliest createdAt wins before issue number');
}

{
  const runner = createRunner([
    issue(197, 'CLOSED', '2026-08-01T00:00:00Z', [198]),
    issue(198, 'CLOSED', '2026-08-02T00:00:00Z', [197]),
  ]);
  await assert.rejects(
    reconcileScoutDuplicates({ repo: repository, issueNumbers: [197, 198], authorized: true, runGh: runner.runGh }),
    /duplicate cycle detected/,
  );
  assert.deepEqual(runner.mutations, [], 'cycle detection must precede every mutation');
}

{
  const runner = createRunner([
    issue(1, 'OPEN', '2026-08-01T00:00:00Z', [2]),
    issue(2, 'OPEN', '2026-08-02T00:00:00Z', [3]),
    issue(3, 'OPEN', '2026-08-03T00:00:00Z', [1]),
  ]);
  await assert.rejects(
    reconcileScoutDuplicates({ repo: repository, issueNumbers: [1, 2, 3], authorized: true, runGh: runner.runGh }),
    /duplicate cycle detected/,
  );
  assert.deepEqual(runner.mutations, [], 'transitive cycles must fail without mutation');
}

{
  const runner = createRunner([
    issue(1, 'OPEN', '2026-08-01T00:00:00Z'),
    issue(2, 'OPEN', '2026-08-02T00:00:00Z'),
  ]);
  let viewCount = 0;
  const driftingRunner = async (args) => {
    if (args[0] === 'issue' && args[1] === 'view') {
      viewCount += 1;
      if (viewCount === 3) runner.issues.get(1).state = 'CLOSED';
    }
    return runner.runGh(args);
  };
  await assert.rejects(
    reconcileScoutDuplicates({ repo: repository, issueNumbers: [1, 2], authorized: true, runGh: driftingRunner }),
    /canonical drift before reconciling/,
  );
  assert.deepEqual(runner.mutations, [], 'a fresh pre-close query must stop on canonical drift');
}

{
  const runner = createRunner([
    issue(1, 'OPEN', '2026-08-01T00:00:00Z'),
    issue(2, 'OPEN', '2026-08-02T00:00:00Z'),
  ]);
  const first = await reconcileScoutDuplicates({ repo: repository, issueNumbers: [2, 1], authorized: true, runGh: runner.runGh });
  const mutationCount = runner.mutations.length;
  const second = await reconcileScoutDuplicates({ repo: repository, issueNumbers: [1, 2], authorized: true, runGh: runner.runGh });
  assert.equal(first.canonical, 1);
  assert.equal(second.canonical, 1);
  assert.equal(runner.mutations.length, mutationCount, 'a second run must be idempotent');
}

{
  const runner = createRunner([
    issue(1, 'OPEN', '2026-08-01T00:00:00Z'),
    issue(2, 'OPEN', '2026-08-02T00:00:00Z'),
  ]);
  const [left, right] = await Promise.all([
    reconcileScoutDuplicates({ repo: repository, issueNumbers: [2, 1], authorized: true, runGh: runner.runGh }),
    reconcileScoutDuplicates({ repo: repository, issueNumbers: [1, 2], authorized: true, runGh: runner.runGh }),
  ]);
  assert.equal(left.canonical, 1);
  assert.equal(right.canonical, 1);
  assert.equal(runner.issues.get(1).state, 'OPEN');
  assert.equal(runner.issues.get(2).state, 'CLOSED');
  assert(!runner.issues.get(1).comments.some(({ body }) => /canonical=#2/.test(body)), 'race must not create a mutual close');
}

process.stdout.write('PASS: scout duplicate reconciliation is deterministic and fail-safe\n');
