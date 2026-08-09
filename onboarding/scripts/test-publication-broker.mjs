#!/usr/bin/env node

import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const brokerScript = path.join(scriptDirectory, 'kaizen-publication-broker.mjs');
const fixture = await fsp.mkdtemp(path.join(os.tmpdir(), 'publication-broker-fixture-'));
const socketPath = path.join(fixture, 'broker.sock');
const pushLog = path.join(fixture, 'push.log');
const realGit = execFileSync('sh', ['-c', 'command -v git'], { encoding: 'utf8' }).trim();
let broker;
let brokerErrors = '';
let completedCases = 0;

function git(args, options = {}) {
  return execFileSync(realGit, args, { encoding: 'utf8', ...options }).trim();
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function runCase(name, action) {
  try {
    await action();
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    const failure = `FAIL: ${name}: ${reason}`;
    console.error(failure);
    throw new Error(failure);
  }
  completedCases += 1;
  console.log(`ok: ${name}`);
}

async function request(payload) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    const chunks = [];
    let settled = false;
    const finish = (action, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      action(value);
    };
    const deadline = setTimeout(() => {
      socket.destroy();
      finish(reject, new Error(`broker did not answer within 30s: ${brokerErrors}`));
    }, 30_000);
    socket.on('connect', () => socket.end(payload));
    socket.on('data', (chunk) => chunks.push(chunk));
    socket.on('error', (error) => finish(reject, error));
    socket.on('end', () => finish(resolve, Buffer.concat(chunks)));
  });
}

function assertBoundedSingleLineResponse(buffer, context) {
  assert(buffer.length <= 4096, `${context}: response exceeded 4096 bytes`);
  const text = buffer.toString('utf8');
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  assert(lines.length === 2 && lines[1] === '',
    `${context}: response was not exactly one line: ${JSON.stringify(text)}`);
  return JSON.parse(lines[0]);
}

async function waitForSocket() {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (broker?.exitCode !== null) throw new Error(`broker exited during startup: ${brokerErrors}`);
    try {
      if ((await fsp.stat(socketPath)).isSocket()) return;
    } catch {
      // Broker is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('broker did not create its socket');
}

try {
  const source = path.join(fixture, 'source');
  const publication = path.join(fixture, 'publication.git');
  await fsp.mkdir(source);
  git(['init', '-q', '-b', 'feature/broker', source]);
  await fsp.writeFile(path.join(source, 'README.md'), 'fixture\n');
  git(['-C', source, 'add', 'README.md']);
  git(['-C', source, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']);
  await fsp.mkdir(publication, { mode: 0o700 });
  git(['clone', '-q', '--bare', '--no-local', source, publication]);
  const sha = git(['-C', publication, 'rev-parse', 'refs/heads/feature/broker']);

  const shim = path.join(fixture, 'git-shim.sh');
  await fsp.writeFile(shim, `#!/bin/sh
for argument in "$@"; do
  if [ "$argument" = push ]; then
    [ "$KAIZEN_PUBLICATION_BROKER_ASKPASS_TOKEN" = test-token ] || exit 91
    case "$*" in *test-token*) exit 92 ;; esac
    printf '%s\\n' "$*" >> ${JSON.stringify(pushLog)}
    exit 0
  fi
done
exec ${JSON.stringify(realGit)} "$@"
`, { mode: 0o700 });

  const uid = typeof process.getuid === 'function' ? process.getuid() : 1;
  const gid = typeof process.getgid === 'function' ? process.getgid() : 0;
  broker = spawn(process.execPath, [
    brokerScript,
    '--test-mode',
    '--socket', socketPath,
    '--allow', 'owner/repo:main',
    '--run-uid', String(uid || 1),
    '--run-gid', String(gid),
    '--git', shim,
    '--runtime-dir', fixture,
    '--push-timeout-ms', '10000'
  ], {
    env: { ...process.env, KAIZEN_PUBLICATION_BROKER_TOKEN: 'test-token' },
    stdio: ['ignore', 'ignore', 'pipe']
  });
  broker.stderr.setEncoding('utf8');
  broker.stderr.on('data', (chunk) => { brokerErrors += chunk; });
  await waitForSocket();

  const valid = {
    version: 1,
    operation: 'git-push',
    cwd: publication,
    pushUrl: 'https://github.com/owner/repo.git',
    refspec: 'feature/broker:refs/heads/feature/broker',
    expectedRepo: 'owner/repo',
    expectedSha: sha,
    forceWithLease: '--force-with-lease=refs/heads/feature/broker:'
  };

  await runCase('a valid request is pushed', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify(valid)}\n`),
      'valid request'
    );
    assert(response.ok === true, `valid request failed: ${JSON.stringify(response)}`);
  });

  await runCase('a mismatched expectedSha is refused', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify({ ...valid, expectedSha: '0'.repeat(40) })}\n`),
      'wrong expectedSha'
    );
    assert(response.ok === false && response.error === 'expected-sha-mismatch', 'wrong SHA was not refused');
  });

  await runCase('a non-private checkout is refused', async () => {
    await fsp.chmod(publication, 0o750);
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify(valid)}\n`),
      'non-private checkout'
    );
    assert(response.ok === false && response.error === 'invalid-cwd', 'non-private checkout was not refused');
    await fsp.chmod(publication, 0o700);
  });

  await runCase('a repository outside the allow-list is refused', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify({ ...valid, expectedRepo: 'other/repo', pushUrl: 'https://github.com/other/repo.git' })}\n`),
      'disallowed repository'
    );
    assert(response.ok === false && response.error === 'repository-not-allowed', 'disallowed repository was not refused');
  });

  await runCase('a malformed JSON request is refused', async () => {
    const response = assertBoundedSingleLineResponse(await request('{not json}\n'), 'malformed JSON');
    assert(response.ok === false && response.error === 'malformed-json', 'malformed JSON was not refused');
  });

  await runCase('a multi-line request is refused', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify(valid)}\n${JSON.stringify(valid)}\n`),
      'multi-line response'
    );
    assert(response.ok === false && response.error === 'invalid-framing', 'multiple request lines were not refused');
  });

  await runCase('an over-sized request is refused', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify({ ...valid, padding: 'x'.repeat(70 * 1024) })}\n`),
      'oversized response'
    );
    assert(response.ok === false && response.error === 'request-too-large', 'oversized request was not refused');
  });

  await runCase('pushing the default branch is refused', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify({ ...valid, refspec: 'main:refs/heads/main' })}\n`),
      'default branch'
    );
    assert(response.ok === false && response.error === 'default-branch-refused', 'default branch was not refused');
  });

  await runCase('an unsafe push URL is refused', async () => {
    const response = assertBoundedSingleLineResponse(
      await request(`${JSON.stringify({ ...valid, pushUrl: 'https://github.com@evil.example/owner/repo.git' })}\n`),
      'URL confusion'
    );
    assert(response.ok === false && response.error === 'unsafe-push-url', 'confusing URL was not refused');
  });

  await runCase('the push log records only the validated sha and ref without credentials', async () => {
    const pushes = (await fsp.readFile(pushLog, 'utf8')).trim().split('\n');
    assert(pushes.length === 1, `refused requests triggered pushes: ${pushes.length}`);
    assert(pushes[0].includes(`${sha}:refs/heads/feature/broker`), 'push did not use the validated SHA');
    assert(!pushes[0].includes('test-token'), 'token appeared in Git arguments');
    assert(!brokerErrors.includes('test-token'), 'token appeared in broker logs');
  });

  const expectedCases = 10;
  assert(completedCases === expectedCases,
    `FAIL: case count: expected ${expectedCases}, reported ${completedCases}`);
  console.log(`All publication broker fixtures passed (${completedCases} cases).`);
} finally {
  if (broker && broker.exitCode === null) {
    broker.kill('SIGTERM');
    await new Promise((resolve) => broker.once('exit', resolve));
  }
  await fsp.rm(fixture, { recursive: true, force: true });
}
