# Daily Dogfood Sync

This document defines the deterministic daily sync contract for the Kaizen Agents repositories.

## Goal

The daily dogfood sync keeps shared, reviewable agent contracts aligned across the core repositories without granting automation authority to merge changes.

The synced contract covers the dogfooding files the monitored repositories depend on staying aligned:

- Source repository: `kaizen-agents-org/.github`
- Target repositories: `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config`
- Deterministic source of truth: `.github/dogfood-sync/manifest.json`

These repositories form a maintainer-controlled self-organization fleet. Their
runtime configs must explicitly set `safety.operationMode: dogfood`; relying on
the `external` default would require a second execution-authorization label and
silently leave maintainer-labeled `kaizen` work unprocessed. This exception is
limited to the repositories named here: PR-only policy, verifier checks, intake
gates, and opt-in selection remain in force. Public issue forms add only the
base `kaizen` label; a maintainer must add `kaizen:ready` before scheduled work
can run. Third-party or adopter repositories must keep the safer `external`
mode and its explicit authorization gate.

The three trusted organization issue creators are the narrow exception: they
add `kaizen`, `kaizen:authorized`, and `kaizen:ready` together after their
preflight checks, so their ready-to-run dogfood issues satisfy this selector.
Authorization and selection remain separate gates. Existing automation-created
backlog is queued through the deliberate maintainer triage described in
[Automation Roles](./automation-roles.md#existing-issue-triage), not by bulk
labeling public or external issues.

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

`.github/workflows/sync-daily-dogfood.yml` also runs immediately after managed source contract changes land on `main`. The push trigger is limited to `.github/dogfood-sync/**`, `.github/ISSUE_TEMPLATE/kaizen.yml`, `scripts/sync-daily-dogfood.sh`, and the sync workflow itself. Shared-skill-only changes keep using the narrower `sync-kaizen-shared-skills.yml` fast path.

The called workflow:

1. Checks for `KAIZEN_SYNC_TOKEN` and skips successfully when it is missing, unless a reusable caller explicitly sets `require_token: true`.
2. Requires `jq` after token validation succeeds, failing with an explicit error when `jq` is missing.
3. Clones the target repositories listed in the manifest when the token is available.
4. Runs `scripts/sync-daily-dogfood.sh` to copy only the manifest-managed paths, and refuses to continue if a target has drift outside those paths.
5. Verifies that each target checkout now matches the manifest-managed sources.
6. Opens or updates ready-for-review sync PRs on the fixed branch `codex/daily-dogfood-sync` targeting `main` in target repositories when managed files changed.
   Every generated PR carries `<!-- kaizen-pr-guardian:managed -->`; the local Kaizen durable guardian uses that marker together with the known branch, same-repository head, and expected base branch before adopting the PR for review convergence.
7. Asserts that any remaining `origin/main` drift is covered by an open sync PR targeting `main` whose branch exactly matches every manifest-managed source path; a missing, stale, or incomplete sync PR fails the run.
8. Reports the per-repository outcome in the workflow summary.

The workflow must not merge PRs automatically.

Generated dogfood sync PRs can be linked to a source issue when the sync resolves an issue-backed task. Run the workflow with `source_issue` set to the canonical issue reference, for example `kaizen-agents-org/.github#49`, and new sync PR bodies include `Closes <source_issue>`. On push-triggered runs, the workflow derives `source_issue` from the pull request associated with the pushed commit when that PR has a closing issue reference. If an open sync PR already exists, the workflow adds the provided or derived closing keyword to that PR body. After writing a closing keyword, the workflow checks `closingIssuesReferences` with bounded retries and fails if GitHub did not link the expected issue; body text alone is not treated as proof that GitHub can link or close the source issue. Scheduled runs without `source_issue` still create or update ready-for-review sync PRs, but the PR body or workflow notice explicitly records that the source issue was not supplied.

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
- The called sync workflow remains callable through `workflow_call`, and scheduled or manual runs can skip cleanly when `KAIZEN_SYNC_TOKEN` is missing.
- Push-triggered sync runs to managed source contract paths after merges to `main` are gated by `TOKEN_REQUIRED` and fail closed when `KAIZEN_SYNC_TOKEN` is absent; `workflow_call` runs also fail closed when called with `require_token: true`.
- Push-triggered sync runs derive the source issue from the merged source PR when possible, and generated target PRs verify the issue linkage through `closingIssuesReferences`.
- The deterministic manifest `.github/dogfood-sync/manifest.json` exists and lists every target and managed path.
- The source repository and every manifest target explicitly declare `safety.operationMode: dogfood` together with opt-in `kaizen:ready` selection.
- Drift outside the manifest-managed paths is reported as follow-up work instead of being modified automatically.

`scripts/check-daily-dogfood-sync-contract.sh` encodes these checks as a regression test.
`scripts/test-dogfood-selection-label-contract.sh` additionally proves that the
contract rejects a trusted issue creator when its label set omits the configured
selection label.

If the daily workflow is missing, failing, or no longer limited to the manifest-managed files, the monitor should file or update a focused `[monitor]` issue.
