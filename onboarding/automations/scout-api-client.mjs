#!/usr/bin/env node

import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { hostname, tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const SCHEMA_FILE = new URL('./scout.findings.schema.json', import.meta.url);
const SCHEMA = JSON.parse(fs.readFileSync(SCHEMA_FILE, 'utf8'));

function fail(message) {
  throw new Error(message);
}

function repositoryName(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9._-]+$/.test(value)) {
    fail('target must be an explicit owner/repository');
  }
  return value;
}

function configuredLabels(value) {
  if (!Array.isArray(value) || value.length === 0 || value.some((label) =>
    typeof label !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9:._ -]*$/.test(label))) {
    fail('labels must be a non-empty array of valid label names');
  }
  return [...new Set(value)];
}

function intakeLabel(config) {
  if (typeof config.intakeLabel !== 'string' || !config.intakeLabel || !config.labels.includes(config.intakeLabel)) {
    fail('intakeLabel must be explicitly configured and included in labels');
  }
  return config.intakeLabel;
}

function limits(config) {
  const { openIssueLimit, wipLimit, creationLimit } = config;
  if (![openIssueLimit, wipLimit].every((value) => Number.isInteger(value) && value >= 1 && value <= 4) ||
      !Number.isInteger(creationLimit) || creationLimit < 1 || creationLimit > 2) {
    fail('limits must be openIssueLimit/wipLimit 1..4 and creationLimit 1..2');
  }
}

function normalize(value) {
  return String(value ?? '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function findingMatches(finding, item) {
  const wanted = normalize(finding.title);
  const haystack = normalize(`${item.title ?? ''} ${item.body ?? ''}`);
  return wanted.length >= 8 && (haystack === wanted || haystack.includes(wanted) || wanted.includes(haystack));
}

function assertString(value, name, min, max) {
  if (typeof value !== 'string' || value.length < min || value.length > max) {
    fail(`${name} must be a string of length ${min}..${max}`);
  }
}

export function validateFindings(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('findings response root must be an object');
  const allowedRoot = new Set(['findings', 'skipped', 'notes']);
  if (Object.keys(value).some((key) => !allowedRoot.has(key))) fail('findings response has unknown properties');
  if (!Array.isArray(value.findings) || value.findings.length > SCHEMA.properties.findings.maxItems) {
    fail('findings must be an array with at most 10 items');
  }
  for (const finding of value.findings) {
    if (!finding || typeof finding !== 'object' || Array.isArray(finding)) fail('finding must be an object');
    const allowed = new Set(['title', 'body', 'evidence', 'confidence', 'area']);
    if (Object.keys(finding).some((key) => !allowed.has(key))) fail('finding has unknown properties');
    assertString(finding.title, 'finding.title', 8, 120);
    assertString(finding.body, 'finding.body', 40, 8000);
    assertString(finding.evidence, 'finding.evidence', 8, 2000);
    if (finding.confidence !== undefined && !['high', 'medium', 'low'].includes(finding.confidence)) {
      fail('finding.confidence is invalid');
    }
    if (finding.area !== undefined) assertString(finding.area, 'finding.area', 0, 60);
  }
  if (value.skipped !== undefined) {
    if (!Array.isArray(value.skipped) || value.skipped.length > 20) fail('skipped must be an array with at most 20 items');
    for (const skipped of value.skipped) {
      if (!skipped || typeof skipped !== 'object' || Array.isArray(skipped)) fail('skipped item must be an object');
      if (Object.keys(skipped).some((key) => !['title', 'reason'].includes(key))) fail('skipped item has unknown properties');
      if (skipped.title !== undefined) assertString(skipped.title, 'skipped.title', 0, 120);
      assertString(skipped.reason, 'skipped.reason', 4, 500);
    }
  }
  if (value.notes !== undefined) assertString(value.notes, 'notes', 0, 2000);
  return value;
}

function issueBody(body, evidence) {
  return `${body}\n\n## Evidence\n${evidence}\n\n## PR linkage requirement\nThe implementation PR must target this repository's default branch, include a GitHub closing keyword such as \`Closes #<this issue number>\`, and verify \`closingIssuesReferences\` before reporting the PR ready.`;
}

const LOCK_WAIT_MS = 30000;
const LOCK_STALE_MS = 120000;
const LOCK_RETRY_MS = 50;
const DEFAULT_CONTEXT_BYTE_BUDGET = 400000;

function defaultLockPath(target) {
  return join(tmpdir(), `scout-api-client-${target.replace(/[^A-Za-z0-9._-]+/g, '_')}.lock`);
}

function ownerIsAlive(owner) {
  if (!Number.isInteger(owner?.pid)) return false;
  // Claims created before hostname was added may still have a live local owner
  // during an in-place upgrade, so they are intentionally unreclaimable.
  if (owner.hostname === undefined) return true;
  if (typeof owner.hostname !== 'string') return false;
  // PIDs are host-local. A foreign-host claim fails closed rather than being
  // reclaimed based on an unrelated local process.
  if (owner.hostname !== hostname()) return true;
  try {
    process.kill(owner.pid, 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}

function readClaim(path) {
  try { return fs.readFileSync(join(path, 'claim.json'), 'utf8'); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

function reclaimLock(lockPath, expectedClaim) {
  const reclaimPath = `${lockPath}.reclaim.${randomUUID()}`;
  try {
    fs.renameSync(lockPath, reclaimPath);
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'EEXIST') return false;
    throw error;
  }
  if (readClaim(reclaimPath) !== expectedClaim) {
    try { fs.renameSync(reclaimPath, lockPath); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    return false;
  }
  try { fs.rmSync(reclaimPath, { recursive: true }); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  return true;
}

function removeStaleReclaimDirectories(lockPath, staleMs) {
  const parent = dirname(lockPath);
  const prefix = `${lockPath.split('/').at(-1)}.reclaim.`;
  for (const entry of fs.readdirSync(parent).filter((name) => name.startsWith(prefix))) {
    const reclaimPath = join(parent, entry);
    try {
      const expectedClaim = readClaim(reclaimPath);
      let owner = null;
      if (expectedClaim !== null) {
        try { owner = JSON.parse(expectedClaim); } catch { owner = null; }
      }
      const stat = fs.statSync(expectedClaim === null ? reclaimPath : join(reclaimPath, 'claim.json'));
      if ((expectedClaim === null || !ownerIsAlive(owner)) && Date.now() - stat.mtimeMs >= staleMs) {
        fs.rmSync(reclaimPath, { recursive: true });
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}

export async function acquireFileLock(lockPath, waitMs = LOCK_WAIT_MS, staleMs = LOCK_STALE_MS) {
  const started = Date.now();
  fs.mkdirSync(dirname(lockPath), { recursive: true, mode: 0o700 });
  const base = lockPath.split('/').at(-1);
  while (true) {
    removeStaleReclaimDirectories(lockPath, staleMs);
    if (fs.readdirSync(dirname(lockPath)).some((entry) => entry.startsWith(`${base}.reclaim.`))) {
      if (Date.now() - started >= waitMs) fail(`single-flight lock timeout: ${lockPath}`);
      await new Promise((resolvePromise) => setTimeout(resolvePromise, LOCK_RETRY_MS));
      continue;
    }
    try {
      fs.mkdirSync(lockPath, 0o700);
      const claim = { pid: process.pid, hostname: hostname(), token: randomUUID(), startedAt: Date.now() };
      const serializedClaim = JSON.stringify(claim);
      fs.writeFileSync(join(lockPath, 'claim.json'), serializedClaim, { mode: 0o600 });
      return () => {
        reclaimLock(lockPath, serializedClaim);
      };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let expectedClaim = null;
      let stale = false;
      try {
        const claimPath = join(lockPath, 'claim.json');
        const stat = fs.statSync(claimPath);
        let owner;
        expectedClaim = fs.readFileSync(claimPath, 'utf8');
        try { owner = JSON.parse(expectedClaim); } catch { owner = null; }
        stale = !ownerIsAlive(owner) && Date.now() - stat.mtimeMs >= staleMs;
      } catch (statError) {
        if (statError.code !== 'ENOENT') throw statError;
        try {
          stale = Date.now() - fs.statSync(lockPath).mtimeMs >= staleMs;
          expectedClaim = null;
        } catch (directoryError) {
          if (directoryError.code !== 'ENOENT') throw directoryError;
        }
      }
      if (stale && reclaimLock(lockPath, expectedClaim)) continue;
      if (Date.now() - started >= waitMs) fail(`single-flight lock timeout: ${lockPath}`);
      await new Promise((resolvePromise) => setTimeout(resolvePromise, LOCK_RETRY_MS));
    }
  }
}

async function withSingleFlight(config, target, action, dependencies) {
  if (dependencies.singleFlight) return dependencies.singleFlight(target, action);
  const release = await acquireFileLock(config.lockPath ?? defaultLockPath(target), config.lockWaitMs, config.lockStaleMs);
  try { return await action(); } finally { release(); }
}

function contextBudget(value) {
  const budget = value ?? DEFAULT_CONTEXT_BYTE_BUDGET;
  if (!Number.isInteger(budget) || budget < 10000 || budget > 2000000) {
    fail('contextByteBudget must be an integer from 10000 to 2000000');
  }
  return budget;
}

export function boundedContext(entries, maxBytes) {
  let used = 0;
  const content = [];
  for (const entry of entries) {
    const separator = content.length ? '\n\n' : '';
    const separatorBytes = Buffer.byteLength(separator);
    if (used + separatorBytes >= maxBytes) break;
    const bytes = Buffer.from(entry, 'utf8');
    const remaining = maxBytes - used - separatorBytes;
    let selected = bytes.subarray(0, Math.min(bytes.length, remaining));
    while (selected.length > 0 && Buffer.byteLength(selected.toString('utf8')) > remaining) {
      selected = selected.subarray(0, -1);
    }
    content.push(`${separator}${selected.toString('utf8')}`);
    used += separatorBytes + Buffer.byteLength(selected.toString('utf8'));
  }
  return content.join('');
}

export async function runScout(config, dependencies) {
  repositoryName(config.target);
  configuredLabels(config.labels);
  const configuredIntakeLabel = intakeLabel(config);
  limits(config);
  const maxContextBytes = contextBudget(config.contextByteBudget);
  if (typeof config.model?.baseUrl !== 'string' || !config.model.baseUrl.startsWith('http')) fail('model.baseUrl is required');
  if (typeof config.model?.name !== 'string' || !config.model.name) fail('model.name is required');
  const { github, model } = dependencies;
  const existing = await github.openState(config.target, configuredIntakeLabel);
  if (existing.openIssues.length >= config.openIssueLimit) return { filed: [], skipped: [{ reason: 'open issue limit reached' }] };
  if (existing.openPullRequests.length >= config.wipLimit) return { filed: [], skipped: [{ reason: 'open pull request WIP limit reached' }] };
  const labelsVerified = await github.verifyLabels(config.target, config.labels);
  if (!labelsVerified) return { filed: [], skipped: [{ reason: 'configured label is missing' }] };
  const labels = config.labels;
  const context = await github.defaultBranchContext(config.target, { maxBytes: maxContextBytes });
  const raw = await model({
    model: config.model.name,
    schema: SCHEMA,
    prompt: config.prompt ?? 'Find bounded, evidence-backed repository improvements.',
    repository: config.target,
    defaultBranch: context.defaultBranch,
    content: context.content
  });
  const response = validateFindings(raw);
  const filed = [];
  const skipped = [...(response.skipped ?? [])];
  await withSingleFlight(config, config.target, async () => {
    for (const finding of response.findings) {
      if (filed.length >= config.creationLimit) {
        skipped.push({ title: finding.title, reason: 'creation limit reached' });
        continue;
      }
      const current = await github.openState(config.target, configuredIntakeLabel);
      if (current.openIssues.length >= config.openIssueLimit) {
        skipped.push({ title: finding.title, reason: 'open issue limit reached before creation' });
        continue;
      }
      if (current.openPullRequests.length >= config.wipLimit) {
        skipped.push({ title: finding.title, reason: 'open pull request WIP limit reached before creation' });
        continue;
      }
      if ([...current.duplicateIssues, ...current.openPullRequests, ...filed].some((item) => findingMatches(finding, item))) {
        skipped.push({ title: finding.title, reason: 'duplicate open issue or pull request' });
        continue;
      }
      const url = await github.createIssue(config.target, `[scout] ${finding.title}`, issueBody(finding.body, finding.evidence), labels);
      filed.push({ title: finding.title, url });
    }
  }, dependencies);
  return { filed, skipped, notes: response.notes };
}

function ghJson(target, endpoint) {
  try {
    return JSON.parse(execFileSync('gh', ['api', `repos/${target}/${endpoint}`], { encoding: 'utf8' }));
  } catch (error) {
    fail(`GitHub query failed: ${error.stderr?.trim() || error.message}`);
  }
}

export function flattenPaginated(pages) {
  return pages.flatMap((page) => Array.isArray(page) ? page : page.items ?? []);
}

function ghJsonPaginated(target, endpoint) {
  try {
    const pages = JSON.parse(execFileSync('gh', ['api', '--paginate', '--slurp', `repos/${target}/${endpoint}`], { encoding: 'utf8' }));
    return flattenPaginated(pages);
  } catch (error) {
    fail(`Paginated GitHub query failed: ${error.stderr?.trim() || error.message}`);
  }
}

function makeGithub() {
  return {
    async openState(target, intakeLabel) {
      const issues = ghJsonPaginated(target, `issues?state=open&labels=${encodeURIComponent(intakeLabel)}&per_page=100`)
        .filter((item) => !item.pull_request);
      const duplicateIssues = ghJsonPaginated(target, 'issues?state=open&per_page=100')
        .filter((item) => !item.pull_request);
      const prs = ghJson(target, 'pulls?state=open&per_page=100');
      return { openIssues: issues, duplicateIssues, openPullRequests: prs };
    },
    async verifyLabels(target, labels) {
      const available = ghJsonPaginated(target, 'labels?per_page=100').map((label) => label.name);
      return labels.every((label) => available.includes(label));
    },
    async defaultBranchContext(target, options = {}) {
      const repository = ghJson(target, '');
      const branch = repository.default_branch;
      if (!branch) fail('GitHub did not return a default branch');
      const tree = ghJson(target, `git/trees/${encodeURIComponent(branch)}?recursive=1`).tree ?? [];
      const textEntries = tree.filter((entry) => entry.type === 'blob' && entry.size <= 100000)
        .filter((entry) => /\.(md|mdx|json|ya?ml|sh|mjs|js|ts|py|toml|txt)$/i.test(entry.path))
        .sort((a, b) => a.path.localeCompare(b.path)).slice(0, 40);
      const entries = [];
      for (const entry of textEntries) {
        const blob = ghJson(target, `git/blobs/${entry.sha}`);
        entries.push(`--- ${entry.path} ---\n${Buffer.from(blob.content, 'base64').toString('utf8')}`);
      }
      return { defaultBranch: branch, content: boundedContext(entries, options.maxBytes ?? DEFAULT_CONTEXT_BYTE_BUDGET) };
    },
    async createIssue(target, title, body, labels) {
      const args = ['issue', 'create', '--repo', target, '--title', title, '--body', body];
      for (const label of labels) args.push('--label', label);
      try {
        return execFileSync('gh', args, { encoding: 'utf8' }).trim();
      } catch (error) {
        fail(`GitHub issue creation failed: ${error.stderr?.trim() || error.message}`);
      }
    }
  };
}

export async function openAiModel(config) {
  const endpoint = `${config.baseUrl.replace(/\/$/, '')}/chat/completions`;
  const request = {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(config.apiKey ? { authorization: `Bearer ${config.apiKey}` } : {}) },
    body: JSON.stringify({
      model: config.name,
      messages: [
        { role: 'system', content: `Return only valid JSON matching this scout findings schema. Do not use Markdown or prose.\n${JSON.stringify(SCHEMA)}` },
        { role: 'user', content: config.request }
      ],
      ...(config.constrainedDecoding === false ? {} : {
        response_format: { type: 'json_schema', json_schema: { name: 'scout_findings', strict: true, schema: SCHEMA } }
      })
    })
  };
  let response = await fetch(endpoint, request);
  if (!response.ok && config.constrainedDecoding !== false && [400, 404, 422].includes(response.status)) {
    const body = JSON.parse(request.body);
    delete body.response_format;
    response = await fetch(endpoint, { ...request, body: JSON.stringify(body) });
  }
  if (!response.ok) fail(`model request failed with HTTP ${response.status}`);
  const payload = await response.json();
  const text = payload?.choices?.[0]?.message?.content;
  if (typeof text !== 'string') fail('model response did not contain message content');
  try { return JSON.parse(text); } catch { fail('model response was not valid JSON'); }
}

async function main() {
  const configPath = process.argv[2];
  if (!configPath) fail('usage: scout-api-client.mjs CONFIG.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  config.model = { ...config.model, apiKey: config.model?.apiKey ?? process.env.SCOUT_MODEL_API_KEY };
  const result = await runScout(config, { github: makeGithub(), model: (request) => openAiModel({
    ...config.model,
    request: `${request.prompt}\n\nTarget: ${request.repository}\nDefault branch: ${request.defaultBranch}\n\nRepository content:\n${request.content}`
  }) });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => { console.error(`error: ${error.message}`); process.exitCode = 1; });
}
