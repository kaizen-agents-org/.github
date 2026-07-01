# Repository Improvement Scout

The Kaizen Agents organization uses a Codex automation named `Kaizen Agents repo improvement scout` to actively find small, repo-local improvement issues for the normal Kaizen issue-to-PR loop.

The scout is the improve layer in the [Automation Roles](./automation-roles.md) model. It is separate from [Organization Monitor](./org-monitor.md): the organization monitor is conservative coordination health checking, while the scout is proactive backlog discovery.

The GitHub-managed source prompt for the Codex automation lives at [`../automations/kaizen-agents-repo-improvement-scout.prompt.md`](../automations/kaizen-agents-repo-improvement-scout.prompt.md). The local Codex runtime copy under `$CODEX_HOME/automations/kaizen-agents-repo-improvement-scout/automation.toml` should be treated as a synced copy, not the source of truth.

## Runtime Cadence

The scout runs on the frequent organization automation cadence: daily at 02:45, 10:45, and 18:45 in the local Codex automation schedule.

This cadence is intentionally higher than the organization monitor because the scout owns proactive, repo-local improvement discovery. The organization monitor runs later in the nightly window as a conservative coordination check.

## Scope

The scout actively scans the four implementation and coordination repositories:

| Area | Repository |
| --- | --- |
| Organization docs and automation sources | `kaizen-agents-org/.github` |
| Builder component | `kaizen-agents-org/builder-agent` |
| Orchestrator component | `kaizen-agents-org/kaizen-loop` |
| Independent verifier component | `kaizen-agents-org/verifier` |

`coderabbit` and `renovate-config` are downstream shared-configuration repositories. They are not scout targets. They may appear only as sync context for a `.github` finding.

## What It Looks For

The scout looks for bounded, evidence-backed improvements that can become one focused PR:

- `.github`: documentation, automation prompt, sync-source, and organization guidance gaps.
- `builder-agent`: implementation artifact quality, self-review quality, adapter/CLI behavior, backend/model selection, fallback behavior, build-result schema fidelity, and verifier-consumable outputs.
- `kaizen-loop`: orchestration, workspace lifecycle, issue intake, verification execution, verifier integration, policy, PR creation/linkage, scheduler behavior, run reporting, and fleet commands.
- `verifier`: independent review depth, verdict quality, schema fidelity, eval harnesses, seeded/golden corpus, false-positive controls, and reproducibility.

The scout should not create operation, sync, scheduler, CI, source-order, or readiness-review issues unless the finding is also a concrete repo-local improvement in the target repository. Those concerns belong to the monitor or readiness-review layer.

## Issue Creation

The scout may create `[scout]` issues when all of these are true:

- the target is one of the four active repositories;
- default-branch docs or code provide concrete evidence;
- the work is not already covered by an open issue or PR in that target repository;
- the issue is ready for the next Kaizen run without human clarification;
- the target repository has fewer than four open issues labeled `kaizen`.

The scout adds the `kaizen` label to created issues. It creates at most two issues per target repository per run. There is no organization-wide issue creation cap because each repository already has its own per-run and open-issue limits. Additional eligible findings for a repository stay in the report. Each created issue must include a PR linkage requirement telling the implementer to put a GitHub closing keyword in the implementation PR body and verify `closingIssuesReferences` before reporting the PR ready.

## Safety Boundaries

The scout does not edit files, push branches, merge pull requests, or open implementation pull requests. It only creates focused GitHub issues and reports what it found.
