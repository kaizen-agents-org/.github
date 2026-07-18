# Organization Monitor

The Kaizen Agents organization uses a Codex automation named `Kaizen Agents org monitor` as a cross-repository coordination check.

The monitor is the maintain layer in the [Automation Roles](./automation-roles.md) model. It is not part of the runtime `kaizen-loop` issue-to-PR pipeline. It is an operational review loop for keeping the organization documentation, repository state, and component responsibilities aligned while the system is changing.

The GitHub-managed source prompt for the Codex automation lives at [`../automations/kaizen-agents-org-monitor.prompt.md`](../automations/kaizen-agents-org-monitor.prompt.md). The local Codex runtime copy under `$CODEX_HOME/automations/kaizen-agents-org-monitor/automation.toml` should be treated as a synced copy, not the source of truth.

## Runtime Cadence

Exactly one organization-wide monitor runs once daily at 04:15 in the local Codex automation schedule, after the nighttime [Repository Improvement Scout](./repo-improvement-scout.md) run. Do not enable repository-scoped copies of the monitor.

This timing reflects the monitor's conservative purpose: it checks organization-level coordination, sync health, and drift after the proactive scout has had a chance to discover repo-local improvement issues.

## Scope

The monitor reviews the active organization repositories:

| Area | Repositories |
| --- | --- |
| Organization docs and shared assets | `kaizen-agents-org/.github` |
| Builder component | `kaizen-agents-org/builder-agent` |
| Orchestrator component | `kaizen-agents-org/kaizen-loop` |
| Independent verifier component | `kaizen-agents-org/verifier` |

The local automation may inspect local checkouts for these repositories as well as their GitHub remotes. `coderabbit` and `renovate-config` are downstream shared-configuration repositories, not active monitor targets; they are mentioned only when `.github` sync evidence requires it.

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
- Whether reviewed, read-only fleet plan evidence exists from the machine-local inventory, for example `kaizen fleet --manifest ~/.kaizen/fleet.yml --prune --dry-run --json`.
- Whether `kaizen-loop`, `builder-agent`, and `verifier` still have clear responsibilities that match the organization profile and architecture docs.
- Recommended next actions and follow-up work that should be handled through PRs.

The monitor should not create general repo-improvement issues. Those belong to the [Repository Improvement Scout](./repo-improvement-scout.md). Monitor issues should stay focused on operation, sync, scheduler, CI/check, documentation source-order, branch/default-branch drift, fleet refresh, or responsibility ambiguity that would make the organization automation harder to operate.

## Issue Creation

After writing the report, the monitor may create GitHub issues for concrete follow-up work.

Automatic issue creation is intentionally conservative:

- Search existing open issues and PRs before creating anything.
- For sync drift, derive a stable duplicate-ownership key from the target repository, managed path or component, and actionable follow-up. Store a SHA-256 digest of that normalized key in every created issue body as `<!-- monitor-ownership-key: sha256:<digest> -->`, and search both open issue and PR bodies for the exact marker before falling back to exact titles, paths or components, source refs, and conceptual action terms. Immediately before creation, repeat the search and acquire an atomic runtime claim for the same digest so overlapping runs cannot both create an issue. A newer ref does not make already-owned reconciliation work distinct, and failed or ambiguous searches or claims must keep the candidate report-only.
- Create an issue only when the target repository is clear, the improvement is actionable, and the work is not already covered.
- Skip new issue creation for a repository when it already has four or more open `kaizen` issues, except for concrete, duplicate-free closed-loop health findings about sync, scheduler, or CI drift.
- Limit automatic issue creation to at most one issue per target repository per run.
- Before creating the first issue in a target repository, verify that `kaizen:authorized` exists and create the label when it is missing. If the label cannot be created and verified, report the candidate as blocked and do not create an issue without execution authorization.
- Add both the `kaizen` and `kaizen:authorized` labels. Automatic authorization is limited to the `kaizen-agents-org` dogfooding policy, and the actor applying `kaizen:authorized` must have at least triage permission in the target repository so `kaizen-loop` accepts the label event. External operation mode keeps human authorization as the default.
- Prefix issue titles with `[monitor]`.
- Include observed evidence, affected repositories, recommended action, and relevant links or file references in the issue body.
- Include a `Documentation basis` section anchored to [Documentation Sources](./documentation-sources.md), citing organization documents in that canonical source order before project-local docs, then cite the source that justifies the issue scope.
- Include a `PR linkage requirement` section telling the implementer to put a GitHub closing keyword in the implementation PR body and verify `closingIssuesReferences` before reporting the PR ready.
- If the documentation basis is missing, stale, contradictory, or narrower than the canonical source-order contract, keep the finding in the report as documentation drift and file a documentation clarification issue only when that is the clear actionable next step.
- If ownership is unclear after investigation, create at most one coordination issue in `kaizen-agents-org/kaizen-loop` explaining the ambiguity.

Speculative ideas, low-confidence observations, duplicate work, and broad cleanup suggestions should stay in the report instead of becoming issues.

`scripts/check-org-monitor-contract.sh` keeps the source prompt's sync-drift duplicate-suppression rules under deterministic regression coverage. The daily dogfood contract check invokes it so the default contract-validation path cannot silently omit these rules.

Daily dogfood sync drift should be reported when the monitor cannot resolve it deterministically, including a missing scheduled workflow, a broken shared-skill sync delegation, or changes outside the documented deterministic file list.

## Safety Boundaries

The monitor may report and file focused follow-up issues, but it must not:

- Merge pull requests.
- Push branches or commits.
- Edit repository files, create implementation branches, open implementation pull requests, or make broad code changes automatically.
- Treat its report as approval to bypass human review.
- Mutate production `registry.json`, fleet inventory, workspaces, scheduler jobs, or run locks.
- Run a mutating `kaizen fleet` command from a repository checkout or Codex worktree.

The monitor may recommend small, deterministic documentation, prompt, or configuration follow-ups, but any proposed coordination change that modifies repository behavior should still go through a normal ready-for-review pull request.

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

## Local Kaizen Loop Job Schedules

The local Kaizen Loop jobs for the Kaizen Agents repositories should remain staggered to avoid running every repository at the same time. The authoritative schedule for each repository is its `.kaizen/config.yml` `scheduler.jobs` map, not an organization-wide set of fixed nightly, afternoon, or polling fields.

The monitor should read the enabled named jobs for each repository and report their configured schedules, run modes, and safety settings as repository-owned configuration. For example, one repository may define `maintenance` and `maintenance-followup` daily jobs, while another repository may choose different job names, intervals, or anchor times.

Scheduled jobs process eligible open `kaizen` issues according to the run mode and guards configured on the job. Monitor reports should not infer fixed triggers such as `scheduled` or `afternoon`, and should not require every repository to expose matching job names or times.

## Why Open PR Count Stays Low

The local Kaizen Loop scheduler intentionally applies backpressure before creating new work.

For automatic scheduled runs, each repository has an open-PR limit from `run.maxOpenPullRequests` in `.kaizen/config.yml`. If the repository already has that many open PRs, eligible issues are left open and the run records `open pull request limit reached` instead of creating another branch. Explicit manual runs, such as `kaizen fix` or `kaizen run --issue <number>`, are not blocked by this automatic-run limit.

Issues with `kaizen:needs-human` are also skipped by scheduled runs until a maintainer adds the missing context or otherwise resolves the blocker and removes that label.

Daily sync workflows use fixed branch names and update existing open sync PRs instead of creating duplicate PRs on every run. As a result, a healthy organization can have only a small number of open PRs even while the scheduler and sync workflows are running regularly.

## Relationship To Daily Dogfood Sync

[Daily Dogfood Sync](./daily-dogfood-sync.md) is the intended GitHub Actions workflow for deterministic scheduled and post-merge updates across repositories, including shared skills and managed dogfooding contract files.

The organization monitor should check that the daily sync is working and report drift that cannot be fixed deterministically. It should not replace the daily sync or push cross-repository updates itself.

The local runtime side is reconciled separately by an operator from the authoritative machine-local `~/.kaizen/fleet.yml`. After confirming that the installed CLI advertises `--manifest` in `kaizen fleet --help`, the monitor may inspect `kaizen fleet --manifest ~/.kaizen/fleet.yml --prune --dry-run --json` output, but must never apply it. If that option is unavailable, the monitor reports fleet plan evidence as unavailable without running a fleet command. After reviewing a supported plan, an operator can run the corresponding apply and verify commands outside the monitor. Fleet failures remain local observations; issue creation still requires default-branch documentation support and duplicate checks.
