# Adopting the Kaizen harness in your repository

This guide is for a maintainer adding the Kaizen issue-to-pull-request loop to a
repository they own. You need `git`, `gh` (authenticated), Node 20 or newer,
`pnpm`, and administrator rights on the repository if you want the branch
protection applied for you.

The toolchain is built from source at its pinned tags rather than installed as
prebuilt packages, so the first install compiles three repositories and takes a
few minutes. `pnpm` is needed because one of them is a pnpm workspace.

> **Status: v0.1.0 is published.** All three components are tagged and
> `install-kaizen.sh` installs them. This flow has been verified end to end on
> macOS; it has not yet been exercised by a third-party maintainer on a machine
> nobody here controls, so expect rough edges and please report them.

## Install

`onboard.sh` needs its sibling assets — `versions.json`, `profiles/`, and the
helper scripts — so run it from a checkout of this repository, pointed at the
repository you are onboarding. Piping it straight from `curl` does **not** work:
the script would look for those files inside your target repository and stop at
the first missing one.

```sh
git clone https://github.com/kaizen-agents-org/.github kaizen-onboarding
cd /path/to/my-product
sh /path/to/kaizen-onboarding/onboarding/onboard.sh
```

Pin the clone to a release tag once one exists, so the kit you onboard with is
reproducible.

It walks eight steps and stops to ask you three things. Those three are the
decisions you own; everything else is mechanical:

1. **The verification commands.** Kaizen proposes them from your manifests
   (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`), then
   prints the generated commands and waits. What counts as "verified" here is
   the root of the whole trust model, so you approve the actual commands after
   reading them, not the idea of generating them. Decline to stop the run, edit
   `.kaizen/config.yml`, and re-run; your edits are kept.
2. **Branch protection.** This uses administrator rights, so it is a separate,
   explicit yes. Skip it with `--skip-protection` and apply your own policy
   instead; the contract check will report it as missing until an equivalent
   policy is in place.
3. **The smoke run.** It opens a real sandbox issue and pull request on your
   repository to prove the loop works end to end.

For an unattended run, name the profile and required check up front:

```sh
onboarding/onboard.sh --yes --profile pilot-python --check test
```

`--yes` refuses to run without `--profile` and `--check`: an unattended run
should not invent your throughput policy or guess a status-check name.

## Choose a profile

A profile sets throughput and risk appetite. Start with the `pilot-*` matching
your stack — one issue per run, one open pull request — and move to
`standard.yml` once you have weekly evidence that the review load is
sustainable. See [`profiles/README.md`](./profiles/README.md).

Four settings are not a profile's to decide, and one that sets them is rejected
outright: `policy.mode` stays `pr-only`, `verifier.enabled` stays `true`,
`safety.operationMode` stays `external`, and `commands.verify` stays whatever
you confirmed for this repository. Setting an ancestor counts as setting the
path, so a profile cannot delete one by replacing the block above it.

The protected-path floor and the concurrency cap are restored rather than
rejected, since a profile can weaken those by omission, and `kaizen init` prints
a warning naming what it corrected.

## What lands in your repository

```text
.kaizen/config.yml                    the contract: commands, policy, schedule
.github/ISSUE_TEMPLATE/kaizen.yml     how Kaizen issues get filed
docs/smoke-runs/<timestamp>.json      evidence the loop completed once
skills/ + skills-manifest.json        vendored skills and their digests
```

Commit all of it. `~/.kaizen/` holds local state (registry, workspaces, logs)
and belongs on your machine, not in the repository.

## Scheduled runs

`kaizen init` writes the job definitions into `.kaizen/config.yml`, and
`onboard.sh` then runs `kaizen scheduler sync` to register them with launchd or
cron — so installing and scheduling happen in the same command. If you run
`kaizen init` by hand instead, run `kaizen scheduler sync` yourself afterwards,
or nothing will ever run on a schedule.

Inspect or change the jobs with:

```sh
kaizen scheduler status   # show configured jobs
kaizen scheduler plan     # show what sync would install
kaizen scheduler sync     # register jobs with launchd or cron
kaizen scheduler disable  # stop scheduled runs
```

Scheduled runs execute from a dedicated clone under `~/.kaizen/runtime/`, not
from your checkout, so an update can never reset your working tree. Set
`KAIZEN_RUNTIME_REF` to the tag pinned in `versions.json` so scheduled runs stay
on released code:

```sh
export KAIZEN_RUNTIME_REF=v0.1.0
```

Without it the runtime follows `main`, which is what the Kaizen organization's
own repositories want and almost certainly not what you want.

## Staying up to date

**Re-run the same command with `--refresh-manifest`.** There is no separate
upgrade procedure:

```sh
onboarding/onboard.sh --profile <your-profile> --refresh-manifest
```

`--refresh-manifest` is what makes an update converge. Your checkout records the
set you installed, so without it the re-run reinstalls exactly those versions.
With it, the upstream pinned set is fetched and validated first, and your
`onboarding/versions.json` is updated — commit it along with the run's other
changes.

The run is otherwise idempotent. Steps already done are skipped, components move
to the newly pinned versions, and the contract is re-checked afterwards. Because
a compatible set is published as a unit, you never end up with a half-updated
toolchain. A malformed or unreachable upstream manifest aborts the run and
leaves your working set untouched.

To be told when an update exists, schedule the update check against your
repository:

```sh
onboarding/scripts/check-toolchain-update.sh --repo <owner>/<repo>
```

It compares your installed manifest against upstream and opens **one** issue
when they differ. It never changes anything: applying an update stays your
deliberate re-run. Add `--dry-run` to see the comparison without filing
anything.

## Checking your setup

```sh
kaizen doctor --repair                                   # local prerequisites
onboarding/scripts/check-onboarding-contract.sh .        # acceptance gate
```

The contract checker is read-only. It validates the **final**
`.kaizen/config.yml`, so hand-editing the file after install cannot slip a
weakened safety floor past it. Every failure prints a remediation line.

## If something goes wrong

- **"no tag vX.Y.Z"** — `versions.json` pins a release that was never
  published. The installer stops rather than falling back to a branch, because
  that would run unreleased code behind a pinned manifest.
- **A command runs but behaves like an old version** — check what it resolves
  to with `readlink "$(npm prefix -g)/lib/node_modules/kaizen-loop"`. It should
  point into `$KAIZEN_HOME/toolchain/`. An older global install left on `PATH`
  can shadow the pinned one.
- **Contract check fails after install** — read the remediation lines; the
  usual causes are a skipped smoke run (no artifact) or skipped branch
  protection.
- **A partial run** — re-run the same command. It resumes rather than starting
  over.
- **`kaizen doctor` reports a missing command** — `builder-agent` and
  `verifier` must be on `PATH`; re-run `install-kaizen.sh`.

## Trust boundary

Issue authors are treated as untrusted input, but **who may trigger a run is a
repository permission**: execution requires the `kaizen:authorized` label, which
only a user with write access can apply. Before opening this up to issues from
outside contributors, read [`../docs/external-readiness-2026-07-08.ja.md`](../docs/external-readiness-2026-07-08.ja.md)
for the current limits.
