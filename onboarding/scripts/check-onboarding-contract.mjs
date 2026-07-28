#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REQUIRED_PROTECTED_PATHS = [
  '.github/**',
  '**/.env*',
  '**/secrets/**',
  '**/*migration*/**',
  '.kaizen/**'
];
const REQUIRED_FORBIDDEN_PATH = '**/.git/**';
const REQUIRED_LABELS = [
  'kaizen',
  'kaizen:P0',
  'kaizen:P1',
  'kaizen:P2',
  'kaizen:pr-only'
];

function usage() {
  console.error(
    'Usage: check-onboarding-contract.sh [--observations FILE] [--toolchain-manifest FILE] TARGET_REPOSITORY'
  );
}

function parseArguments(argv) {
  let observations;
  let toolchainManifest;
  let target;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--observations' || argument === '--toolchain-manifest') {
      const value = argv[index + 1];
      if (!value) throw new Error(`${argument} requires a file path`);
      if (argument === '--observations') observations = value;
      else toolchainManifest = value;
      index += 1;
    } else if (argument === '--help' || argument === '-h') {
      usage();
      process.exit(0);
    } else if (argument.startsWith('-')) {
      throw new Error(`unknown option: ${argument}`);
    } else if (target) {
      throw new Error('only one target repository may be checked');
    } else {
      target = argument;
    }
  }
  if (!target) throw new Error('target repository path is required');
  return { observations, target, toolchainManifest };
}

function reportFailure(message, remediation) {
  console.error(`FAIL: ${message}`);
  console.error(`  Remediation: ${remediation}`);
  failures += 1;
}

async function readJson(file, description) {
  let raw;
  try {
    raw = await fs.readFile(file, 'utf8');
  } catch (error) {
    reportFailure(
      `${description} is missing: ${file}`,
      `create ${file} using the documented onboarding contract format`
    );
    return undefined;
  }
  try {
    return JSON.parse(raw);
  } catch (error) {
    reportFailure(
      `${description} is not valid JSON: ${file}`,
      `replace it with valid JSON (${error.message})`
    );
    return undefined;
  }
}

function resolveKaizenRoot() {
  if (process.env.KAIZEN_LOOP_ROOT) {
    return path.resolve(process.env.KAIZEN_LOOP_ROOT);
  }
  let executable;
  try {
    executable = execFileSync('sh', ['-c', 'command -v kaizen'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore']
    }).trim();
  } catch {
    return undefined;
  }
  if (!executable) return undefined;
  const cli = realpathSync(executable);
  return path.dirname(path.dirname(cli));
}

async function loadConfig(target) {
  const kaizenRoot = resolveKaizenRoot();
  if (!kaizenRoot) {
    reportFailure(
      'the Kaizen configuration schema is unavailable because the kaizen executable was not found',
      'install the versions pinned by onboarding/versions.json, or set KAIZEN_LOOP_ROOT to a kaizen-loop installation'
    );
    return undefined;
  }
  const loader = path.join(kaizenRoot, 'dist', 'config', 'config.js');
  if (!existsSync(loader)) {
    reportFailure(
      `the Kaizen configuration loader is missing: ${loader}`,
      'install a built kaizen-loop release containing dist/config/config.js'
    );
    return undefined;
  }
  try {
    const { loadConfig: loadKaizenConfig } = await import(pathToFileURL(loader));
    return await loadKaizenConfig(target);
  } catch (error) {
    reportFailure(
      `.kaizen/config.yml is not schema-valid: ${error.message}`,
      'regenerate or repair the config with the pinned kaizen-loop toolchain'
    );
    return undefined;
  }
}

function checkConfig(config) {
  if (!config) return;
  if (config.policy.mode !== 'pr-only') {
    reportFailure(
      `policy.mode must be pr-only (found ${JSON.stringify(config.policy.mode)})`,
      'set policy.mode: pr-only in .kaizen/config.yml'
    );
  }
  if (!Number.isInteger(config.safety.wipLimit) || config.safety.wipLimit > 5) {
    reportFailure(
      `safety.wipLimit must be an integer no greater than 5 (found ${JSON.stringify(config.safety.wipLimit)})`,
      'set safety.wipLimit to an integer from 0 through 5'
    );
  }
  if (config.verifier.enabled !== true) {
    reportFailure(
      'verifier.enabled must be true',
      'set verifier.enabled: true in .kaizen/config.yml'
    );
  }
  for (const requiredPath of REQUIRED_PROTECTED_PATHS) {
    if (!config.policy.protectedPaths.includes(requiredPath)) {
      reportFailure(
        `policy.protectedPaths is missing the organization safety-floor entry ${requiredPath}`,
        `add ${JSON.stringify(requiredPath)} to policy.protectedPaths in the final .kaizen/config.yml; profile overlays cannot replace this check`
      );
    }
  }
  if (!config.policy.forbiddenPaths.includes(REQUIRED_FORBIDDEN_PATH)) {
    reportFailure(
      `policy.forbiddenPaths is missing ${REQUIRED_FORBIDDEN_PATH}`,
      `add ${JSON.stringify(REQUIRED_FORBIDDEN_PATH)} to policy.forbiddenPaths`
    );
  }
}

async function checkIssueTemplate(target) {
  const template = path.join(target, '.github', 'ISSUE_TEMPLATE', 'kaizen.yml');
  try {
    const stat = await fs.stat(template);
    if (!stat.isFile() || stat.size === 0) throw new Error('not a non-empty file');
  } catch {
    reportFailure(
      'the required Kaizen issue template is missing or empty',
      'create a non-empty .github/ISSUE_TEMPLATE/kaizen.yml'
    );
  }
}

function checkObservations(observations) {
  if (!observations) return;
  if (!Array.isArray(observations.labels) || observations.labels.some((label) => typeof label !== 'string')) {
    reportFailure(
      'observations.labels must be an array of label names',
      'capture the repository labels as strings in the observations file'
    );
  } else {
    for (const label of REQUIRED_LABELS) {
      if (!observations.labels.includes(label)) {
        reportFailure(
          `required repository label is not observed: ${label}`,
          `create the ${label} label, recapture observations, and rerun the checker`
        );
      }
    }
  }

  const protection = observations.branchProtection;
  if (!protection || typeof protection !== 'object' || Array.isArray(protection)) {
    reportFailure(
      'observations.branchProtection must describe the default-branch protection',
      'capture strict required status checks, conversation resolution, and admin enforcement'
    );
    return;
  }
  const checks = protection.requiredStatusChecks;
  if (!checks || checks.strict !== true || !Array.isArray(checks.contexts) || checks.contexts.length === 0 ||
      checks.contexts.some((context) => typeof context !== 'string' || context.length === 0)) {
    reportFailure(
      'branch protection must require at least one strict status check',
      'enable strict required status checks and record their non-empty contexts in observations.branchProtection.requiredStatusChecks'
    );
  }
  if (protection.requiredConversationResolution !== true) {
    reportFailure(
      'branch protection must require conversation resolution',
      'enable required_conversation_resolution and recapture observations'
    );
  }
  if (protection.enforceAdmins !== true) {
    reportFailure(
      'branch protection must enforce rules for administrators',
      'enable enforce_admins and recapture observations'
    );
  }
}

async function checkSmokeArtifact(target) {
  const directory = path.join(target, 'docs', 'smoke-runs');
  let entries;
  try {
    entries = await fs.readdir(directory, { withFileTypes: true });
  } catch {
    reportFailure(
      'no smoke artifact directory was found',
      'run kaizen smoke successfully and commit its JSON artifact under docs/smoke-runs/'
    );
    return;
  }
  const artifacts = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
    .map((entry) => path.join(directory, entry.name))
    .sort();
  if (artifacts.length === 0) {
    reportFailure(
      'no smoke artifact JSON file was found',
      'run kaizen smoke successfully and commit its JSON artifact under docs/smoke-runs/'
    );
    return;
  }
  let validArtifact = false;
  for (const artifact of artifacts) {
    try {
      JSON.parse(await fs.readFile(artifact, 'utf8'));
      validArtifact = true;
      break;
    } catch {
      // Keep looking so a malformed historical artifact does not hide a valid one.
    }
  }
  if (!validArtifact) {
    reportFailure(
      'smoke artifact files exist but none contains valid JSON',
      'replace or regenerate at least one artifact under docs/smoke-runs/'
    );
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function sha256(content) {
  return createHash('sha256').update(content).digest('hex');
}

async function listFiles(directory, prefix = '') {
  const result = [];
  const currentDirectory = path.join(directory, ...prefix.split('/').filter(Boolean));
  const entries = await fs.readdir(currentDirectory, { withFileTypes: true });
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const relative = path.posix.join(prefix, entry.name);
    const absolute = path.join(directory, ...relative.split('/'));
    if (entry.isDirectory()) result.push(...await listFiles(directory, relative));
    else if (entry.isFile()) result.push(relative);
  }
  return result;
}

async function checkSkillsManifest(target, toolchainManifestOption) {
  const manifestPath = path.join(target, 'skills', 'skills-manifest.json');
  if (!existsSync(manifestPath)) return;
  const manifest = await readJson(manifestPath, 'skills manifest');
  if (!manifest) return;
  if (manifest.version !== 1 || !isPlainObject(manifest.files)) {
    reportFailure(
      'skills/skills-manifest.json must have version 1 and a files object',
      'regenerate the skills manifest with the pinned Kaizen toolchain'
    );
    return;
  }

  const declaredFiles = Object.keys(manifest.files).sort();
  for (const relative of declaredFiles) {
    const expected = manifest.files[relative];
    const normalized = path.posix.normalize(relative);
    if (!relative.startsWith('skills/') || normalized !== relative || relative === 'skills/skills-manifest.json') {
      reportFailure(
        `skills manifest contains an unsafe or invalid path: ${relative}`,
        'use normalized repository-relative paths below skills/ and omit skills-manifest.json itself'
      );
      continue;
    }
    if (typeof expected !== 'string' || !/^[0-9a-f]{64}$/.test(expected)) {
      reportFailure(
        `skills manifest has an invalid SHA-256 digest for ${relative}`,
        'regenerate the manifest with lowercase SHA-256 digests'
      );
      continue;
    }
    const absolute = path.join(target, ...relative.split('/'));
    try {
      const actual = sha256(await fs.readFile(absolute));
      if (actual !== expected) {
        reportFailure(
          `vendored skill does not match its manifest digest: ${relative}`,
          're-vendor the skill from the pinned toolchain and regenerate skills/skills-manifest.json'
        );
      }
    } catch {
      reportFailure(
        `skills manifest references a missing file: ${relative}`,
        're-vendor the missing skill or regenerate skills/skills-manifest.json'
      );
    }
  }

  const actualFiles = (await listFiles(path.join(target, 'skills')))
    .filter((relative) => relative !== 'skills-manifest.json')
    .map((relative) => `skills/${relative}`)
    .sort();
  for (const actual of actualFiles) {
    if (!Object.prototype.hasOwnProperty.call(manifest.files, actual)) {
      reportFailure(
        `vendored skill file is not recorded in the manifest: ${actual}`,
        'regenerate skills/skills-manifest.json so every vendored skill file is pinned'
      );
    }
  }

  const defaultToolchain = path.join(target, 'onboarding', 'versions.json');
  const toolchainPath = toolchainManifestOption
    ? path.resolve(toolchainManifestOption)
    : (existsSync(defaultToolchain) ? defaultToolchain : undefined);
  if (!toolchainPath && manifest.toolchain !== undefined) {
    reportFailure(
      'skills manifest declares toolchain versions but no toolchain manifest was found',
      'provide --toolchain-manifest FILE or add onboarding/versions.json to the target repository'
    );
    return;
  }
  if (!toolchainPath) return;
  const toolchain = await readJson(toolchainPath, 'toolchain manifest');
  if (!toolchain) return;
  if (!isPlainObject(toolchain) ||
      Object.values(toolchain).some((version) => typeof version !== 'string' || version.length === 0)) {
    reportFailure(
      'toolchain manifest must be an object of component names to non-empty versions',
      'regenerate the toolchain manifest from onboarding/versions.json'
    );
    return;
  }
  if (!isPlainObject(manifest.toolchain)) {
    reportFailure(
      'skills manifest must declare a toolchain object when toolchain metadata is present',
      'copy the pinned component versions into skills/skills-manifest.json under toolchain'
    );
    return;
  }
  for (const [component, version] of Object.entries(toolchain)) {
    if (manifest.toolchain[component] !== version) {
      reportFailure(
        `skills manifest toolchain mismatch for ${component}: expected ${JSON.stringify(version)}, found ${JSON.stringify(manifest.toolchain[component])}`,
        're-vendor skills with the pinned toolchain and update skills/skills-manifest.json'
      );
    }
  }
}

let failures = 0;
let options;
try {
  options = parseArguments(process.argv.slice(2));
} catch (error) {
  usage();
  console.error(`ERROR: ${error.message}`);
  process.exit(2);
}

const target = path.resolve(options.target);
try {
  const stat = await fs.stat(target);
  if (!stat.isDirectory()) throw new Error('not a directory');
} catch {
  console.error(`ERROR: target repository is not a directory: ${target}`);
  process.exit(2);
}

const observationsPath = options.observations
  ? path.resolve(options.observations)
  : path.join(target, '.kaizen', 'onboarding-observations.json');
const observations = await readJson(observationsPath, 'onboarding observations');
const config = await loadConfig(target);

checkConfig(config);
await checkIssueTemplate(target);
checkObservations(observations);
await checkSmokeArtifact(target);
await checkSkillsManifest(target, options.toolchainManifest);

if (failures > 0) {
  console.error(`Onboarding contract failed with ${failures} mismatch(es).`);
  process.exit(1);
}
console.log(`PASS: onboarding contract is satisfied for ${target}`);
