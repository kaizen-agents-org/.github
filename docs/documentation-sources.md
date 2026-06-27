# Documentation Sources

This document defines how Kaizen Agents documentation should be used as source material for coordination work and automated issue creation.

## Source Order

Use these documents in this order when checking whether a proposed issue matches the organization direction:

| Source | Use it for |
| --- | --- |
| [Organization Profile](../profile/README.md) | Public product framing, core project list, current operating posture, and the issue-to-PR promise. |
| [Repository README](../README.md) | Organization repository responsibilities, shared assets, and the local map of docs and skills. |
| [Architecture Notes](./architecture.md) | Component boundaries, end-to-end flow, quality gates, and responsibility rules. |
| [Issue-to-PR MVP](./issue-to-pr-mvp.md) | Runtime contract for turning a GitHub Issue into a ready-for-review PR. |
| [Daily Dogfood Sync](./daily-dogfood-sync.md) | Deterministic shared-skill and contract-file sync rules. |
| [Shared Skill Sync](./shared-skill-sync.md) | Push-triggered shared-skill propagation rules and target-repository PR behavior. |
| [Organization Monitor](./org-monitor.md) | Monitor scope, issue creation rules, and safety boundaries. |
| [Implementation Status](./implementation-status.md) | Current implementation state and known hardening gaps. |
| [Production Readiness Reviews](./production-readiness/README.md) | Weekly readiness review process, checklist, metrics, and log template. |
| [Production Readiness Log](./production-readiness-log.md) | Dated readiness findings, observed operational gaps, and priority hardening work. |

Project-local READMEs and docs may add repository-specific details, but they should not silently override the organization-level responsibility model. If project docs and organization docs disagree, report the drift instead of filing an implementation issue based on the conflicting assumption.

## Issue Evidence

Before creating a coordination or improvement issue, cite the documentation basis for the work.

Issue bodies should include a `Documentation basis` section with:

- the document path or URL
- the relevant heading or short excerpt
- why that source supports the issue scope

Example:

```markdown
## Documentation basis

- `.github/docs/architecture.md`, "Product Goal": the workflow should produce reviewable PRs, not unreviewed autonomy.
- `.github/docs/issue-to-pr-mvp.md`, "Repository Contract": target repositories should keep `.kaizen/config.yml` and Kaizen issue templates aligned.
```

Do not create an automated issue when the documentation basis is missing, stale, or contradictory. Include the observation in the coordination report and ask for human clarification or a documentation update first.

## Documentation Maintenance

Keep documentation changes scoped to the document's role:

- Update the organization profile when the public product promise, core project list, or current status changes.
- Update this repository README when shared assets, docs, or repository ownership changes.
- Update architecture notes when component responsibilities or quality gates change.
- Update project-local READMEs when commands, setup, runtime behavior, or repository-specific contracts change.
- Update monitor and automation docs when automated issue creation rules or safety boundaries change.

When a code change changes behavior that users or automations depend on, update the nearest relevant documentation in the same PR.
