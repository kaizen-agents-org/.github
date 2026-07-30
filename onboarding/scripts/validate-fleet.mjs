#!/usr/bin/env node

import fs from 'node:fs/promises';

const OWNER_REPOSITORY = /^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9._-]+$/;
const SLUG = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const CHECKOUT = /^[A-Za-z0-9.][A-Za-z0-9._-]*$/;
const EXACT_ENTRY_KEYS = [
  'localCheckout',
  'monitor',
  'projectSlug',
  'repository',
  'weeklyReadiness'
];

function fail(message) {
  console.error(`fleet validation failed: ${message}`);
  process.exit(1);
}

const file = process.argv[2];
if (!file || process.argv.length !== 3) {
  fail('usage: validate-fleet.mjs <fleet.json>');
}

let fleet;
try {
  fleet = JSON.parse(await fs.readFile(file, 'utf8'));
} catch (error) {
  fail(`cannot read valid JSON from ${file}: ${error.message}`);
}

if (!fleet || typeof fleet !== 'object' || Array.isArray(fleet)) {
  fail('the root must be an object');
}
if (JSON.stringify(Object.keys(fleet).sort()) !== JSON.stringify(['repositories', 'version'])) {
  fail('the root must contain exactly version and repositories');
}
if (fleet.version !== 1) {
  fail('version must be 1');
}
if (!Array.isArray(fleet.repositories) || fleet.repositories.length === 0) {
  fail('repositories must be a non-empty array');
}

const seen = {
  localCheckout: new Set(),
  projectSlug: new Set(),
  repository: new Set()
};

for (const [index, entry] of fleet.repositories.entries()) {
  const location = `repositories[${index}]`;
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    fail(`${location} must be an object`);
  }
  if (JSON.stringify(Object.keys(entry).sort()) !== JSON.stringify(EXACT_ENTRY_KEYS)) {
    fail(`${location} must contain exactly ${EXACT_ENTRY_KEYS.join(', ')}`);
  }
  if (!OWNER_REPOSITORY.test(entry.repository)) {
    fail(`${location}.repository must be an explicit owner/repo`);
  }
  if (!SLUG.test(entry.projectSlug)) {
    fail(`${location}.projectSlug must be a non-empty slug`);
  }
  if (!CHECKOUT.test(entry.localCheckout) || entry.localCheckout === '.' || entry.localCheckout === '..') {
    fail(`${location}.localCheckout must be one repository directory name`);
  }
  if (typeof entry.monitor !== 'boolean' || typeof entry.weeklyReadiness !== 'boolean') {
    fail(`${location} monitor and weeklyReadiness must be booleans`);
  }
  if (!entry.monitor && !entry.weeklyReadiness) {
    fail(`${location} must enable at least one read-only fleet consumer`);
  }

  for (const key of Object.keys(seen)) {
    const identity = key === 'repository' ? entry[key].toLowerCase() : entry[key];
    if (seen[key].has(identity)) {
      fail(`${key} is duplicated: ${entry[key]}`);
    }
    seen[key].add(identity);
  }
}

console.log(`PASS: fleet registry is valid (${fleet.repositories.length} repositories)`);
