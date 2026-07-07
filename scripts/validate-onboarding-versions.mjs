#!/usr/bin/env node
import fs from "node:fs";

const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error("usage: validate-onboarding-versions.mjs <versions.json>");
  process.exit(1);
}

const expectedComponents = ["kaizen-loop", "builder-agent", "verifier"];
const raw = fs.readFileSync(manifestPath, "utf8");
let manifest;

try {
  manifest = JSON.parse(raw);
} catch (error) {
  console.error(`invalid JSON: ${error.message}`);
  process.exit(1);
}

const keys = Object.keys(manifest).sort();
const expectedKeys = [...expectedComponents].sort();

if (JSON.stringify(keys) !== JSON.stringify(expectedKeys)) {
  console.error(`expected keys ${expectedKeys.join(", ")}, got ${keys.join(", ")}`);
  process.exit(1);
}

for (const component of expectedComponents) {
  const version = manifest[component];
  if (typeof version !== "string" || !/^v0\.\d+\.\d+$/.test(version)) {
    console.error(`${component} must be pinned to a v0.x.y tag`);
    process.exit(1);
  }
}
