#!/usr/bin/env node

import fs from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function isSuccessfulSmokeArtifact(value) {
  const pullRequest = value?.pullRequest;
  return value?.version === 1 &&
    value?.kind === 'sandbox-e2e-smoke' &&
    value?.result === 'success' &&
    pullRequest !== null &&
    typeof pullRequest === 'object' &&
    Number.isInteger(pullRequest.number) &&
    pullRequest.number > 0 &&
    typeof pullRequest.url === 'string' &&
    pullRequest.url.length > 0 &&
    pullRequest.isDraft === false &&
    pullRequest.issueLinkRecognized === true;
}

export async function hasSuccessfulSmokeArtifact(directory) {
  let entries;
  try {
    entries = await fs.readdir(directory, { withFileTypes: true });
  } catch {
    return false;
  }
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith('.json')) continue;
    try {
      const value = JSON.parse(await fs.readFile(path.join(directory, entry.name), 'utf8'));
      if (isSuccessfulSmokeArtifact(value)) return true;
    } catch {
      // A malformed historical artifact does not hide a valid one.
    }
  }
  return false;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.exit(await hasSuccessfulSmokeArtifact(process.argv[2] ?? 'docs/smoke-runs') ? 0 : 1);
}
