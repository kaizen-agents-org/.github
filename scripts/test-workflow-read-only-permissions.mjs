#!/usr/bin/env node

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const [workflowPath, kaizenLoopRoot] = process.argv.slice(2);
if (!workflowPath || !kaizenLoopRoot) {
  console.error('usage: test-workflow-read-only-permissions.mjs <workflow> <kaizen-loop-root>');
  process.exit(2);
}

const requireFromKaizen = createRequire(path.join(path.resolve(kaizenLoopRoot), 'package.json'));
const { parse, stringify } = requireFromKaizen('yaml');
const checkerPath = path.join(path.dirname(fileURLToPath(import.meta.url)), 'check-workflow-read-only-permissions.mjs');
const source = parse(fs.readFileSync(workflowPath, 'utf8'));
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'workflow-permissions-contract-'));

const mutations = [
  ['missing', (workflow) => { delete workflow.permissions; }],
  ['scalar', (workflow) => { workflow.permissions = 'read'; }],
  ['array', (workflow) => { workflow.permissions = []; }],
  ['write', (workflow) => { workflow.permissions = { contents: 'write' }; }]
];

try {
  for (const [name, mutate] of mutations) {
    const workflow = structuredClone(source);
    mutate(workflow);
    const mutationPath = path.join(tempDir, `${name}.yml`);
    const misleadingComment = name === 'missing' ? '# contents: read\n' : '';
    fs.writeFileSync(mutationPath, misleadingComment + stringify(workflow));
    const result = spawnSync(process.execPath, [checkerPath, mutationPath, kaizenLoopRoot], {
      encoding: 'utf8'
    });
    assert.equal(result.error, undefined, `${name} checker invocation must start`);
    assert.notEqual(result.status, null, `${name} checker invocation must exit normally`);
    assert.notEqual(result.status, 0, `${name} workflow permissions mutation must be rejected`);
  }
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}
