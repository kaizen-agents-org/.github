#!/usr/bin/env node

import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
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

export async function runScout(config, dependencies) {
  repositoryName(config.target);
  configuredLabels(config.labels);
  limits(config);
  if (typeof config.model?.baseUrl !== 'string' || !config.model.baseUrl.startsWith('http')) fail('model.baseUrl is required');
  if (typeof config.model?.name !== 'string' || !config.model.name) fail('model.name is required');
  const { github, model } = dependencies;
  const existing = await github.openState(config.target, config.labels[0]);
  if (existing.openIssues.length >= config.openIssueLimit) return { filed: [], skipped: [{ reason: 'open issue limit reached' }] };
  if (existing.openPullRequests.length >= config.wipLimit) return { filed: [], skipped: [{ reason: 'open pull request WIP limit reached' }] };
  const labelsVerified = await github.verifyLabels(config.target, config.labels);
  if (!labelsVerified) return { filed: [], skipped: [{ reason: 'configured label is missing' }] };
  const labels = config.labels;
  const context = await github.defaultBranchContext(config.target);
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
  for (const finding of response.findings) {
    if (filed.length >= config.creationLimit) {
      skipped.push({ title: finding.title, reason: 'creation limit reached' });
      continue;
    }
    const current = await github.openState(config.target, config.labels[0]);
    if (current.openIssues.length >= config.openIssueLimit) {
      skipped.push({ title: finding.title, reason: 'open issue limit reached before creation' });
      continue;
    }
    if ([...current.duplicateIssues, ...current.openPullRequests, ...filed].some((item) => findingMatches(finding, item))) {
      skipped.push({ title: finding.title, reason: 'duplicate open issue or pull request' });
      continue;
    }
    const url = await github.createIssue(config.target, `[scout] ${finding.title}`, issueBody(finding.body, finding.evidence), labels);
    filed.push({ title: finding.title, url });
  }
  return { filed, skipped, notes: response.notes };
}

function ghJson(target, endpoint) {
  try {
    return JSON.parse(execFileSync('gh', ['api', `repos/${target}/${endpoint}`], { encoding: 'utf8' }));
  } catch (error) {
    fail(`GitHub query failed: ${error.stderr?.trim() || error.message}`);
  }
}

function makeGithub() {
  return {
    async openState(target, intakeLabel) {
      const issues = ghJson(target, `issues?state=open&labels=${encodeURIComponent(intakeLabel)}&per_page=100`)
        .filter((item) => !item.pull_request);
      const duplicateIssues = ghJson(target, 'issues?state=open&per_page=100')
        .filter((item) => !item.pull_request);
      const prs = ghJson(target, 'pulls?state=open&per_page=100');
      return { openIssues: issues, duplicateIssues, openPullRequests: prs };
    },
    async verifyLabels(target, labels) {
      const available = ghJson(target, 'labels?per_page=100').map((label) => label.name);
      return labels.every((label) => available.includes(label));
    },
    async defaultBranchContext(target) {
      const repository = ghJson(target, '');
      const branch = repository.default_branch;
      if (!branch) fail('GitHub did not return a default branch');
      const tree = ghJson(target, `git/trees/${encodeURIComponent(branch)}?recursive=1`).tree ?? [];
      const textEntries = tree.filter((entry) => entry.type === 'blob' && entry.size <= 100000)
        .filter((entry) => /\.(md|mdx|json|ya?ml|sh|mjs|js|ts|py|toml|txt)$/i.test(entry.path)).slice(0, 40);
      const content = [];
      for (const entry of textEntries) {
        const blob = ghJson(target, `git/blobs/${entry.sha}`);
        content.push(`--- ${entry.path} ---\n${Buffer.from(blob.content, 'base64').toString('utf8')}`);
      }
      return { defaultBranch: branch, content: content.join('\n\n') };
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

async function openAiModel(config) {
  const endpoint = `${config.baseUrl.replace(/\/$/, '')}/chat/completions`;
  const request = {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(config.apiKey ? { authorization: `Bearer ${config.apiKey}` } : {}) },
    body: JSON.stringify({
      model: config.name,
      messages: [{ role: 'user', content: config.request }],
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
