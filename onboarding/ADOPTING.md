# Adopting the Kaizen harness in your repository

This guide is for a maintainer adding the Kaizen issue-to-pull-request loop to a
repository they own. You need `git`, `gh` (authenticated), Node 20 or newer,
`pnpm`, either a running GitHub publication broker for the usual HTTPS clone or
a working SSH origin, and
administrator rights on the repository if you want the branch protection
applied for you.

The toolchain is built from source at its pinned tags rather than installed as
prebuilt packages, so the first install compiles three repositories and takes a
few minutes. `pnpm` is needed because one of them is a pnpm workspace.

> **Status: the pinned set installs.** `onboarding/versions.json` pins
> `kaizen-loop v0.1.3`, `builder-agent v0.1.0`, and `verifier v0.1.0`, and a
> clean install from that set produces three working commands. This has been
> verified on macOS only, and no third-party maintainer has yet run it on a
> machine nobody here controls, so expect rough edges and please report them.

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

## Configure publication authentication

Kaizen supports two Git publication paths. The effective publication URL is
the value of `git remote get-url --push origin`, which may differ from the
fetch URL. An HTTPS publication URL requires the credential-separated broker
described below. An SSH publication URL, such as
`git@github.com:owner/repository.git`, publishes with the runner account's SSH
identity and does not use `KAIZEN_GITHUB_TOKEN_SOCKET`. For unattended SSH
publication, make sure the runner can authenticate without a prompt and already
trusts GitHub's host key. The publication process ignores custom user SSH
configuration, so use a default identity or `SSH_AUTH_SOCK`; verify
non-destructive write access in the exact runner environment before onboarding:

```sh
publication_url=$(git remote get-url --push origin)
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND='ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=yes' \
  git push --dry-run "$publication_url" \
    "HEAD:refs/heads/kaizen-onboarding-auth-check-$$"
```

Kaizen does not put a GitHub token in `smoke`, `run`, or any builder process.
For an HTTPS publication URL, a small root-owned broker validates one specific push and
performs it in a separate process. Install the broker in a root-owned location,
create a socket directory whose entire path is root-owned and not group- or
world-writable. Name the unprivileged account that runs Kaizen so request
validation cannot gain root privileges:

```sh
kaizen_group=kaizen-publisher # create this group with only the Kaizen runner
kaizen_gid=1234              # replace with that group's numeric GID

sudo install -o root -g "$kaizen_group" -m 0755 \
  onboarding/scripts/kaizen-publication-broker.mjs \
  /usr/local/libexec/kaizen-publication-broker
sudo install -d -o root -g "$kaizen_group" -m 0755 /opt/kaizen/run

sudo env KAIZEN_PUBLICATION_BROKER_TOKEN="$(gh auth token)" \
  /usr/local/libexec/kaizen-publication-broker \
    --socket /opt/kaizen/run/github-publication.sock \
    --socket-gid "$kaizen_gid" \
    --run-uid "$(id -u)" \
    --run-gid "$kaizen_gid" \
    --runtime-dir /var/tmp \
    --allow owner/repository:main
```

Use the default branch after the colon in every `--allow` entry. Repeat
`--allow` when one broker serves several repositories. The broker refuses tags,
the configured default branch, repositories outside this list, and any request
whose commit does not match the source branch tip. It creates the socket as
`root:<socket-gid>` with mode `0660`; `--socket-gid` and `--run-gid` must name
the same dedicated group whose only member is the Kaizen runner. The broker also
requires the request checkout to be owned by that runner with mode `0700`. The
broker refuses to start when
any directory above the socket is group- or world-writable. On macOS,
`/var/run` is group-writable and is refused, while `/opt/kaizen/run` created as
above passes the ownership checks.

The root-only Git and askpass workspace defaults to `/var/tmp`. If that
filesystem is mounted `noexec`, create a root-owned executable directory and
pass it with `--runtime-dir`; its ancestors must not be group- or world-writable.

Run the broker under a root service manager so it starts before scheduled
Kaizen jobs and restarts after token rotation. The token belongs only in that
service's environment. Broker logs contain refusals and successful repository,
branch, and commit identifiers, but never the credential. If startup reports an
existing socket, verify that no broker is running and remove that exact stale
socket before restarting; the broker never replaces an existing path.

Validation of the caller-controlled checkout runs as `--run-uid/--run-gid`.
The final credentialed Git process remains inside the root broker because the
token must not become observable to builder code running as that same account.
It uses a new root-only bare repository, ignores caller Git configuration and
hooks, and reads only the already-validated object database. This still makes
the broker a narrow high-privilege boundary: keep Node and Git patched, use a
repository-scoped token, and allow-list only repositories this machine must
publish.

In the shell or service definition that starts Kaizen, configure only the
socket—not the token:

```sh
export KAIZEN_GITHUB_TOKEN_SOCKET=/opt/kaizen/run/github-publication.sock
```

`onboard.sh` inspects the effective push URL before it installs the toolchain or
begins the smoke pass. HTTPS publication without this setting is rejected, and
SSH publication must pass the non-interactive dry-run push above. The broker
still validates the full request; the environment check is only an early
configuration error.

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
.kaizen/.gitignore                    excludes regenerated onboarding observations
.github/ISSUE_TEMPLATE/kaizen.yml     how Kaizen issues get filed
docs/smoke-runs/<timestamp>.json      evidence the loop completed once
skills/ + skills-manifest.json        vendored skills and their digests
```

Commit all of the files listed above. `.kaizen/onboarding-observations.json` is
different: `onboard.sh` regenerates this live labels and branch-protection
snapshot for the contract checker, and `.kaizen/.gitignore` keeps it out of
commits. On an upgrade, `onboard.sh` also removes a previously committed snapshot
from the index while leaving the refreshed local file in place. In contrast,
`docs/smoke-runs/*.json` is durable acceptance evidence
and should be committed. `~/.kaizen/` holds local state (registry, workspaces,
logs) and belongs on your machine, not in the repository.

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

Read it from the manifest rather than typing a version, so it cannot drift out
of step with the pinned set:

```sh
export KAIZEN_RUNTIME_REF=$(node -p "require('./onboarding/versions.json')['kaizen-loop']")
```

Without it the runtime follows `main`, which is what the Kaizen organization's
own repositories want and almost certainly not what you want. Pinning it to a
superseded tag is worse than either: `v0.1.0` in particular ships a
non-executable CLI.

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

## Removing the harness

If you trial Kaizen and decide against it, run this from the repository:

```sh
onboarding/scripts/uninstall-kaizen.sh --dry-run   # see the plan first
onboarding/scripts/uninstall-kaizen.sh
```

It stops the scheduled jobs and removes this project's local state — its
registry entry and its workspace under `~/.kaizen/`. Re-running is safe.

It needs `kaizen` on `PATH` to stop the jobs, and refuses to run without it.
Removing the registry entry while launchd or cron still hold jobs would leave
automation firing for a project nothing knows about, behind a successful-looking
uninstall.

**It deliberately leaves three things alone**, and prints the exact commands
for each:

- **Repository files** (`.kaizen/`, the issue template, vendored skills, smoke
  artifacts). The printed cleanup first removes the ignored generated
  `.kaizen/onboarding-observations.json`, then stages removal of the committed
  files so the repository change remains a commit you author.
- **Labels.** Deleting a label strips it from every issue that ever carried it,
  including closed ones.
- **Branch protection, issues, and pull requests.** Protection is an
  administrative decision you may want to keep, and the issues and pull requests
  the loop opened are project history.

The toolchain under `~/.kaizen/toolchain/` is shared by every repository you
onboarded on this machine, so it also survives. Pass `--remove-toolchain` to
remove it and its global links once you are uninstalling the last one.

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
