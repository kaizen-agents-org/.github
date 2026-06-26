# Organization Monitor

The Kaizen Agents organization uses a Codex automation named `Kaizen Agents org monitor` as a cross-repository coordination check.

The monitor is not part of the runtime `kaizen-loop` issue-to-PR pipeline. It is an operational review loop for keeping the organization documentation, repository state, and component responsibilities aligned while the system is changing.

The GitHub-managed source prompt for the Codex automation lives at [`../automations/kaizen-agents-org-monitor.prompt.md`](../automations/kaizen-agents-org-monitor.prompt.md). The local Codex runtime copy under `$CODEX_HOME/automations/kaizen-agents-org-monitor/automation.toml` should be treated as a synced copy, not the source of truth.

## Scope

The monitor reviews the core and support organization repositories:

| Area | Repositories |
| --- | --- |
| Organization docs and shared assets | `kaizen-agents-org/.github` |
| Builder component | `kaizen-agents-org/builder-agent` |
| Orchestrator component | `kaizen-agents-org/kaizen-loop` |
| Independent verifier component | `kaizen-agents-org/verifier` |
| Code review configuration | `kaizen-agents-org/coderabbit` |
| Renovate configuration | `kaizen-agents-org/renovate-config` |

The local automation may inspect local checkouts for these repositories as well as their GitHub remotes.

## Local Kaizen Loop Scheduler

Local dogfooding runs should follow the current `kaizen-loop` scheduler contract: each repository defines named jobs under `scheduler.jobs` in its `.kaizen/config.yml`, and scheduler operations sync those job definitions from the YAML config.

The monitor should treat job names such as `maintenance` as repository-owned configuration, not as fixed organization-wide fields like `nightly`, `afternoon`, or `poll`. Staggering is still an operational goal, but it should come from each job's schedule settings, such as interval cadence and anchor time, so repositories can adjust their own safe run windows without changing the monitor contract.

For example, a local maintenance posture can be represented as an interval job:

```yaml
scheduler:
  jobs:
    maintenance:
      schedule:
        type: interval
        everyHours: 8
        anchorTime: "02:45"
```

## What It Checks

Each run produces a concise coordination report covering:

- Local git status and branch alignment with `origin`.
- Open GitHub pull requests and issues.
- CI and check status where available.
- Documentation and implementation drift across the core and support components.
- Whether local Kaizen Loop scheduler documentation and repository configs use the current `scheduler.jobs` model instead of stale fixed job fields.
- Whether the [daily dogfood sync](./daily-dogfood-sync.md) workflow exists, runs on schedule, runs after managed source contract changes land on `main`, and stays limited to deterministic files it can update safely.
- Whether local runner state can be refreshed after dogfood changes with `kaizen fleet --root .. --owner kaizen-agents-org --prune --verify`.
- Whether `kaizen-loop`, `builder-agent`, and `verifier` still have clear responsibilities that match the organization profile and architecture docs.
- Recommended next actions and follow-up work that should be handled through PRs.

## Issue Creation

After writing the report, the monitor may create GitHub issues for concrete follow-up work.

Automatic issue creation is intentionally conservative:

- Search existing open issues and PRs before creating anything.
- Create an issue only when the target repository is clear, the improvement is actionable, and the work is not already covered.
- Limit automatic issue creation to at most two issues per run.
- Prefix issue titles with `[monitor]`.
- Include observed evidence, affected repositories, recommended action, and relevant links or file references in the issue body.
- Include a `Documentation basis` section that cites the Organization Profile, repository README, Architecture Notes, Issue-to-PR MVP, or project-local docs that justify the issue scope.
- If the documentation basis is missing, stale, or contradictory, keep the finding in the report and file a documentation clarification issue only when that is the clear actionable next step.
- If ownership is unclear after investigation, create at most one coordination issue in `kaizen-agents-org/kaizen-loop` explaining the ambiguity.

Speculative ideas, low-confidence observations, duplicate work, and broad cleanup suggestions should stay in the report instead of becoming issues.

Daily dogfood sync drift should be reported when the monitor cannot resolve it deterministically, including a missing scheduled workflow, a broken shared-skill sync delegation, or changes outside the documented deterministic file list.

## Safety Boundaries

The monitor may report and file focused follow-up issues, but it must not:

- Merge pull requests.
- Push branches or commits.
- Make broad code changes automatically.
- Treat its report as approval to bypass human review.

Any proposed coordination change that modifies repository behavior should still go through a normal ready-for-review pull request.

## Relationship To The Core Flow

The core product flow remains:

```text
GitHub Issue
  -> kaizen-loop
  -> builder-agent
  -> mechanical verification
  -> verifier
  -> ready-for-review PR
  -> human merge
```

The organization monitor sits outside that flow. Its job is to notice drift and create reviewable follow-up work so the core flow remains understandable and maintainable.

## Local Kaizen Loop Schedule

The local Kaizen Loop jobs for the Kaizen Agents repositories are staggered to avoid running every repository at the same time. Each repository has a nightly run and an afternoon run:

| Nightly (JST) | Afternoon (JST) | Repository |
| --- | --- | --- |
| 01:30 | 13:30 | `kaizen-agents-org/.github` |
| 01:45 | 13:45 | `kaizen-agents-org/coderabbit` |
| 02:00 | 14:00 | `kaizen-agents-org/renovate-config` |
| 02:15 | 14:15 | `kaizen-agents-org/builder-agent` |
| 02:45 | 14:45 | `kaizen-agents-org/kaizen-loop` |
| 03:00 | 15:00 | `kaizen-agents-org/verifier` |

The nightly job runs `kaizen run --project <slug> --scheduled --trigger scheduled`. The afternoon job runs `kaizen run --project <slug> --scheduled --trigger afternoon`. Both process eligible open `kaizen` issues for that repository.

## Why Open PR Count Stays Low

The local Kaizen Loop scheduler intentionally applies backpressure before creating new work.

For automatic scheduled runs, each repository has an open-PR limit from `run.maxOpenPullRequests` in `.kaizen/config.yml`. If the repository already has that many open PRs, eligible issues are left open and the run records `open pull request limit reached` instead of creating another branch. Explicit manual runs, such as `kaizen fix` or `kaizen run --issue <number>`, are not blocked by this automatic-run limit.

Issues with `kaizen:needs-human` are also skipped by scheduled runs until a maintainer adds the missing context or otherwise resolves the blocker and removes that label.

Daily sync workflows use fixed branch names and update existing open sync PRs instead of creating duplicate PRs on every run. As a result, a healthy organization can have only a small number of open PRs even while the scheduler and sync workflows are running regularly.

## Relationship To Daily Dogfood Sync

[Daily Dogfood Sync](./daily-dogfood-sync.md) is the intended GitHub Actions workflow for deterministic scheduled and post-merge updates across repositories, including shared skills and managed dogfooding contract files.

The organization monitor should check that the daily sync is working and report drift that cannot be fixed deterministically. It should not replace the daily sync or push cross-repository updates itself.

The local runtime side of the same loop is refreshed with `kaizen fleet --root .. --owner kaizen-agents-org --prune --verify`, which rebuilds registry/workspace/scheduler state and runs configured setup and verify commands in synced workspaces. The monitor may report fleet refresh failures as local observations, but issue creation still requires default-branch documentation support and duplicate checks.
