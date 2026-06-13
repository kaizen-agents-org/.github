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

4. [Implementation Status](./implementation-status.md)
   - What works today
   - What is still missing
   - Why the target flow is not complete yet

5. [Design Decisions](./design-decisions.md)
   - Product goal
   - Responsibility separation
   - Why self-review is not enough
   - Why `builder-agent` starts as a skill
   - Why Product Kaizen is out of scope for now

## Core Concepts

- **Product goal**: issue registration should lead to a high-quality pull request, and a human merge should resolve the issue.
- **Core philosophy**: Build -> Verify -> Improve.
- **Responsibility split**: builders build, verifiers verify, Kaizen Loop coordinates.
- **Quality gate**: builder self-review, mechanical verification, independent verifier, human review.
- **Standalone principle**: `builder-agent`, `verifier`, and `kaizen-loop` should each be useful independently.
- **MVP posture**: automate up to ready-for-review PR creation; keep merge under human control.

## Current Focus

The current focus is the first usable vertical slice:

```text
GitHub Issue
  -> builder-agent
  -> mechanical verification
  -> verifier
  -> pull request
  -> human merge
```

The system should optimize for reviewable PRs, not unreviewed autonomy.
