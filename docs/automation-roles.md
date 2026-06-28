# Automation Roles

Kaizen Agents uses four Codex automations in three layers: improve, maintain, and readiness-check.

| Layer | Automation | Responsibility | May create issues | May create PRs |
| --- | --- | --- | --- | --- |
| Improve | `Kaizen Agents repo improvement scout` | Find concrete repo-local improvement work for the normal Kaizen issue-to-PR loop. | Yes, `[scout]` issues. | No. |
| Maintain | `Kaizen Agents org monitor` | Check organization operation, sync, scheduler, CI, source-order, and drift health. | Yes, only focused `[monitor]` issues. | No. |
| Readiness-check | `Kaizen Agents weekly readiness review` | Evaluate whether the system is closer to real operation and publish an approval-ready dated report. | No. | Yes, only readiness report PRs in `.github`. |
| Readiness-check | `Kaizen Agents readiness issue creator` | Convert an approved readiness report on `main` into implementation backlog. | Yes, `[readiness-review]` issues. | No. |

## Boundaries

`repo-improvement-scout` owns proactive improvement discovery. It should create small, actionable repo-local issues backed by default-branch docs or code evidence. It must not file organization operation issues, readiness-review issues, or implementation PRs.

`org-monitor` owns conservative maintenance. It should report broad state and create issues only for operational drift, sync failures, scheduler/fleet health, CI/check drift, documentation source-order gaps, or responsibility ambiguity that would make the automation system harder to operate. It must not become a general improvement scout.

`weekly-readiness-review` owns readiness assessment. It should inspect evidence, write the dated report, update the readiness index, and open or update a normal ready-for-review PR containing only the report file and index update. It must not create GitHub issues or implementation PRs.

`readiness-issue-creator` owns approved-report issue creation. It must read the latest dated readiness report from the `.github` default branch after the report PR is merged. It must not create issues from local-only reports, open PR contents, proposed report text, or previous automation memory.

## Issue Prefixes

| Prefix | Source automation | Meaning |
| --- | --- | --- |
| `[scout]` | `repo-improvement-scout` | Repo-local improvement found by proactive scanning. |
| `[monitor]` | `org-monitor` | Operation, sync, scheduler, CI, source-order, or coordination drift. |
| `[readiness-review]` | `readiness-issue-creator` | Work approved through a merged dated readiness report. |

## Limits

Each automation applies limits per target repository so one repository cannot consume another repository's capacity:

| Automation | Per-repository creation limit |
| --- | --- |
| `repo-improvement-scout` | At most two issues per target repository per run. |
| `org-monitor` | At most one issue per target repository per run. |
| `readiness-issue-creator` | At most three issues per target repository per run. |

The shared backlog guard still applies: skip new issue creation for a target repository when it already has four or more open issues labeled `kaizen`, except where a monitor prompt explicitly allows a concrete closed-loop health finding to bypass that guard.
