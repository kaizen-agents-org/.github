# Scout Contract

A scout finds work that has not been filed yet and files it as an issue. It is
the layer that makes a repository improve without someone deciding, each time,
what to improve. Without it the loop only runs as often as a human writes
issues.

This document defines what a scout must do to be called one. It says nothing
about which model finds the work, what it looks for, or what runs it on a
schedule — those belong to the prompt and to the runner. Any implementation
that satisfies everything below is a conforming scout.

## Why the contract is separate from the runner

The organization's own scout runs as a Codex automation. That is one runner, not
the definition. A scout that only exists as a Codex automation cannot be adopted
by anyone who does not use Codex, and a contract expressed only as prompt text
cannot be checked.

Separating them means:

- **The prompt decides what to look for.** Test coverage, documentation drift,
  dead code, dependency risk — that is a prompt concern, and different targets
  will want different things.
- **The runner decides when and where.** GitHub Actions, Codex Automation,
  Claude Routines, or a person pasting the prompt into a chat window.
- **The contract decides what may reach GitHub.** This is the part that must not
  vary, because it is what makes an unattended scout safe to point at a
  repository.

## Required behaviour

A conforming scout satisfies all of the following.

### 1. Issues only

It creates GitHub issues. It does not edit files, create or push branches, open
or merge pull requests, or modify existing issues.

This is the boundary that makes everything else tolerable. A scout that can only
file issues cannot damage a repository, whatever its prompt says or however
badly it misjudges a finding — the worst case is noise a maintainer closes.

### 2. Default branch as the only source

Evidence comes from the target repository's default branch. Local-only,
feature-branch-only, uncommitted, or stale content is not evidence.

A scout reading a runner's working directory would file issues about whatever
happened to be checked out there. Resolve the default branch explicitly and read
from it.

### 3. Explicit target on every operation

Every read and every mutation names the target repository explicitly — `--repo
owner/name` or the equivalent API parameter. A scout never inherits a repository
from the runner's current directory.

When a local checkout is used for speed, its `origin` must resolve to the
configured target before it is trusted; a missing, ambiguous, fork, or different
origin means falling back to reading the repository through the API.

### 4. Per-run creation limit

At most a configured number of issues per run, between 1 and 2. Findings beyond
the limit stay in the report.

### 5. Backlog stop condition

No new issues when the target already has enough open work: a configured limit
on open issues carrying the intake label, and a configured limit on open
generated pull requests.

This is what stops an unattended scout from filling a backlog nobody is
draining. A scout that runs three times a day against a repository nobody is
working on must go quiet, not accumulate.

### 6. Duplicate suppression

Before creating an issue, check that no open issue or pull request in the target
already covers the same work. When several issues own the same work, the
canonical one is chosen deterministically — open before closed, then earliest
`createdAt`, then lowest number — and duplicates point at it, never the reverse.

Normal runs do not close, reopen, or relabel anything. Reconciling existing
duplicates is a separate, explicitly authorized operation.

### 7. Labels are explicit and never assumed

Only the configured labels are applied. If a configured label cannot be verified
and applied, the scout fails closed and creates nothing rather than filing an
issue that will not be picked up — or, worse, one that is picked up by the wrong
gate.

**Execution authorization is not a scout decision.** In this organization's own
repositories, the scout applies `kaizen:authorized` and `kaizen:ready` as a
deliberate dogfooding policy: the organization has accepted that its own scout
may queue work for immediate execution. That policy does not travel. A scout
pointed at any other repository applies only the labels its operator configured,
and authorization stays a maintainer action.

An adopter whose scout silently marked its own findings as authorized would have
an unattended agent choosing its own work and starting it. Keep the two gates
separate.

### 8. Ready without clarification

An issue is only filed when it can go to the next run as written — concrete
evidence, a bounded change, no open question for a human to answer first.

A finding that needs discussion is a report line, not an issue.

## Configuration a runner must supply

| Input | Meaning |
| --- | --- |
| Target repository | `owner/name`, explicit |
| Labels | Applied to created issues; must include the intake label the loop filters on |
| Creation limit | Issues per run (1–2) |
| Open-issue limit | Stop when the target has this many open intake-labelled issues |
| WIP limit | Stop when the target has this many open generated pull requests |

## Permissions a runner must grant

- Read repository contents on the default branch
- Read issues, pull requests, and labels
- Create issues and apply existing labels

Write access to contents is not required and should not be granted. A scout that
cannot push is a scout that cannot push by accident.

Creating a *missing* label needs write permission on labels; a scout without it
must fail closed rather than file an unlabelled issue, and the operator
pre-provisions the labels instead.

## Runners

| Runner | Status | Notes |
| --- | --- | --- |
| GitHub Actions | **Default** | Fewest prerequisites: a repository and a model credential. Runs in a clean environment, and its logs are visible to anyone with repository access. See [`../onboarding/automations/scout.workflow.yml`](../onboarding/automations/scout.workflow.yml). |
| Codex Automation | Optional | What this organization runs today; see [`repo-improvement-scout.md`](./repo-improvement-scout.md). |
| Claude Routines | Optional | Not yet wired. |
| Manual | Optional | Paste the rendered prompt into any agent session. Useful for evaluating a prompt before scheduling it. |

GitHub Actions is the default because it assumes the least. Codex Automation and
Claude Routines both require an account with that provider; Actions requires a
repository, which an adopter necessarily has.

The trade is honest and worth stating: with Actions, the model call is yours to
make and pay for, and the credential lives in repository secrets. With a
provider's own automation layer, the execution environment comes with the
subscription. Fewer prerequisites, more visible cost.

## Checking conformance

Behaviour that can be verified without running a model:

- The runner passes an explicit target, and nothing in the configuration depends
  on the runner's working directory.
- Configured limits are within range and are actually passed to the prompt.
- Granted permissions do not include write access to contents.
- The rendered prompt states the issues-only boundary, the default-branch rule,
  the limits, and the label policy.

`onboarding/scripts/enable-scout.sh` performs these checks when rendering a
per-repository scout, and refuses to install one that would violate them.

What cannot be checked mechanically is whether the findings are any good. That
is a prompt-quality question, and it is why the creation and backlog limits
exist: a scout is allowed to be wrong occasionally, as long as being wrong is
cheap and bounded.
