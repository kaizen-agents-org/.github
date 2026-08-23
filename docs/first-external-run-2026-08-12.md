# First External Issue-to-Merge Run — 2026-08-12

The first time an issue in a repository outside this organization went through
builder, verifier, publication, review and merge without manual intervention in
the pipeline.

This records what was verified, what had to be fixed to get there, and what is
still known to be broken. It closes the execution half of
[`#120`](https://github.com/kaizen-agents-org/.github/issues/120).

## Result

| | |
|---|---|
| Target | `s-hiraoku/topcoat-sandbox` (Rust, outside this organization) |
| Issue | [#11](https://github.com/s-hiraoku/topcoat-sandbox/issues/11) — cover the `herdr` error paths |
| Pull request | [#12](https://github.com/s-hiraoku/topcoat-sandbox/pull/12) — `src/herdr.rs`, `+58 −0`, 1 file |
| Merge | `683d9ff` |
| Toolchain | kaizen-loop `v0.1.6`, builder-agent `v0.1.0`, verifier `v0.1.1` |

The issue was a real gap found by reading the source: `parse_agent_list` has
three outcomes and only the success path had a test. The merged change takes
`cargo test` on `main` from 3 passing tests to 6, with no `clippy` warnings and
no behaviour change.

Verifier reported `evidence_grade: "executed"` with
`verify_commands: [cargo test, cargo clippy]`, both exiting 0, backed by a
338-line `verify.log`.

## Why this took four releases

Every one of these was invisible to the Node dogfood repositories. None was a
defect in the target repository, and none was Rust-specific — they were exposed
by *a greenfield repository outside the organization*, not by the language.

### v0.1.4 — pinned installs failed their own preflight

`kaizen init` wrote `verifier.expectedRef: refs/heads/main` while the installer
had checked out a pinned tag. The freshness preflight compared the two and
failed as soon as verifier `main` moved past the tag
([kaizen-loop#362](https://github.com/kaizen-agents-org/kaizen-loop/issues/362)).

Dogfood repositories track `main`, so the two agreed there.

### v0.1.5 — no HTTPS publication could ever succeed

The publication broker parses a request only on end-of-input. The client wrote
the request and left the write side open, so the broker waited out its own
10-second read timeout and answered `request-timeout`
([kaizen-loop#372](https://github.com/kaizen-agents-org/kaizen-loop/pull/372)).

```
write only (before)   elapsed=10007ms   {"ok":false,"error":"request-timeout"}
half-close (after)    elapsed=1963ms    push succeeded
```

Both halves were individually correct and individually tested; the *contract
between them* was tested by neither repository. The broker lives in `.github`
and kaizen-loop talks to it only over a Unix socket, so nothing covered the
wire format. `test/publication-broker-protocol.test.ts` now does.

Dogfood repositories use SSH remotes, which never reach the broker.

### v0.1.6 — every generated pull request was contaminated

The verifier writes its artifacts inside the checkout — it is confined to
`KAIZEN_WORKSPACE_DIR` by design and cannot use a temporary directory — and
`commitLeftovers` staged the tree with a bare `git add -A`
([kaizen-loop#374](https://github.com/kaizen-agents-org/kaizen-loop/pull/374),
[verifier#226](https://github.com/kaizen-agents-org/verifier/issues/226)).

A run whose actual change was an 8-line README section produced:

```
+925 −0    7 files changed
```

Six were `.kaizen/verifier/.verifier-artifacts-*/`, including `intent.txt` with
the full builder prompt — an information-disclosure surface in a public diff as
much as a size problem. Exclusions are now derived from
`dirname(config.verifier.resultPath)`, so this holds for any adopter wherever
they configure the result file.

### verifier v0.1.1 — verdicts were reached without the verification logs

`verify_commands` was empty and `evidence_grade` stayed `"reported"` even
though `cargo test` and `cargo clippy` had run and produced 338 lines of output
([kaizen-loop#357](https://github.com/kaizen-agents-org/kaizen-loop/issues/357),
[verifier#221](https://github.com/kaizen-agents-org/verifier/pull/221)).

Without this, every verdict rested on the builder's self-report — the exact
degradation `#120` was created to look for.

## Environment defects found alongside

These block adoption without being pipeline bugs.

| Issue | Problem |
|---|---|
| [`.github#214`](https://github.com/kaizen-agents-org/.github/issues/214) | The global npm prefix is neither stable nor exclusive. Under Volta/nvm it moves per Node version; two installations on one machine fight over the same link. |
| [`.github#215`](https://github.com/kaizen-agents-org/.github/issues/215) | `npm link` silently no-ops under a Volta shim — exit 0, nothing written — so the installer reports success while leaving dead commands on `PATH`. |
| [`.github#217`](https://github.com/kaizen-agents-org/.github/issues/217) | Workspaces are created `0755`; the broker requires `0700`. A fresh worktree per run means `chmod` is not a workaround. |
| [`.github#218`](https://github.com/kaizen-agents-org/.github/issues/218) | The documented broker startup passed the token via `sudo env`, placing it in argv where any local process could read it with `ps`. |
| [`kaizen-loop#371`](https://github.com/kaizen-agents-org/kaizen-loop/issues/371) | Broker socket validation reported every failure as a permission problem, including a missing socket — which sends the operator to audit directory ownership that was never at fault. |

## Still broken

- ~~**Workspaces are `0755`**~~ — **fixed in kaizen-loop `v0.1.7`**
  ([#217](https://github.com/kaizen-agents-org/.github/issues/217),
  [kaizen-loop#370](https://github.com/kaizen-agents-org/kaizen-loop/issues/370)).
  At the time of this run a scout needed `umask 077`, because workspaces were
  created `0755` while the broker requires `0700`. Workspaces and worktrees are
  now created private from the start and revalidated, so a run works under the
  usual `022`. This mattered more than the workaround suggested: a launchd job
  inherits launchd's umask rather than an interactive shell's, so scheduled runs
  were blocked outright.
- **Verifier false positive on test fixtures.** A shell stub made executable
  with `set_permissions(0o755)` was classified as "high-risk auth/authz code".
  Any change that creates an executable test fixture will trip this.
- **Scheduled runs and scout are not enabled** for the external target. The
  registry entry is `enabled: false` and the fleet was registered with
  `--no-scheduler`. This was deliberate: automating a pipeline that could not
  publish would have produced contaminated pull requests on a timer. The manual
  path is what this document verifies.
- **Downgrade is not possible.** Configs generated by `kaizen init` under
  v0.1.4+ use `expectedRef: refs/tags/...`, which the v0.1.3 schema rejects.

## What this says about the test strategy

The dogfood repositories could not have caught any of the four release-blocking
defects. They are mature: branch protection configured, labels present, SSH
remotes, tracking `main` rather than a pinned tag. Each of those differences is
exactly what hid a bug.

Two conclusions worth carrying forward:

1. **What needs reproducing is a greenfield repository, not another language.**
   No defect was Rust-specific. The exposure condition was "a repository where
   nothing has been set up yet, installed from pinned tags, over HTTPS."
2. **Contract tests between components are the gap.** The half-close bug
   survived because both sides were correct and well tested in isolation, and
   the boundary belonged to no repository's test suite.

## Design lessons for kaizen-loop

Patterns behind the individual defects, in rough order of how much they cost.

### Swallowed errors were the single largest cost

Three layers each discarded the reason a publication failed: `requestBroker`
rejected with one fixed string, `GitClient.push` used a bare `catch {}`, and
`resolveConfiguredBrokerSocket` wrapped every check in one try/catch. The result
was that "the broker is not running", "the repository is not allow-listed" and
"git rejected the push" were indistinguishable.

Diagnosing one failure required reading the broker source and reconstructing the
push by hand. The fix was cheap; finding it was not.

**Carry forward:** when an error crosses a process or repository boundary,
propagate a reason. Where the message cannot be trusted — an injected callback,
a socket response — forward a *code matched against an allow-list*, never the
raw text. Both patterns are now in `src/utils/command.ts`.

### Success was reported for states that were not successful

`install-kaizen.sh` printed "Kaizen toolchain installed" after `npm link`
silently no-oped, and wrote `.installed-version` so the next run saw a converged
install. `commitLeftovers` proceeded on a dirty tree that produced an empty
index. `doctor` passed while every GitHub operation was broken, because without
a registered project it returned before reaching them.

**Carry forward:** a step that can partially fail should verify its own
postcondition before reporting success, and should not record state it did not
achieve. `install-kaizen.sh` checking that the resolved command points into
`$KAIZEN_HOME` is the shape to copy.

### Messages sent operators to the wrong place

`KAIZEN_GITHUB_TOKEN_SOCKET must resolve to a root-owned broker socket in
immutable root-owned directories` was emitted for a missing socket. The
ownership and permissions were entirely correct; the broker simply was not
running. `Verification | not configured` in the result comment means
`verifyResults` is empty, not that commands are unconfigured.

**Carry forward:** name the condition that actually failed and the object it
failed on. A message that describes a plausible-but-wrong cause is worse than a
generic one, because it is actionable in the wrong direction.

### Harness artifacts must not be able to reach a pull request

The verifier's scratch landed in the work branch because it is written inside
the checkout and the commit step staged everything. The size was the visible
symptom; `intent.txt` reaching a public diff was the real problem.

**Carry forward:** treat anything the harness writes into the workspace as
untrusted for commit purposes, and derive exclusions from configuration rather
than hard-coded paths so they hold for any adopter layout.

### Test-mode branches hide the paths that matter

The broker's `childIdentity` returns `{}` under `--test-mode`, so its privilege
downgrade was never exercised by its own tests. Mocked runners returned exit 0
for every git call, which reads as "nothing staged" — the exact condition the
new guard exists to detect.

**Carry forward:** where semantics live in an external tool (git pathspecs,
process identity, socket framing), test against the real thing. Two defects in
the scratch-exclusion change passed a fully mocked suite and were caught only by
running real `git`.

### Defaults assumed a machine that adopters may not have

`npm prefix -g` is not stable under Volta or nvm. The global link is not
exclusive when two installations share a prefix. `os.tmpdir()` under `/tmp` is
wiped on reboot. Each was fine on the dogfood machine.

**Carry forward:** resolve and record the environment actually used rather than
assuming a canonical one, and fail loudly when a version manager shadows an
installed command.

### Sequencing: do not automate a pipeline that cannot complete manually

Scheduled runs were deliberately left disabled throughout. Had they been on, the
harness would have produced contaminated pull requests on a timer for the entire
period publication was broken — three issues were sitting labelled
`kaizen:authorized` and would have been picked up.

**Carry forward:** enable automation one layer at a time, after the layer below
completes by hand.

## Reproducing

```sh
onboarding/scripts/install-kaizen.sh          # pinned set from versions.json
kaizen doctor --repair --project <slug>       # expect all checks passing
KAIZEN_GITHUB_TOKEN_SOCKET=/opt/kaizen/run/github-publication.sock \
  kaizen fix <issue> --project <slug> --yes
```

The broker must be running and allow-listed for the target repository; see
[`onboarding/ADOPTING.md`](../onboarding/ADOPTING.md). Confirm the resolved
commands point into `$KAIZEN_HOME/toolchain/` before trusting any result —
`readlink "$(npm prefix -g)/lib/node_modules/kaizen-loop"` — because a command
resolving to a different installation is the failure mode that cost the most
time in this run.
