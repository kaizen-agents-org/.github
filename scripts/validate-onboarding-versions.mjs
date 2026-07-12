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

const componentKeyCounts = new Map(expectedComponents.map((component) => [component, 0]));
let depth = 0;

for (let index = 0; index < raw.length; index += 1) {
  if (raw[index] === '"') {
    const start = index;
    for (index += 1; index < raw.length; index += 1) {
      if (raw[index] === "\\") {
        index += 1;
      } else if (raw[index] === '"') {
        break;
      }
    }

    let next = index + 1;
    while (/\s/.test(raw[next] ?? "")) {
      next += 1;
    }
    if (depth === 1 && raw[next] === ":") {
      const key = JSON.parse(raw.slice(start, index + 1));
      if (componentKeyCounts.has(key)) {
        componentKeyCounts.set(key, componentKeyCounts.get(key) + 1);
      }
    }
  } else if (raw[index] === "{") {
    depth += 1;
  } else if (raw[index] === "}") {
    depth -= 1;
  }
}

for (const [component, count] of componentKeyCounts) {
  if (count > 1) {
    console.error(`duplicate component key: ${component}`);
    process.exit(1);
  }
}

if (manifest === null || typeof manifest !== "object" || Array.isArray(manifest)) {
  console.error("onboarding versions manifest must be a JSON object");
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
  if (typeof version !== "string" || !/^v0\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
    console.error(`${component} must be pinned to a v0.x.y tag`);
    process.exit(1);
  }
}
