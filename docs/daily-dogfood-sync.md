# Daily Dogfood Sync

This document defines the deterministic daily sync contract for the Kaizen Agents repositories.

## Goal

The daily dogfood sync keeps shared, reviewable agent contracts aligned across the core repositories without granting automation authority to merge changes.

The synced contract covers the dogfooding files the monitored repositories depend on staying aligned:

- Source repository: `kaizen-agents-org/.github`
- Target repositories: `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config`
- Deterministic source of truth: `.github/dogfood-sync/manifest.json`

The manifest enumerates every managed path. Three kinds of paths are managed today:

- **Shared skills** copied identically into each target's `skills/` directory:
  `skills/gh-link-issue-pr`, `skills/kaizen-bug-router`, and `skills/pr-guardian`.
- **Dogfooding contract files** that may differ per target and live under
  `.github/dogfood-sync/targets/<repo>/`:
  - `.kaizen/config.yml` — the per-repository runtime contract.
  - `AGENTS.md` — agent guidance.
- **Global identical files** that live outside the per-repository target tree:
  - `.github/ISSUE_TEMPLATE/kaizen.yml` — the shared issue template.

## Workflow

`.github/workflows/daily-dogfood-sync.yml` runs once per day and can also be run manually. It delegates to `.github/workflows/sync-daily-dogfood.yml`, which owns the deterministic manifest-driven copy behavior.

The called workflow:

1. Checks for `KAIZEN_SYNC_TOKEN` and skips successfully when it is missing, unless a reusable caller explicitly sets `require_token: true`.
2. Requires `jq`, failing with an explicit error when it is missing.
3. Clones the target repositories listed in the manifest when the token is available.
4. Runs `scripts/sync-daily-dogfood.sh` to copy only the manifest-managed paths, and refuses to continue if a target has drift outside those paths.
5. Verifies that each target checkout now matches the manifest-managed sources.
6. Opens or updates ready-for-review sync PRs on the fixed branch `codex/daily-dogfood-sync` targeting `main` in target repositories when managed files changed.
7. Asserts that no target repository's `origin/main` still drifts from the managed contracts without an open sync PR targeting `main`, failing the run if it does.
8. Reports the per-repository outcome in the workflow summary.

The workflow must not merge PRs automatically.

`.github/workflows/sync-kaizen-shared-skills.yml` remains the dedicated, push-triggered fast path for shared-skill-only propagation and stays callable through `workflow_call`. The daily dogfood sync is the broader scheduled contract.

## Deterministic Files

The daily workflow is limited to the deterministic paths enumerated in `.github/dogfood-sync/manifest.json`. Each managed path has a repository-owned source of truth:

```text
skills/gh-link-issue-pr/          (identical to every target)
skills/kaizen-bug-router/         (identical to every target)
skills/pr-guardian/               (identical to every target)
.github/ISSUE_TEMPLATE/kaizen.yml (identical to every target)
.github/dogfood-sync/targets/<repo>/.kaizen/config.yml -> <repo>/.kaizen/config.yml
.github/dogfood-sync/targets/<repo>/AGENTS.md          -> <repo>/AGENTS.md
```

Do not add generated reports, logs, transient state, or undocumented runtime configuration to the daily sync contract. Add a new entry to the manifest (and to the per-target source files when the value differs per repository) before expanding the workflow.

## Monitor Contract

The organization monitor should check that:

- `.github/workflows/daily-dogfood-sync.yml` exists.
- The daily workflow has both `schedule` and `workflow_dispatch` triggers.
- The daily workflow delegates to `.github/workflows/sync-daily-dogfood.yml`.
- The called sync workflow remains callable through `workflow_call`, skips cleanly when `KAIZEN_SYNC_TOKEN` is missing, and can fail closed when called with `require_token: true`.
- The deterministic manifest `.github/dogfood-sync/manifest.json` exists and lists every target and managed path.
- Drift outside the manifest-managed paths is reported as follow-up work instead of being modified automatically.

`scripts/check-daily-dogfood-sync-contract.sh` encodes these checks as a regression test.

If the daily workflow is missing, failing, or no longer limited to the manifest-managed files, the monitor should file or update a focused `[monitor]` issue.
