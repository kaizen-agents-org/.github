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

`org-monitor` has exactly one organization-wide installation. Repository-scoped copies must remain disabled. It observes local Kaizen runtime health but never reconciles production registry, workspace, scheduler, lock, or inventory state. Runtime reconciliation belongs to a separate operator action using the machine-local authoritative fleet manifest.

`weekly-readiness-review` owns readiness assessment. It should inspect evidence, write the dated report, update the readiness index, write or update the weekly metrics snapshot, open or update a normal ready-for-review PR containing only the report file, readiness index, and weekly metrics file, and run `pr-guardian` on that report PR until it is merge-ready or blocked. It must not create GitHub issues or implementation PRs.

`readiness-issue-creator` owns approved-report issue creation. It runs as a daily post-merge poll and must read the latest dated readiness report from the `.github` default branch after the report PR is merged. It must not create issues from local-only reports, open PR contents, proposed report text, or previous automation memory.

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

Every issue-creating automation must include a `PR linkage requirement` section
in each created issue body. The section tells the implementer to put a GitHub
closing keyword in the implementation PR body and verify
`closingIssuesReferences` before reporting the PR ready. This keeps issue
creation aligned with the issue-to-PR promise: merging the implementation PR
closes the source issue.

## Duplicate Ownership

Before creating any issue, every issue-creating automation must search open
issues and PRs in the target repository using the proposed title, affected
paths, component names, and conceptual keywords. It must also search sibling
repositories for explicit cross-repository coordination issues or PRs that may
own the same work. Duplicate blocking is target-repository scoped by default,
except when an existing cross-repository issue or PR explicitly owns the exact
work.

An existing issue or PR blocks new issue creation when it clearly owns the same
target repository and the same actionable follow-up. A cross-repository issue
or PR blocks creation only when it explicitly owns that exact cross-repository
work. Related work elsewhere should be linked in the report or issue body, but
it must not by itself block a concrete repo-local issue.

When a finding is skipped as duplicate, the automation report must name the
existing issue or PR that owns the work. If ownership is unclear, create no
repo-local implementation issue for that finding and report the ambiguity
instead of allowing two automations to race on the same problem. The maintain
layer may still create at most one coordination issue in `kaizen-loop` when the
org-monitor prompt's ownership-ambiguity rule applies.

For recurring monitor sync-drift findings, duplicate ownership is identified by
the target repository, affected repository-relative path or documented
component, and actionable follow-up. The monitor stores a SHA-256 digest of
that normalized key in the issue body. After a candidate is fully formed, it
must refresh open issues and PRs and acquire an atomic claim immediately before
creation; the earlier report inventory is not sufficient for this final gate.
Exact titles and affected paths remain fallback ownership evidence for older
issues or PRs that predate ownership markers.
