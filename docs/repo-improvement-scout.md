# Repository Improvement Scout

The Kaizen Agents organization uses a Codex automation named `Kaizen Agents repo improvement scout` to actively find small, repo-local improvement issues for the normal Kaizen issue-to-PR loop.

The scout is the improve layer in the [Automation Roles](./automation-roles.md) model. It is separate from [Organization Monitor](./org-monitor.md): the organization monitor is conservative coordination health checking, while the scout is proactive backlog discovery.

The GitHub-managed source prompt for the Codex automation lives at [`../automations/kaizen-agents-repo-improvement-scout.prompt.md`](../automations/kaizen-agents-repo-improvement-scout.prompt.md). The local Codex runtime copy under `$CODEX_HOME/automations/kaizen-agents-repo-improvement-scout/automation.toml` should be treated as a synced copy, not the source of truth.

## Runtime Cadence

The scout runs on the frequent organization automation cadence: daily at 02:45, 10:45, and 18:45 in the local Codex automation schedule.

This cadence is intentionally higher than the organization monitor because the scout owns proactive, repo-local improvement discovery. The organization monitor runs later in the nightly window as a conservative coordination check.

## Scope

There are two supported scout deployment modes.

The fixed organization-wide scout actively scans these four implementation and
coordination repositories:

| Area | Repository |
| --- | --- |
| Organization docs and automation sources | `kaizen-agents-org/.github` |
| Builder component | `kaizen-agents-org/builder-agent` |
| Orchestrator component | `kaizen-agents-org/kaizen-loop` |
| Independent verifier component | `kaizen-agents-org/verifier` |

`coderabbit` and `renovate-config` are downstream shared-configuration repositories. They are not scout targets. They may appear only as sync context for a `.github` finding.

An opt-in per-repository scout rendered from
[`../onboarding/automations/scout.prompt.template.md`](../onboarding/automations/scout.prompt.template.md)
and enabled through [`../onboarding/scripts/enable-scout.sh`](../onboarding/scripts/enable-scout.sh)
scans exactly its explicitly configured `owner/repository`. That target may be a
newly onboarded organization repository or an external repository; it does not
need to appear in the fixed organization-wide list. Enabling one target does not
expand the fixed scout or authorize any other repository. The four fixed targets
cannot also be enabled as per-repository scouts; enablement rejects those
repository identities case-insensitively to prevent duplicate discovery and
issue creation.

## What It Looks For

The scout looks for bounded, evidence-backed improvements that can become one focused PR:

- `.github`: documentation, automation prompt, sync-source, and organization guidance gaps.
- `builder-agent`: implementation artifact quality, self-review quality, adapter/CLI behavior, backend/model selection, fallback behavior, build-result schema fidelity, and verifier-consumable outputs.
- `kaizen-loop`: orchestration, workspace lifecycle, issue intake, verification execution, verifier integration, policy, PR creation/linkage, scheduler behavior, run reporting, and fleet commands.
- `verifier`: independent review depth, verdict quality, schema fidelity, eval harnesses, seeded/golden corpus, false-positive controls, and reproducibility.

The scout should not create operation, sync, scheduler, CI, source-order, or readiness-review issues unless the finding is also a concrete repo-local improvement in the target repository. Those concerns belong to the monitor or readiness-review layer.

## Issue Creation

The scout may create `[scout]` issues when all of these are true:

- the target is either one of the fixed organization-wide scout repositories or
  the explicit target of a reviewed opt-in per-repository scout installation;
- default-branch docs or code provide concrete evidence;
- the work is not already covered by an open issue or PR in that target repository;
- the issue is ready for the next Kaizen run without human clarification;
- the target repository has fewer than four open issues labeled `kaizen`;
- for the fixed organization-wide scout, the target repository has fewer than
  five open generated PRs.

For the fixed organization-wide scout's generated-PR WIP guard, branches or PR titles prefixed with `kaizen/`, `codex/`, `claude/`, `agent/`, `[scout]`, `[monitor]`, or `kaizen:` count as generated. Those prefixes count as generated unless there is evidence that they are human-authored maintenance.
When a target reaches five open generated PRs, the fixed scout creates no new
issue for that repository and reports the eligible finding as skipped due to
the WIP cap. An opt-in per-repository scout instead blocks at its configured
WIP limit of one to four open pull requests, regardless of provenance.

For organization-owned targets, the scout adds the `kaizen`,
`kaizen:authorized`, and `kaizen:ready` labels to created issues. Execution
authorization and opt-in queue selection are separate gates, and this automatic
approval of both is an explicit `kaizen-agents-org` dogfooding policy. The actor
applying the authorization label must have at least triage permission in the
target repository because `kaizen-loop` validates the label event actor's
permission. External opt-in scouts apply only their explicitly configured labels;
authorization and queue selection remain maintainer actions and must not inherit
the organization bypass implicitly.

Before creating the first issue for an organization-owned target, the scout
verifies that `kaizen:authorized` and `kaizen:ready` exist and creates either
label when it is missing. Bootstrap requires write permission; triage permission
is only sufficient to apply an existing label. Without write permission, a
maintainer must pre-provision missing labels. If either label cannot be created
and verified, the scout keeps the candidate in its report and does not create an
issue without both execution authorization and queue selection. An external
opt-in scout never bootstraps these labels automatically.

The scout creates at most two issues per target repository per run. There is no organization-wide issue creation cap because each repository already has its own per-run and open-issue limits. Additional eligible findings for a repository stay in the report. Each created issue must include a PR linkage requirement telling the implementer to put a GitHub closing keyword in the implementation PR body and verify `closingIssuesReferences` before reporting the PR ready.

Duplicate detection groups issues that own the same target repository and
actionable follow-up into one equivalence set. The canonical issue is selected
by a deterministic total ordering: open before closed, then earliest
`createdAt`, then lowest issue number. An open pull request that already owns
the exact work suppresses creation of another issue. Duplicate relationships
point only from duplicate to canonical, and the canonical issue is never closed
as a duplicate.

Normal scout runs do not close, reopen, or relabel existing issues and do not
invoke reconciliation. Duplicate reconciliation requires explicit
authorization naming the target repository, complete issue set, and permitted
reconciliation action. The managed organization scout must use
`scripts/reconcile-scout-duplicates.mjs` as its
only existing-issue mutation path; manual `gh issue` mutations are forbidden.
The helper refreshes every explicitly authorized candidate issue individually,
including both `OPEN` and `CLOSED` state, and never relies on the default
open-only issue list. It recomputes the canonical issue immediately before
every close. Direct or transitive legacy cycles are
repairable only when every historical relation remains inside the complete
explicitly authorized candidate set. The helper preserves those comments, then
writes an authoritative reconciliation marker to every candidate; the newest
consistent marker state overrides legacy relations. If every candidate is
already closed, an authorized run reopens the deterministically selected
canonical issue before writing the markers and linking the remaining closed
duplicates. Failed queries, missing candidates, out-of-scope relations,
conflicting current markers, relations added after the current marker, or
canonical drift fail safe without closing anything. Repeated and concurrent
runs are idempotent and preserve the same one-way canonical relationship.
Rendered opt-in scouts have no reconciliation mutation path and report
duplicates for maintainer review.

## Safety Boundaries

The scout does not edit files, push branches, merge pull requests, or open implementation pull requests. It only creates focused GitHub issues and reports what it found.
