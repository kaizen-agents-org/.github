# Kaizen Agents Docs

This directory contains the organization-level documentation for Kaizen Agents.

## Reading Order

1. [Architecture Notes](./architecture.md)
   - Product goal
   - Repository responsibilities
   - Component process flows
   - End-to-end workflow
   - Quality gate model

1. [Documentation Sources](./documentation-sources.md)
   - Source-of-truth order
   - Documentation-backed issue evidence
   - Maintenance expectations for profile, README, architecture, and project docs

1. [MVP Plan](./mvp-plan.md)
   - Phased plan for making the system usable
   - Minimal vertical slice
   - Gate contracts
   - Operational readiness

1. [Issue-to-PR MVP](./issue-to-pr-mvp.md)
   - Organization-level MVP goal
   - Per-repository contract
   - Ready-for-review PR requirements
   - Failure behavior

1. [Shared Skill Sync](./shared-skill-sync.md)
   - Shared skill source of truth
   - Per-project vendoring
   - Update propagation workflow

1. [Kaizen Toolchain Release Tags](./release-tags.md)
   - `v0.x.y` tag policy for `kaizen-loop`, `builder-agent`, and `verifier`
   - Compatibility manifest ownership
   - Release and install verification checklist

1. [Daily Dogfood Sync](./daily-dogfood-sync.md)
   - Daily deterministic sync workflow
   - Shared skill sync delegation
   - Organization monitor contract

1. [Automation Roles](./automation-roles.md)
   - Improve, maintain, and readiness-check responsibilities
   - Issue prefixes, issue creation limits, and PR permissions
   - Duplicate ownership rules across issue-creating automations
   - Boundaries between scout, monitor, readiness review, and issue creator

1. [Organization Monitor](./org-monitor.md)
   - Cross-repository coordination checks
   - Conservative follow-up issue creation
   - Safety boundaries for monitor automation
   - Source prompt stored under `../automations/`

1. [Repository Improvement Scout](./repo-improvement-scout.md)
   - Proactive repo-local improvement discovery
   - `[scout]` issue creation rules
   - Source prompt stored under `../automations/`

1. [Implementation Status](./implementation-status.md)
   - What works today
   - What is still missing
   - What is still being hardened

1. [Production Readiness Log](./production-readiness-log.md)
   - Dated readiness evaluations
   - Observed operational gaps
   - Priority hardening work before broader production use

1. [Weekly Kaizen Metrics](./metrics/README.md)
   - Durable ISO-week snapshots from `kaizen status --metrics`
   - Denominator-bearing rates for Phase A-5 and readiness reviews

1. [Production Readiness Reviews](./production-readiness/README.md)
   - Weekly review process
   - Checklist, metrics, and log template
   - Source-managed weekly automation prompt

1. [Design Decisions](./design-decisions.md)
   - Product goal
   - Responsibility separation
   - Why self-review is not enough
   - Deterministic gates, LLM discovery
   - Why `builder-agent` has both a skill and CLI
   - Why Product Kaizen is out of scope for now

## Improvement Reports

Dated organization-wide evaluations and their implementation guidance. Evaluation reports and the improvement playbook in this directory are the canonical, versioned copies; any local workspace copies outside this repository are mirrors only.

- [improvement-report-2026-07-03.ja.md](./improvement-report-2026-07-03.ja.md): value-priority strategy report (Japanese).
- [verifier-strategy-2026-07-03.ja.md](./verifier-strategy-2026-07-03.ja.md): verifier implementation plan referenced by the strategy report (Japanese).
- [evaluation-2026-07-04.ja.md](./evaluation-2026-07-04.ja.md): follow-up snapshot evaluation, one day later, with delta against the strategy report (Japanese).
- [improvement-playbook.ja.md](./improvement-playbook.ja.md): actionable checklist (Phase A/B/C) derived from the evaluation above; update its progress log as work completes (Japanese).
- [evaluation-2026-07-05.ja.md](./evaluation-2026-07-05.ja.md): re-evaluation after resyncing all repos to `origin/main`, with measured delta against 07-04 (Japanese).
- [org-design-improvement-notes-2026-07-05.ja.md](./org-design-improvement-notes-2026-07-05.ja.md): cross-repo organizational design gaps (throughput control, evidence-strength labeling, primary-intent precedence, automation-role overlap, deterministic-vs-LLM judgment principle) intended for other AI agents to consult when attempting further kaizen (Japanese).
- [evaluation-2026-07-05-v2.ja.md](./evaluation-2026-07-05-v2.ja.md): same-day afternoon re-evaluation with new findings — BLOCKED root cause (`required_conversation_resolution` + unresolved bot threads), WIP-limit/sandbox-smoke completion confirmed, fleet-hygiene regression evidence, and tracking issues filed per recommendation (Japanese).
- [product-adoption-plan-2026-07-05.ja.md](./product-adoption-plan-2026-07-05.ja.md): decision guide for onboarding a real product onto the harness — staged timeline (supervised pilot in ~2 weeks, steady operation in 1.5–2.5 months), pilot preconditions, per-stack adjustments, and the single hard wait item (untrusted issue authors until Phase C-2) (Japanese).
- [onboarding-kit-design-2026-07-05.ja.md](./onboarding-kit-design-2026-07-05.ja.md): design for deploying the harness onto a target repository with one idempotent command — Onboarding Contract, declarative profiles under `onboarding/`, `kaizen init --profile` hardening, branch-protection preset, deterministic contract check, smoke-artifact acceptance gate, and the Phase C-1 reusable-workflow runtime (Japanese).
- [onboarding-flow-diagram-2026-07-05.ja.html](./onboarding-flow-diagram-2026-07-05.ja.html): standalone visual companion to the onboarding-kit design — the three deployment stages, the seven `onboard.sh` steps with the three human confirmation points, the Onboarding Contract acceptance state, both runtime forms, and steady-state operations; open locally in a browser (Japanese).
- [external-readiness-2026-07-08.ja.md](./external-readiness-2026-07-08.ja.md): external-application readiness assessment with the G1–G5 gap analysis tracked by the `.github#121` umbrella issue (Japanese).
- [evaluation-2026-07-11.ja.md](./evaluation-2026-07-11.ja.md): re-evaluation covering the code-mode-host/sandbox execution regression (design A / operational proof B), the stale-citation flaw found in the 07-08 readiness report, and W28 metrics denominators (Japanese).
- [evaluation-2026-07-12.ja.md](./evaluation-2026-07-12.ja.md): next-day re-evaluation (design A / operational proof B+) — 24h structural recovery from the execution regression, B-1 corpus target (50+/non-Node 10+) achieved, with B-4 (non-Node dogfood) flagged as the remaining critical path (Japanese).

## Core Concepts

- **Product goal**: issue registration should lead to a high-quality pull request, and a human merge should resolve the issue.
- **Core philosophy**: Build -> Verify -> Improve.
- **Responsibility split**: builders build, verifiers verify, Kaizen Loop coordinates.
- **Quality gate**: builder self-review, mechanical verification, independent verifier, human review.
- **Gate design**: code decides gates; LLMs discover evidence for deterministic gates to consume.
- **Standalone principle**: `builder-agent`, `verifier`, and `kaizen-loop` should each be useful independently.
- **MVP posture**: automate up to ready-for-review PR creation; keep merge under human control.
- **Issue linkage**: implementation PRs must include a closing keyword such as `Closes #123` in the PR body.
- **Documentation-backed issue creation**: automated coordination issues should cite the profile, README, architecture notes, or project docs that justify the scope.

## Project Skills

- [gh-link-issue-pr](../skills/gh-link-issue-pr/SKILL.md): project workflow for creating GitHub PRs that close their source issues.
- [kaizen-bug-router](../skills/kaizen-bug-router/SKILL.md): workflow for filing Kaizen Agents bug issues in the owning repository, falling back to `kaizen-loop` when ownership is unclear.
- [pr-guardian](../skills/pr-guardian/SKILL.md): workflow for monitoring opened PRs until they are mergeable or a real blocker remains.

Shared skills are synchronized into `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config`; see [Shared Skill Sync](./shared-skill-sync.md).

The daily dogfood sync runs the deterministic shared skill sync contract on a schedule; see [Daily Dogfood Sync](./daily-dogfood-sync.md).

## Organization Monitor

The Codex automation `Kaizen Agents org monitor` periodically reviews the core repositories for local/remote drift, open PRs and issues, CI state, responsibility alignment, and daily dogfood sync health. It may create focused `[monitor]` issues for concrete follow-up work after checking for duplicates, but it does not push, merge, or make broad changes automatically. Its source prompt is stored at [automations/kaizen-agents-org-monitor.prompt.md](../automations/kaizen-agents-org-monitor.prompt.md). See [Organization Monitor](./org-monitor.md).

## Repository Improvement Scout

The Codex automation `Kaizen Agents repo improvement scout` actively scans the active repositories for small, repo-local improvement issues. It may create focused `[scout]` issues for the normal Kaizen scheduler, but it does not implement changes itself. Its source prompt is stored at [automations/kaizen-agents-repo-improvement-scout.prompt.md](../automations/kaizen-agents-repo-improvement-scout.prompt.md). See [Repository Improvement Scout](./repo-improvement-scout.md).

## Automation Layers

The automation system is split into improve, maintain, and readiness-check layers. See [Automation Roles](./automation-roles.md) for the authoritative role boundaries, issue prefixes, duplicate ownership rules, and PR permissions.

## Current Focus

The first usable vertical slice is now wired together as an MVP:

```text
GitHub Issue
  -> kaizen-loop
  -> builder-agent
  -> mechanical verification
  -> verifier
  -> pull request
  -> human merge
```

`kaizen-loop` has Phase 2 support for builder-agent-based fixes, verifier review, isolated per-issue worktrees, scheduler registration, opt-in queueing, PR creation, and `pr-guardian` follow-up. `verifier` has a runnable `verifier check` CLI and writes Kaizen Loop verdict payloads through `KAIZEN_VERIFIER_RESULT_PATH`.

The current focus is hardening contracts, evidence quality, and operational behavior while keeping the system optimized for reviewable PRs, not unreviewed autonomy.

See [Production Readiness Log](./production-readiness-log.md) for dated
readiness reviews and the current list of operational gaps. See
[Production Readiness Reviews](./production-readiness/README.md) for the
weekly checklist, metrics, and log template.
