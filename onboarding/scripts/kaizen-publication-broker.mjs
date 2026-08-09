#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { TextDecoder } from 'node:util';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';

const MAX_REQUEST_BYTES = 64 * 1024;
const MAX_RESPONSE_BYTES = 4096;
const DEFAULT_PUSH_TIMEOUT_MS = 25 * 60 * 1000;
const MAX_CONCURRENT_PUSHES = 4;
const REPOSITORY_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]+$/;
const SHA_PATTERN = /^[0-9a-f]{40}$/;

function usage() {
  console.error(`Usage: kaizen-publication-broker.mjs [options]

  --socket PATH             Unix socket path (required)
  --allow REPO:BRANCH       Allow owner/repo and name its default branch; repeatable
  --run-uid UID             Kaizen runner UID used for request validation (required)
  --run-gid GID             Kaizen runner GID used for request validation (required)
  --socket-gid GID          Group allowed to connect (default: --run-gid)
  --git PATH                Trusted Git executable (default: /usr/bin/git)
  --runtime-dir PATH        Root-only push workspace parent (default: /var/tmp)
  --push-timeout-ms MS      Per-push timeout (default: ${DEFAULT_PUSH_TIMEOUT_MS})
  --help                    Show this help

The broker token is read from KAIZEN_PUBLICATION_BROKER_TOKEN.`);
}

function parseInteger(value, option, { minimum = 0 } = {}) {
  if (!/^(0|[1-9]\d*)$/.test(value ?? '')) throw new Error(`${option} requires an integer`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum) throw new Error(`${option} is out of range`);
  return parsed;
}

function parseAllow(value) {
  const separator = value.lastIndexOf(':');
  if (separator <= 0 || separator === value.length - 1) {
    throw new Error('--allow must use owner/repo:default-branch');
  }
  const repository = value.slice(0, separator);
  const defaultBranch = value.slice(separator + 1);
  if (!REPOSITORY_PATTERN.test(repository)) throw new Error(`invalid allow-listed repository: ${repository}`);
  if (!isSyntacticallySafeBranch(defaultBranch)) throw new Error(`invalid default branch: ${defaultBranch}`);
  return { repository, defaultBranch };
}

function parseArguments(argv) {
  const options = {
    allows: new Map(),
    git: '/usr/bin/git',
    pushTimeoutMs: DEFAULT_PUSH_TIMEOUT_MS,
    runtimeDir: '/var/tmp',
    testMode: false
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') {
      usage();
      process.exit(0);
    }
    if (argument === '--test-mode') {
      options.testMode = true;
      continue;
    }
    if (!['--socket', '--allow', '--run-uid', '--run-gid', '--socket-gid', '--git', '--runtime-dir', '--push-timeout-ms'].includes(argument)) {
      throw new Error(`unknown option: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value) throw new Error(`${argument} requires a value`);
    index += 1;
    if (argument === '--socket') options.socket = value;
    else if (argument === '--allow') {
      const entry = parseAllow(value);
      const key = entry.repository.toLowerCase();
      if (options.allows.has(key)) throw new Error(`duplicate allow-listed repository: ${entry.repository}`);
      options.allows.set(key, entry);
    } else if (argument === '--run-uid') options.runUid = parseInteger(value, argument, { minimum: 1 });
    else if (argument === '--run-gid') options.runGid = parseInteger(value, argument);
    else if (argument === '--socket-gid') options.socketGid = parseInteger(value, argument);
    else if (argument === '--git') options.git = value;
    else if (argument === '--runtime-dir') options.runtimeDir = value;
    else options.pushTimeoutMs = parseInteger(value, argument, { minimum: 10_000 });
  }
  if (!options.socket || !path.isAbsolute(options.socket)) throw new Error('--socket must be an absolute path');
  if (options.allows.size === 0) throw new Error('at least one --allow entry is required');
  if (options.runUid === undefined) throw new Error('--run-uid is required');
  if (options.runGid === undefined) throw new Error('--run-gid is required');
  if (options.socketGid === undefined) options.socketGid = options.runGid;
  if (!options.testMode && options.socketGid !== options.runGid) {
    throw new Error('--socket-gid must equal --run-gid so one dedicated runner group controls access');
  }
  if (!path.isAbsolute(options.git)) throw new Error('--git must be an absolute path');
  if (!path.isAbsolute(options.runtimeDir)) throw new Error('--runtime-dir must be an absolute path');
  if (options.pushTimeoutMs > 60 * 60 * 1000) throw new Error('--push-timeout-ms may not exceed 3600000');
  return options;
}

function isSyntacticallySafeBranch(branch) {
  return typeof branch === 'string' && branch.length > 0 && branch.length <= 255 &&
    !branch.startsWith('-') && !branch.includes(':') && !branch.includes('\0') && !branch.includes('\n') &&
    !branch.includes('\r');
}

function assertSecureRootDirectory(directory) {
  let current = fs.realpathSync(directory);
  if (current !== directory) throw new Error(`socket directory must use its canonical path: ${directory}`);
  while (true) {
    const stat = fs.lstatSync(current);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== 0 || (stat.mode & 0o022) !== 0) {
      throw new Error(`socket directory is not immutable and root-owned: ${current}`);
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}

function resolveSafeRuntimeDirectory(directory) {
  const resolved = fs.realpathSync(directory);
  const stat = fs.lstatSync(resolved);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== 0 ||
      ((stat.mode & 0o022) !== 0 && (stat.mode & 0o1000) === 0)) {
    throw new Error(`runtime directory must be root-owned and non-writable or sticky: ${resolved}`);
  }
  let current = path.dirname(resolved);
  while (true) {
    const ancestor = fs.lstatSync(current);
    if (!ancestor.isDirectory() || ancestor.isSymbolicLink() || ancestor.uid !== 0 ||
        (ancestor.mode & 0o022) !== 0) {
      throw new Error(`runtime directory ancestor must be immutable and root-owned: ${current}`);
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return resolved;
}

function assertTrustedExecutable(executable, testMode) {
  const resolved = fs.realpathSync(executable);
  const stat = fs.statSync(resolved);
  if (!stat.isFile() || (stat.mode & 0o111) === 0) throw new Error(`Git executable is not executable: ${resolved}`);
  if (!testMode && (stat.uid !== 0 || (stat.mode & 0o022) !== 0)) {
    throw new Error(`Git executable must be immutable and root-owned: ${resolved}`);
  }
  if (!testMode) {
    let current = path.dirname(resolved);
    while (true) {
      const directory = fs.lstatSync(current);
      if (!directory.isDirectory() || directory.isSymbolicLink() || directory.uid !== 0 ||
          (directory.mode & 0o022) !== 0) {
        throw new Error(`Git executable directory must be immutable and root-owned: ${current}`);
      }
      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
  }
  return resolved;
}

function parseGithubUrl(value) {
  if (typeof value !== 'string' || value.length > 512 || value.includes('%')) {
    throw new RequestError('unsafe-push-url');
  }
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new RequestError('unsafe-push-url');
  }
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'github.com' || parsed.host !== 'github.com' ||
      parsed.username || parsed.password || parsed.port || parsed.search || parsed.hash) {
    throw new RequestError('unsafe-push-url');
  }
  const segments = parsed.pathname.split('/').filter(Boolean);
  if (segments.length !== 2 || parsed.pathname.includes('//')) throw new RequestError('unsafe-push-url');
  const repository = `${segments[0]}/${segments[1].replace(/\.git$/, '')}`;
  if (!REPOSITORY_PATTERN.test(repository) || segments[1] === '.git') throw new RequestError('unsafe-push-url');
  const canonicalPath = `/${segments[0]}/${segments[1]}`;
  if (parsed.pathname !== canonicalPath) throw new RequestError('unsafe-push-url');
  return repository;
}

class RequestError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function assertExactKeys(request) {
  const required = ['cwd', 'expectedRepo', 'expectedSha', 'operation', 'pushUrl', 'refspec', 'version'];
  const optional = ['forceWithLease'];
  const actual = Object.keys(request).sort();
  const allowed = new Set([...required, ...optional]);
  if (required.some((key) => !Object.prototype.hasOwnProperty.call(request, key)) ||
      actual.some((key) => !allowed.has(key))) {
    throw new RequestError('invalid-request-fields');
  }
}

async function validateRequest(request, options) {
  if (!request || typeof request !== 'object' || Array.isArray(request)) throw new RequestError('invalid-request');
  assertExactKeys(request);
  if (request.version !== 1 || request.operation !== 'git-push') throw new RequestError('unsupported-operation');
  for (const key of ['cwd', 'pushUrl', 'refspec', 'expectedRepo', 'expectedSha']) {
    if (typeof request[key] !== 'string') throw new RequestError('invalid-request-fields');
  }
  if (!path.isAbsolute(request.cwd)) throw new RequestError('invalid-cwd');
  let cwd;
  try {
    cwd = await fsp.realpath(request.cwd);
    const cwdStat = await fsp.stat(cwd);
    const ownerMatches = cwdStat.uid === options.runUid ||
      (options.testMode && typeof process.getuid === 'function' && process.getuid() === 0);
    if (!cwdStat.isDirectory() || !ownerMatches || (cwdStat.mode & 0o077) !== 0) {
      throw new Error('cwd is not private to the configured runner');
    }
  } catch {
    throw new RequestError('invalid-cwd');
  }
  const urlRepo = parseGithubUrl(request.pushUrl);
  if (!REPOSITORY_PATTERN.test(request.expectedRepo) ||
      urlRepo.toLowerCase() !== request.expectedRepo.toLowerCase()) {
    throw new RequestError('repository-mismatch');
  }
  const allow = options.allows.get(request.expectedRepo.toLowerCase());
  if (!allow) throw new RequestError('repository-not-allowed');

  const parts = request.refspec.split(':');
  if (parts.length !== 2 || !parts[1].startsWith('refs/heads/')) throw new RequestError('invalid-refspec');
  const source = parts[0];
  const target = parts[1].slice('refs/heads/'.length);
  if (!isSyntacticallySafeBranch(source) || source !== target || target === allow.defaultBranch) {
    throw new RequestError(target === allow.defaultBranch ? 'default-branch-refused' : 'invalid-refspec');
  }
  await gitChecked(options, ['-C', cwd, 'check-ref-format', '--branch', source]);
  if (!SHA_PATTERN.test(request.expectedSha)) throw new RequestError('invalid-expected-sha');

  let lease;
  if (request.forceWithLease !== undefined) {
    if (typeof request.forceWithLease !== 'string') throw new RequestError('invalid-force-with-lease');
    const prefix = `--force-with-lease=refs/heads/${target}:`;
    if (!request.forceWithLease.startsWith(prefix)) throw new RequestError('invalid-force-with-lease');
    const expectedRemote = request.forceWithLease.slice(prefix.length);
    if (expectedRemote !== '' && !SHA_PATTERN.test(expectedRemote)) throw new RequestError('invalid-force-with-lease');
    lease = `${prefix}${expectedRemote}`;
  }

  const tip = (await gitChecked(options, [
    '-C', cwd, 'rev-parse', '--verify', `refs/heads/${source}^{commit}`
  ])).stdout.trim();
  if (tip !== request.expectedSha) throw new RequestError('expected-sha-mismatch');
  const objectsText = (await gitChecked(options, ['-C', cwd, 'rev-parse', '--git-path', 'objects'])).stdout.trim();
  const objects = await fsp.realpath(path.resolve(cwd, objectsText));
  if (objects.includes(path.delimiter) || objects.includes('\n') || objects.includes('\r') ||
      !(await fsp.stat(objects)).isDirectory()) {
    throw new RequestError('invalid-object-directory');
  }
  return { cwd, objects, target, lease, expectedSha: request.expectedSha, pushUrl: request.pushUrl };
}

function childIdentity(options, brokerIdentity = false) {
  if (options.testMode) return {};
  if (!brokerIdentity && typeof process.geteuid === 'function' && process.geteuid() === 0) {
    return { uid: options.runUid, gid: options.runGid };
  }
  return {};
}

function baseGitEnvironment(home) {
  return {
    HOME: home,
    LANG: 'C',
    LC_ALL: 'C',
    PATH: '/usr/bin:/bin',
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_TERMINAL_PROMPT: '0'
  };
}

function runChild(command, args, { brokerIdentity = false, env, options, timeoutMs = 30_000 }) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      ...childIdentity(options, brokerIdentity)
    });
    const stdout = [];
    const stderr = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, timeoutMs);
    timer.unref();
    child.stdout.on('data', (chunk) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes <= 64 * 1024) stdout.push(chunk);
    });
    child.stderr.on('data', (chunk) => {
      stderrBytes += chunk.length;
      if (stderrBytes <= 64 * 1024) stderr.push(chunk);
    });
    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      const result = {
        code: code ?? 1,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8')
      };
      if (timedOut) reject(new RequestError('git-timeout'));
      else if (result.code !== 0) reject(Object.assign(new RequestError('git-failed'), { result }));
      else resolve(result);
    });
  });
}

function gitChecked(options, args, overrides = {}) {
  return runChild(options.git, args, {
    brokerIdentity: overrides.brokerIdentity,
    env: overrides.env ?? baseGitEnvironment('/var/empty'),
    options,
    timeoutMs: overrides.timeoutMs
  });
}

async function pushValidatedRef(validated, options, token) {
  const temporaryRoot = options.testMode ? os.tmpdir() : options.runtimeDir;
  const temporary = await fsp.mkdtemp(path.join(temporaryRoot, 'kaizen-publication-broker-'));
  try {
    await fsp.chmod(temporary, 0o700);
    const gitDir = path.join(temporary, 'publication.git');
    const askpass = path.join(temporary, 'askpass.sh');
    await fsp.writeFile(askpass, `#!/bin/sh
case \"$1\" in
  *Username*) printf '%s\\n' x-access-token ;;
  *Password*) printf '%s\\n' \"$KAIZEN_PUBLICATION_BROKER_ASKPASS_TOKEN\" ;;
  *) exit 1 ;;
esac
`, { mode: 0o700 });
    await gitChecked(options, ['init', '--bare', gitDir], {
      brokerIdentity: true,
      env: baseGitEnvironment(temporary)
    });
    const env = {
      ...baseGitEnvironment(temporary),
      GIT_ALTERNATE_OBJECT_DIRECTORIES: validated.objects,
      GIT_ASKPASS: askpass,
      KAIZEN_PUBLICATION_BROKER_ASKPASS_TOKEN: token
    };
    const args = [
      `--git-dir=${gitDir}`,
      '-c', 'core.hooksPath=/dev/null',
      '-c', 'credential.helper=',
      'push', '--no-verify',
      ...(validated.lease ? [validated.lease] : []),
      validated.pushUrl,
      `${validated.expectedSha}:refs/heads/${validated.target}`
    ];
    await gitChecked(options, args, {
      brokerIdentity: true,
      env,
      timeoutMs: options.pushTimeoutMs
    });
  } finally {
    await fsp.rm(temporary, { recursive: true, force: true });
  }
}

function log(event, details = {}) {
  process.stderr.write(`${JSON.stringify({ timestamp: new Date().toISOString(), event, ...details })}\n`);
}

function writeResponse(socket, value) {
  const output = `${JSON.stringify(value)}\n`;
  if (Buffer.byteLength(output) > MAX_RESPONSE_BYTES || output.split('\n').length !== 2) {
    socket.end('{"ok":false,"error":"internal-response-error"}\n', () => {
      setTimeout(() => socket.destroy(), 1_000).unref();
    });
    return;
  }
  socket.end(output, () => {
    setTimeout(() => socket.destroy(), 1_000).unref();
  });
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (process.platform === 'win32') throw new Error('Unix sockets are required');
  if (!options.testMode && (typeof process.geteuid !== 'function' || process.geteuid() !== 0)) {
    throw new Error('the publication broker must start as root');
  }
  if (options.testMode) {
    const resolvedSocketParent = fs.realpathSync(path.dirname(options.socket));
    const resolvedTemporaryRoot = fs.realpathSync(os.tmpdir());
    if (process.env.KAIZEN_PUBLICATION_BROKER_TOKEN !== 'test-token' ||
        !(resolvedSocketParent === resolvedTemporaryRoot ||
          resolvedSocketParent.startsWith(`${resolvedTemporaryRoot}${path.sep}`))) {
      throw new Error('--test-mode is restricted to a temporary socket and the sentinel test token');
    }
  } else {
    assertSecureRootDirectory(path.dirname(options.socket));
    options.runtimeDir = resolveSafeRuntimeDirectory(options.runtimeDir);
  }
  options.git = assertTrustedExecutable(options.git, options.testMode);
  for (const entry of options.allows.values()) {
    try {
      await gitChecked(options, ['check-ref-format', '--branch', entry.defaultBranch]);
    } catch {
      throw new Error(`invalid default branch in --allow: ${entry.defaultBranch}`);
    }
  }
  const token = process.env.KAIZEN_PUBLICATION_BROKER_TOKEN;
  if (!token || token.includes('\0') || token.includes('\n') || token.includes('\r')) {
    throw new Error('KAIZEN_PUBLICATION_BROKER_TOKEN must contain one non-empty line');
  }
  if (fs.existsSync(options.socket)) {
    throw new Error(`socket path already exists; inspect and remove it before restart: ${options.socket}`);
  }

  const previousUmask = process.umask(0o077);
  let activePushes = 0;
  const server = net.createServer({ allowHalfOpen: true }, (socket) => {
    const chunks = [];
    let bytes = 0;
    let finished = false;
    socket.setTimeout(10_000, () => {
      if (finished) {
        socket.destroy();
        return;
      }
      finished = true;
      log('request-refused', { reason: 'request-timeout' });
      writeResponse(socket, { ok: false, error: 'request-timeout' });
    });
    socket.on('data', (chunk) => {
      if (finished) return;
      bytes += chunk.length;
      if (bytes > MAX_REQUEST_BYTES) {
        finished = true;
        log('request-refused', { reason: 'request-too-large' });
        writeResponse(socket, { ok: false, error: 'request-too-large' });
        return;
      }
      chunks.push(chunk);
    });
    socket.on('end', async () => {
      if (finished) return;
      finished = true;
      if (activePushes >= MAX_CONCURRENT_PUSHES) {
        writeResponse(socket, { ok: false, error: 'broker-busy' });
        return;
      }
      activePushes += 1;
      try {
        const input = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
        if (!input.endsWith('\n') || input.slice(0, -1).includes('\n') || input.includes('\r')) {
          throw new RequestError('invalid-framing');
        }
        let request;
        try {
          request = JSON.parse(input.slice(0, -1));
        } catch {
          throw new RequestError('malformed-json');
        }
        const validated = await validateRequest(request, options);
        await pushValidatedRef(validated, options, token);
        log('publication-succeeded', {
          repository: request.expectedRepo,
          branch: validated.target,
          sha: validated.expectedSha
        });
        writeResponse(socket, { ok: true });
      } catch (error) {
        const reason = error instanceof RequestError ? error.code : 'internal-error';
        log('request-refused', { reason });
        writeResponse(socket, { ok: false, error: reason });
      } finally {
        activePushes -= 1;
      }
    });
    socket.on('error', (error) => log('connection-error', { reason: error.code ?? 'socket-error' }));
  });
  server.maxConnections = 32;

  await new Promise((resolve, reject) => {
    const startupError = (error) => reject(error);
    server.once('error', startupError);
    server.listen(options.socket, () => {
      server.off('error', startupError);
      resolve();
    });
  });
  server.on('error', (error) => log('server-error', { reason: error.code ?? 'server-error' }));
  try {
    if (options.testMode) {
      fs.chmodSync(options.socket, 0o600);
    } else {
      fs.chownSync(options.socket, 0, options.socketGid);
      fs.chmodSync(options.socket, 0o660);
    }
  } finally {
    process.umask(previousUmask);
  }
  const socketStat = fs.statSync(options.socket);
  log('broker-ready', {
    socket: options.socket,
    repositories: [...options.allows.values()].map((entry) => entry.repository),
    runUid: options.runUid,
    runGid: options.runGid
  });

  const shutdown = (signal) => {
    const exitCode = signal === 'SIGINT' ? 130 : 143;
    let exited = false;
    let deadline;
    const finish = () => {
      if (exited) return;
      exited = true;
      if (deadline) clearTimeout(deadline);
      try {
        const current = fs.lstatSync(options.socket);
        if (current.isSocket() && current.dev === socketStat.dev && current.ino === socketStat.ino) {
          fs.unlinkSync(options.socket);
        }
      } catch (error) {
        if (error.code !== 'ENOENT') log('socket-cleanup-failed', { reason: error.code ?? 'unknown' });
      }
      process.exit(exitCode);
    };
    deadline = setTimeout(finish, 30_000);
    server.close(finish);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exit(1);
});
