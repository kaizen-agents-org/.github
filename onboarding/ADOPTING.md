# Adopting the Kaizen harness in your repository

This guide is for a maintainer adding the Kaizen issue-to-pull-request loop to a
repository they own. You need `git`, `gh` (authenticated), Node 20 or newer, and
administrator rights on the repository if you want the branch protection applied
for you.

> **Status: not yet installable.** `onboarding/versions.json` pins all three
> components to `v0.1.0`, and none of those tags has been published, so
> `install-kaizen.sh` stops with a "no tag" error by design rather than
> installing unreleased code. Everything below is the intended flow; it becomes
> runnable once a compatible release set exists (see
> [`docs/release-tags.md`](../docs/release-tags.md)).

## Install

Run this from inside the repository you want to onboard:

```sh
onboarding/onboard.sh
```

It walks seven steps and stops to ask you three things. Those three are the
decisions you own; everything else is mechanical:

1. **The verification commands.** Kaizen proposes them from your manifests
   (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`), but
   what counts as "verified" here is the root of the whole trust model, so you
   confirm it. Review the generated `.kaizen/config.yml` before committing.
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

Three settings are not yours to lower, and a profile that sets them is rejected:
`policy.mode` stays `pr-only`, `verifier.enabled` stays `true`, and
`safety.operationMode` stays `external`. The protected-path floor and the
concurrency cap are restored rather than rejected, and `kaizen init` prints a
warning naming what it corrected.

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

**Re-run the same command.** There is no separate upgrade procedure:

```sh
onboarding/onboard.sh --profile <your-profile>
```

It is idempotent. Steps already done are skipped, components move to the newly
pinned versions, and the contract is re-checked afterwards. Because a compatible
set is published as a unit, you never end up with a half-updated toolchain.

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

- **"no tag vX.Y.Z"** — the pinned release has not been published. This is
  expected today; see the status note at the top.
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
