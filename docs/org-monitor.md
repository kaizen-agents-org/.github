# Organization Monitor

The Kaizen Agents organization uses a Codex automation named `Kaizen Agents org monitor` as a cross-repository coordination check.

The monitor is not part of the runtime `kaizen-loop` issue-to-PR pipeline. It is an operational review loop for keeping the organization documentation, repository state, and component responsibilities aligned while the system is changing.

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

## What It Checks

Each run produces a concise coordination report covering:

- Local git status and branch alignment with `origin`.
- Open GitHub pull requests and issues.
- CI and check status where available.
- Documentation and implementation drift across the core and support components.
- Whether the [daily dogfood sync](./daily-dogfood-sync.md) workflow exists, runs on schedule, and stays limited to deterministic files it can update safely.
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
