#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const [workflowPath, kaizenLoopRoot] = process.argv.slice(2);
if (!workflowPath || !kaizenLoopRoot) {
  console.error('usage: check-workflow-read-only-permissions.mjs <workflow> <kaizen-loop-root>');
  process.exit(2);
}

const requireFromKaizen = createRequire(path.join(path.resolve(kaizenLoopRoot), 'package.json'));
const { parse } = requireFromKaizen('yaml');
const workflow = parse(fs.readFileSync(workflowPath, 'utf8'));
const workflowPermissions = workflow?.permissions;
if (
  !workflowPermissions ||
  typeof workflowPermissions !== 'object' ||
  Array.isArray(workflowPermissions) ||
  workflowPermissions.contents !== 'read'
) {
  console.error('workflow permissions must explicitly declare contents: read');
  process.exit(1);
}
const permissionBlocks = [
  ['workflow', workflowPermissions],
  ...Object.entries(workflow?.jobs ?? {}).map(([name, job]) => [`job ${name}`, job?.permissions])
];

for (const [scope, permissions] of permissionBlocks) {
  if (permissions === 'write-all') {
    console.error(`${scope} permissions must not use write-all`);
    process.exit(1);
  }
  if (!permissions || typeof permissions !== 'object' || Array.isArray(permissions)) continue;
  for (const [name, access] of Object.entries(permissions)) {
    if (access === 'write') {
      console.error(`${scope} permission ${name} must not use write access`);
      process.exit(1);
    }
  }
}
