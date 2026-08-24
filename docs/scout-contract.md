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

The organization's own scout runs as a Codex automation. That is one
implementation, not the definition. A scout that only exists as a Codex
automation cannot be adopted by anyone who does not use Codex, and a contract
expressed only as prompt text cannot be checked.

Separating them means:

- **The prompt decides what to look for.** Test coverage, documentation drift,
  dead code, dependency risk — that is a prompt concern, and different targets
  will want different things.
- **The implementation decides when it runs and how a model is reached.**
- **The contract decides what may reach GitHub.** This is the part that must not
  vary, because it is what makes an unattended scout safe to point at a
  repository.

## Three implementations

The rules below are identical for all three. What differs is *who enforces
them*, and that difference is worth being explicit about.

| Implementation | Schedule | Model | Who applies the rules | Status |
| --- | --- | --- | --- | --- |
| Codex Automation | Codex app | Codex | The agent, by following its prompt | In use |
| Agent on GitHub Actions | Actions schedule | Any coding agent with an API key | The agent, inside a wrapper that enforces the limits before `gh issue create` | Available |
| Claude Routines | Routines | Claude | The agent, by following its prompt | [Not yet wired](https://github.com/kaizen-agents-org/.github/issues/227) |
| API client | cron, launchd, CI — anything that runs a command | Any OpenAI-compatible endpoint | The client, in code | Available: `onboarding/automations/scout-api-client.mjs` |

The difference that matters is **how far the enforcement sits from the model**.

**Agent implementations** run the whole scout in one session: read the
repository, count what is open, create the issue. Where the host allows it, the
limits can still be enforced outside the model — the Actions implementation
gives the agent a wrapper script instead of raw `gh`, and that script re-checks
the creation, WIP, and open-issue limits and refuses to proceed past them. Codex
Automation and Claude Routines have no such seam today: their limits live in the
prompt, because that is the only place they can live.

**The API client** moves the enforcement out entirely. A model API
cannot create an issue, so the work splits by construction:

- the **model** reads the repository content it is given and returns candidate
  findings as JSON — see
  [`scout.findings.schema.json`](../onboarding/automations/scout.findings.schema.json)
- the **client** applies every limit, checks for duplicates, attaches labels, and
  makes the only GitHub write

One consequence is unique to that ordering: the backlog check runs *before* the
model is called, so a scout pointed at a repository with a full queue costs
nothing. Every agent implementation has to call the model to find that out.

The client also has no provider of its own. Any endpoint speaking the
OpenAI-compatible shape works; switching between them is a base URL and a
credential, not a second implementation. That includes a local gateway holding a
subscription credential, which is how a scout runs without a separate metered
bill.

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
pull requests, regardless of provenance.

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
Every created issue includes a `PR linkage requirement` section that requires
an implementation PR to use a GitHub closing keyword and to verify the expected
`closingIssuesReferences` before it is reported ready.

A finding that needs discussion is a report line, not an issue.

## Configuration a runner must supply

| Input | Meaning |
| --- | --- |
| Target repository | `owner/name`, explicit |
| Intake label | Explicit label used for the open-issue backlog check; must be present in Labels |
| Labels | Applied to created issues; must include the intake label the loop filters on |
| Creation limit | Issues per run (1–2) |
| Open-issue limit | Stop when the target has this many open intake-labelled issues |
| WIP limit | Stop when the target has this many open pull requests, regardless of provenance |

## Permissions a runner must grant

- Read repository contents on the default branch
- Read issues, pull requests, and labels
- Create issues and apply existing labels

Write access to contents is not required and should not be granted. A scout that
cannot push is a scout that cannot push by accident.

Creating a *missing* label needs write permission on labels; a scout without it
must fail closed rather than file an unlabelled issue, and the operator
pre-provisions the labels instead.

## The API client

The reference implementation is
[`../onboarding/automations/scout-api-client.mjs`](../onboarding/automations/scout-api-client.mjs).
It is deliberately a single Node.js command with no package dependency. Issue
[#229](https://github.com/kaizen-agents-org/.github/issues/229) tracks its
implementation and contract tests.

The client is one command. Whatever starts it — cron, launchd, a CI schedule —
supplies only timing.

```
1. Read configuration: target, labels, limits, model endpoint.
2. Ask GitHub what is already open.
3. Stop here if a limit is already reached. No model call, no cost.
4. Send the prompt and the repository content to the model,
   requiring scout.findings.schema.json as the response shape.
5. Validate the response against the schema. Reject it if it does not match;
   do not repair it.
6. Drop findings that duplicate an open issue or pull request.
7. Create up to the creation limit, applying the configured labels.
8. Report what was filed and what was skipped.
```

Step 3 matters more than it looks. The backlog check happens *before* the model
is called, so a scout pointed at a repository with a full queue costs nothing at
all. An agent implementation has to call the model to find that out.

Steps 5 through 7 are where the contract is enforced. The model's output is
data, and it is treated as such: a finding that fails validation is discarded
rather than fixed up, and one that duplicates existing work never reaches
`gh issue create`.

### Running the reference client

Create a configuration file with an explicit repository and all limits. The
`labels` array is never inferred; every configured label must already exist.

```json
{
  "target": "owner/repository",
  "intakeLabel": "kaizen",
  "labels": ["kaizen"],
  "openIssueLimit": 4,
  "wipLimit": 4,
  "creationLimit": 2,
  "model": {
    "baseUrl": "http://127.0.0.1:8080/v1",
    "name": "scout"
  },
  "prompt": "Find bounded, evidence-backed improvements."
}
```

Run it with `node onboarding/automations/scout-api-client.mjs CONFIG.json`.
Set `SCOUT_MODEL_API_KEY` for a metered endpoint; do not put credentials in the
configuration file. The client reads the default branch and repository content
through explicit `gh api` calls, stops before the model when backlog or WIP is
full, validates the response locally, and uses `gh issue create` as its only
GitHub write. A local gateway is supported by changing only `baseUrl`, the
credential, and model name; no provider-specific branch is used.

### Model endpoint

Any endpoint accepting an OpenAI-compatible request works. The client needs a
base URL, a credential, and a model name; it has no provider-specific code.

| Endpoint | Credential | Billing |
| --- | --- | --- |
| `https://api.anthropic.com/v1` | API key | Metered, separate from any subscription |
| `https://api.openai.com/v1` | API key | Metered, separate from any subscription |
| A local gateway on `127.0.0.1` | Gateway token | Whatever subscription the gateway holds |

The third row is how a scout runs without a second bill: a local gateway
authenticated with an existing subscription exposes an OpenAI-compatible
endpoint, and the client cannot tell the difference. It does constrain the
schedule to a machine that can reach the gateway — a hosted CI runner cannot.

### Structured output

The model must return JSON matching
[`scout.findings.schema.json`](../onboarding/automations/scout.findings.schema.json).
The schema is deliberately small — no `$ref`, no `oneOf`, no `format`, no
`pattern` — because constrained decoding implementations accept different
subsets, and a schema that only works on one endpoint would undo the point of
having one client.

When an endpoint supports constrained decoding, pass the schema to it. When it
does not, validate the response locally and discard anything that does not
conform. Either way the client validates before acting: an endpoint's promise
that output matches a schema is not a reason to skip checking.

## Agent implementations

Codex Automation and Claude Routines each run the whole scout inside one agent
session. They need no client, because the session can already read the
repository, query GitHub, and create issues.

The rules are unchanged, but they are carried in the prompt rather than in code.
The prompt must state the issues-only boundary, the default-branch rule, every
limit, and the label policy — an agent that is not told a limit will not observe
it. `enable-scout.sh` renders exactly that prompt.

- **Codex Automation** — what this organization runs today; see
  [`repo-improvement-scout.md`](./repo-improvement-scout.md).
- **Claude Routines** — see
  [#227](https://github.com/kaizen-agents-org/.github/issues/227) for the
  wiring, and for two ways Routines diverges from the contract.

Pasting a rendered prompt into an agent session by hand is the same shape
without a schedule, and is the cheapest way to judge a prompt before automating
it.

## Checking conformance

For every implementation, without running a model:

- The target is explicit, and no configuration depends on a working directory.
- Configured limits are within range and reach whatever enforces them.
- Granted permissions do not include write access to contents.

`onboarding/scripts/enable-scout.sh` performs these checks when rendering a
per-repository scout and refuses to render one that would violate them.

How much more can be checked depends on where the enforcement sits.

**Where the agent is given a wrapper instead of raw `gh`** — as in the Actions
implementation — the wrapper's refusals are testable without a model, and
`test-scout-fleet-contract.sh` exercises them: the creation, WIP, and open-issue
limits, and the exact label set.

**Where the limits live only in the prompt** — Codex Automation and Claude
Routines today — the rendered prompt can be asserted to state the issues-only
boundary, the default-branch rule, the limits, and the label policy, but whether
the agent observes them only shows up in what it files.

**The API client** moves one more thing inside the testable boundary. Because it
decides *whether to call the model at all*, this becomes checkable:

- a backlog at the limit produces no model call
- a response violating the schema is rejected rather than repaired
- a finding matching an open issue is dropped before creation

The first of those is the one no agent implementation can offer: a wrapper can
refuse to file, but the model has already run and already cost something.

What no implementation can check mechanically is whether the findings are any
good. That is a prompt-quality question, and it is why the creation and backlog
limits exist: a scout is allowed to be wrong occasionally, as long as being
wrong is cheap and bounded.
