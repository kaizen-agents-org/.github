# Daily Dogfood Sync

This document defines the deterministic daily sync contract for the Kaizen Agents repositories.

## Goal

The daily dogfood sync keeps shared, reviewable agent contracts aligned across the core repositories without granting automation authority to merge changes.

The first supported contract is the shared skill sync:

- Source repository: `kaizen-agents-org/.github`
- Source files: `skills/gh-link-issue-pr`, `skills/kaizen-bug-router`, and `skills/pr-guardian`
- Target repositories: `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config`
- Target path: each repository's `skills/` directory

## Workflow

`.github/workflows/daily-dogfood-sync.yml` runs once per day and can also be run manually. It delegates to `.github/workflows/sync-kaizen-shared-skills.yml`, which owns the existing deterministic shared-skill copy behavior.

The called workflow:

1. Requires `KAIZEN_SYNC_TOKEN` so target repositories can be cloned, updated, and opened as PRs.
2. Fails with an explicit error when the token is missing.
3. Clones the target repositories when the token is available.
4. Runs `scripts/sync-kaizen-shared-skills.sh` to copy only the documented shared skill directories.
5. Verifies that each target checkout now matches the source shared skill directories.
6. Opens or updates ready-for-review sync PRs targeting `main` in target repositories when copied files changed.
7. Asserts that no target repository's `origin/main` still drifts from the source shared skills without an open sync PR targeting `main`, failing the run if it does.
8. Reports the per-repository outcome in the workflow summary.

The workflow must not merge PRs automatically.

## Deterministic Files

The daily workflow is limited to deterministic files with a repository-owned source of truth. Today that means only these shared skill directories:

```text
skills/
  gh-link-issue-pr/
  kaizen-bug-router/
  pr-guardian/
```

Do not add generated reports, logs, transient state, or repository-specific runtime configuration to the daily sync contract. Add new deterministic targets here before expanding the workflow.

## Monitor Contract

The organization monitor should check that:

- `.github/workflows/daily-dogfood-sync.yml` exists.
- The daily workflow has both `schedule` and `workflow_dispatch` triggers.
- The daily workflow delegates to `.github/workflows/sync-kaizen-shared-skills.yml`.
- The shared skill sync workflow remains callable through `workflow_call`.
- Drift outside the deterministic file list is reported as follow-up work instead of being modified automatically.

If the daily workflow is missing, failing, or no longer limited to deterministic files, the monitor should file or update a focused `[monitor]` issue.
