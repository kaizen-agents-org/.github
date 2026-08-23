#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const markerPattern = /<!--\s*kaizen-scout-duplicate:\s*canonical=#(\d+)\s*-->/gi;
const duplicateCommentPattern = /(?:^|\n)\s*duplicate\s+of\s+#(\d+)\b/gi;
const reconciliationPattern = /<!--\s*kaizen-scout-reconciliation:\s*candidates=([0-9,]+);\s*canonical=#(\d+);\s*role=(canonical|duplicate)\s*-->/gi;

function fail(message) {
  throw new Error(message);
}

function validateTarget(repo, issueNumbers) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) {
    fail('--repo must be an explicit owner/repository');
  }
  if (issueNumbers.length < 2 || issueNumbers.some((number) => !Number.isInteger(number) || number < 1)) {
    fail('--issues must contain at least two comma-separated positive issue numbers');
  }
  if (new Set(issueNumbers).size !== issueNumbers.length) {
    fail('--issues must not contain duplicate issue numbers');
  }
}

function parseArgs(argv) {
  const options = { issues: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--repo') options.repo = argv[++index];
    else if (argument === '--issues') {
      options.issues = (argv[++index] ?? '').split(',').map(Number);
    } else if (argument === '--authorize-reconciliation') {
      options.authorized = true;
    } else if (argument === '--gh-bin') options.ghBin = argv[++index];
    else fail(`unknown argument: ${argument}`);
  }

  if (!options.authorized) fail('explicit --authorize-reconciliation is required');
  validateTarget(options.repo, options.issues);
  return options;
}

function candidateKey(issueNumbers) {
  return [...issueNumbers].sort((left, right) => left - right).join(',');
}

function reconciliationMarker(issueNumber, canonicalNumber, issueNumbers) {
  const role = issueNumber === canonicalNumber ? 'canonical' : 'duplicate';
  const marker = `<!-- kaizen-scout-reconciliation: candidates=${candidateKey(issueNumbers)}; canonical=#${canonicalNumber}; role=${role} -->`;
  return role === 'canonical'
    ? `${marker}\nCanonical issue for this explicitly authorized duplicate reconciliation.`
    : `${marker}\nDuplicate of #${canonicalNumber}.`;
}

function sources(issue) {
  return [issue.body ?? '', ...(issue.comments ?? []).map((comment) => comment.body ?? '')];
}

function reconciliationState(issue) {
  let state;
  sources(issue).forEach((text, sourceIndex) => {
    reconciliationPattern.lastIndex = 0;
    for (let match = reconciliationPattern.exec(text); match; match = reconciliationPattern.exec(text)) {
      state = {
        candidateKey: match[1],
        canonical: Number(match[2]),
        role: match[3],
        sourceIndex,
      };
    }
  });
  return state;
}

function rawRelationTargets(issue, afterSourceIndex = -1) {
  const targets = new Set();
  sources(issue).forEach((text, sourceIndex) => {
    if (sourceIndex <= afterSourceIndex) return;
    for (const pattern of [markerPattern, duplicateCommentPattern]) {
      pattern.lastIndex = 0;
      for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
        targets.add(Number(match[1]));
      }
    }
  });
  return targets;
}

function relationTargets(issue) {
  const state = reconciliationState(issue);
  if (!state) return rawRelationTargets(issue);
  if (rawRelationTargets(issue, state.sourceIndex).size > 0) {
    fail(`issue #${issue.number} has an unmanaged duplicate relation after its current reconciliation marker`);
  }
  return state.role === 'canonical' ? new Set() : new Set([state.canonical]);
}

function chooseCanonical(issues) {
  return [...issues].sort((left, right) => {
    const stateOrder = Number(left.state !== 'OPEN') - Number(right.state !== 'OPEN');
    if (stateOrder !== 0) return stateOrder;
    const createdOrder = Date.parse(left.createdAt) - Date.parse(right.createdAt);
    if (createdOrder !== 0) return createdOrder;
    return left.number - right.number;
  })[0];
}

function assertNoCycle(issues) {
  const candidates = new Set(issues.map((issue) => issue.number));
  const graph = new Map(issues.map((issue) => [
    issue.number,
    [...relationTargets(issue)].filter((target) => candidates.has(target)),
  ]));
  const visiting = new Set();
  const visited = new Set();

  function visit(number) {
    if (visiting.has(number)) fail(`duplicate cycle detected at #${number}`);
    if (visited.has(number)) return;
    visiting.add(number);
    for (const target of graph.get(number) ?? []) visit(target);
    visiting.delete(number);
    visited.add(number);
  }

  for (const number of candidates) visit(number);
}

function assertOneWayRelations(issues, canonicalNumber) {
  for (const issue of issues) {
    const targets = [...relationTargets(issue)];
    if (issue.number === canonicalNumber && targets.length > 0) {
      fail(`canonical issue #${canonicalNumber} already points to a duplicate`);
    }
    if (issue.number !== canonicalNumber && targets.some((target) => target !== canonicalNumber)) {
      fail(`duplicate issue #${issue.number} points away from canonical #${canonicalNumber}`);
    }
  }
}

function assertRepairableRelations(issues, canonicalNumber, issueNumbers) {
  const candidates = new Set(issueNumbers);
  const expectedKey = candidateKey(issueNumbers);
  for (const issue of issues) {
    const outsideTarget = [...rawRelationTargets(issue)].find((target) => !candidates.has(target));
    if (outsideTarget !== undefined) {
      fail(`issue #${issue.number} points outside the authorized candidate set to #${outsideTarget}`);
    }
    const state = reconciliationState(issue);
    if (!state) continue;
    const expectedRole = issue.number === canonicalNumber ? 'canonical' : 'duplicate';
    if (state.candidateKey !== expectedKey || state.canonical !== canonicalNumber || state.role !== expectedRole) {
      fail(`issue #${issue.number} has a conflicting reconciliation marker`);
    }
    if (rawRelationTargets(issue, state.sourceIndex).size > 0) {
      fail(`issue #${issue.number} has an unmanaged duplicate relation after its current reconciliation marker`);
    }
  }
}

async function defaultRunGh(args, ghBin = process.env.KAIZEN_SCOUT_GH_BIN ?? 'gh') {
  const { stdout } = await execFileAsync(ghBin, args, { encoding: 'utf8' });
  return stdout;
}

export async function reconcileScoutDuplicates({ repo, issueNumbers, authorized = false, runGh = defaultRunGh }) {
  if (!authorized) fail('explicit reconciliation authorization is required');
  validateTarget(repo, issueNumbers);
  async function fetchIssue(number) {
    const output = await runGh([
      'issue', 'view', String(number), '--repo', repo,
      '--json', 'number,state,createdAt,body',
    ]);
    const issue = JSON.parse(output);
    const commentOutput = await runGh([
      'api', '--paginate', '--slurp', `repos/${repo}/issues/${number}/comments`,
    ]);
    const commentPages = JSON.parse(commentOutput);
    issue.comments = commentPages.flat().map((comment) => ({ body: comment.body ?? '' }));
    if (issue.number !== number || !['OPEN', 'CLOSED'].includes(issue.state) || Number.isNaN(Date.parse(issue.createdAt))) {
      fail(`invalid current state returned for #${number}`);
    }
    return issue;
  }

  async function fetchAll() {
    const issues = [];
    for (const number of issueNumbers) issues.push(await fetchIssue(number));
    return issues;
  }

  let current = await fetchAll();
  let canonical = chooseCanonical(current);
  assertRepairableRelations(current, canonical.number, issueNumbers);
  const result = { canonical: canonical.number, reopened: false, marked: [], closed: [], skipped: [] };

  if (current.every((issue) => issue.state === 'CLOSED')) {
    await runGh(['issue', 'reopen', String(canonical.number), '--repo', repo]);
    result.reopened = true;
    current = await fetchAll();
    canonical = chooseCanonical(current);
    if (canonical.number !== result.canonical || canonical.state !== 'OPEN') {
      fail(`canonical drift after reopen: expected #${result.canonical}`);
    }
    assertRepairableRelations(current, canonical.number, issueNumbers);
  }

  const markerOrder = [
    result.canonical,
    ...issueNumbers.filter((number) => number !== result.canonical).sort((left, right) => left - right),
  ];
  for (const issueNumber of markerOrder) {
    current = await fetchAll();
    canonical = chooseCanonical(current);
    if (canonical.number !== result.canonical || canonical.state !== 'OPEN') {
      fail(`canonical drift before writing reconciliation state for #${issueNumber}`);
    }
    assertRepairableRelations(current, canonical.number, issueNumbers);
    const issue = current.find((candidate) => candidate.number === issueNumber);
    if (reconciliationState(issue)) continue;
    await runGh([
      'issue', 'comment', String(issueNumber), '--repo', repo,
      '--body', reconciliationMarker(issueNumber, canonical.number, issueNumbers),
    ]);
    result.marked.push(issueNumber);
  }

  current = await fetchAll();
  assertNoCycle(current);
  assertOneWayRelations(current, result.canonical);

  for (const duplicateNumber of issueNumbers.filter((number) => number !== result.canonical)) {
    // This fetch/recompute is intentionally adjacent to each mutation. Never
    // close based on the initial snapshot.
    current = await fetchAll();
    assertNoCycle(current);
    canonical = chooseCanonical(current);
    if (canonical.number !== result.canonical || canonical.state !== 'OPEN') {
      fail(`canonical drift before reconciling #${duplicateNumber}`);
    }
    assertOneWayRelations(current, canonical.number);

    const duplicate = current.find((issue) => issue.number === duplicateNumber);
    const targets = relationTargets(duplicate);
    const pointsToCanonical = targets.has(canonical.number);
    if (duplicate.state === 'CLOSED') {
      if (!pointsToCanonical) fail(`closed duplicate #${duplicateNumber} lacks current canonical state`);
      result.skipped.push(duplicateNumber);
      continue;
    }

    const closeArgs = [
      'issue', 'close', String(duplicateNumber), '--repo', repo,
      '--duplicate-of', String(canonical.number),
    ];
    if (!pointsToCanonical) fail(`open duplicate #${duplicateNumber} lacks current canonical state`);
    await runGh(closeArgs);
    result.closed.push(duplicateNumber);
  }

  current = await fetchAll();
  assertNoCycle(current);
  canonical = chooseCanonical(current);
  assertOneWayRelations(current, result.canonical);
  const finalCanonical = current.find((issue) => issue.number === result.canonical);
  if (canonical.number !== result.canonical || finalCanonical.state !== 'OPEN') {
    fail(`reconciliation did not preserve open canonical #${result.canonical}`);
  }
  for (const issue of current.filter((candidate) => candidate.number !== result.canonical)) {
    if (issue.state !== 'CLOSED' || !relationTargets(issue).has(result.canonical)) {
      fail(`duplicate #${issue.number} was not closed one-way to canonical #${result.canonical}`);
    }
  }
  return result;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const runGh = (args) => defaultRunGh(args, options.ghBin);
  const result = await reconcileScoutDuplicates({
    repo: options.repo,
    issueNumbers: options.issues,
    authorized: options.authorized,
    runGh,
  });
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`scout duplicate reconciliation failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
