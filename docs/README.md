# Kaizen Agents Docs

This directory contains the organization-level documentation for Kaizen Agents.

## Reading Order

1. [Architecture Notes](./architecture.md)
   - Product goal
   - Repository responsibilities
   - Component process flows
   - End-to-end workflow
   - Quality gate model

2. [MVP Plan](./mvp-plan.md)
   - Phased plan for making the system usable
   - Minimal vertical slice
   - Gate contracts
   - Operational readiness

3. [Issue-to-PR MVP](./issue-to-pr-mvp.md)
   - Organization-level MVP goal
   - Per-repository contract
   - Ready-for-review PR requirements
   - Failure behavior

4. [Shared Skill Sync](./shared-skill-sync.md)
   - Shared skill source of truth
   - Per-project vendoring
   - Update propagation workflow

5. [Daily Dogfood Sync](./daily-dogfood-sync.md)
   - Daily deterministic sync workflow
   - Shared skill sync delegation
   - Organization monitor contract

6. [Organization Monitor](./org-monitor.md)
   - Cross-repository coordination checks
   - Conservative follow-up issue creation
   - Safety boundaries for monitor automation

7. [Implementation Status](./implementation-status.md)
   - What works today
   - What is still missing
   - What is still being hardened

8. [Design Decisions](./design-decisions.md)
   - Product goal
   - Responsibility separation
   - Why self-review is not enough
   - Why `builder-agent` has both a skill and CLI
   - Why Product Kaizen is out of scope for now

## Core Concepts

- **Product goal**: issue registration should lead to a high-quality pull request, and a human merge should resolve the issue.
- **Core philosophy**: Build -> Verify -> Improve.
- **Responsibility split**: builders build, verifiers verify, Kaizen Loop coordinates.
- **Quality gate**: builder self-review, mechanical verification, independent verifier, human review.
- **Standalone principle**: `builder-agent`, `verifier`, and `kaizen-loop` should each be useful independently.
- **MVP posture**: automate up to ready-for-review PR creation; keep merge under human control.
- **Issue linkage**: implementation PRs must include a closing keyword such as `Closes #123` in the PR body.

## Project Skills

- [gh-link-issue-pr](../skills/gh-link-issue-pr/SKILL.md): project workflow for creating GitHub PRs that close their source issues.
- [kaizen-bug-router](../skills/kaizen-bug-router/SKILL.md): workflow for filing Kaizen Agents bug issues in the owning repository, falling back to `kaizen-loop` when ownership is unclear.
- [pr-guardian](../skills/pr-guardian/SKILL.md): workflow for monitoring opened PRs until they are mergeable or a real blocker remains.

Shared skills are synchronized into `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config`; see [Shared Skill Sync](./shared-skill-sync.md).

The daily dogfood sync runs the deterministic shared skill sync contract on a schedule; see [Daily Dogfood Sync](./daily-dogfood-sync.md).

## Organization Monitor

The Codex automation `Kaizen Agents org monitor` periodically reviews the core repositories for local/remote drift, open PRs and issues, CI state, responsibility alignment, and daily dogfood sync health. It may create focused `[monitor]` issues for concrete follow-up work after checking for duplicates, but it does not push, merge, or make broad changes automatically. See [Organization Monitor](./org-monitor.md).

## Current Focus

The first usable vertical slice is now wired together as an MVP:

```text
GitHub Issue
  -> builder-agent
  -> mechanical verification
  -> verifier
  -> pull request
  -> human merge
```

`kaizen-loop` has Phase 2 support for builder-agent-based fixes, verifier review, isolated per-issue worktrees, scheduler registration, opt-in queueing, PR creation, and `pr-guardian` follow-up. `verifier` has a runnable `verifier check` CLI and writes Kaizen Loop verdict payloads through `KAIZEN_VERIFIER_RESULT_PATH`.

The current focus is hardening contracts, evidence quality, and operational behavior while keeping the system optimized for reviewable PRs, not unreviewed autonomy.
