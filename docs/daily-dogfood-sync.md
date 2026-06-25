# Daily Dogfood Sync

This document defines the intended daily update loop that keeps Kaizen Agents dogfooding current across the organization repositories.

## Goal

Each core repository is both:

- a component of Kaizen Agents, and
- a target repository that Kaizen Agents should be able to operate on.

When a component changes, the repository's dogfooding contract must stay aligned so the organization can keep using Kaizen Agents on itself. The daily sync should keep shared skills, repository contracts, and generated dogfooding assets current enough that the normal issue-to-PR flow remains usable.

The target experience is:

```text
component update
  -> daily dogfood sync detects required contract updates
  -> ready-for-review PR in the affected repository
  -> human review and merge
```

The sync must not merge automatically.

## Scope

The daily sync covers the same core and support repositories as the organization monitor:

| Area | Repository |
| --- | --- |
| Organization docs and shared assets | `kaizen-agents-org/.github` |
| Builder component | `kaizen-agents-org/builder-agent` |
| Orchestrator component | `kaizen-agents-org/kaizen-loop` |
| Independent verifier component | `kaizen-agents-org/verifier` |
| Code review configuration | `kaizen-agents-org/coderabbit` |
| Renovate configuration | `kaizen-agents-org/renovate-config` |

The first implementation should update `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config`. The `.github` repository remains the source for organization-level shared assets and the workflow implementation.

## What Gets Updated

The daily sync should update deterministic, reviewable files only.

### Shared Skills

Shared skills continue to come from `.github/skills`:

```text
skills/
  gh-link-issue-pr/
  kaizen-bug-router/
  pr-guardian/
```

The daily sync should include the existing shared-skill sync behavior so skill drift and dogfooding contract drift are handled in one scheduled PR loop.

### Dogfooding Contract

Each target repository should keep a small machine-readable and agent-readable contract:

```text
AGENTS.md
skills/
.kaizen/
  config.yml
  dogfood.yml
.github/
  ISSUE_TEMPLATE/
    kaizen.yml
```

The exact file set may vary by repository, but the daily sync should keep these categories aligned:

- verification commands used by `kaizen-loop`
- protected paths and PR-only policy defaults
- issue label and issue template conventions
- local shared skill copies
- adapter, CLI, schema, or prompt references needed for the repository to dogfood the latest component behavior
- generated examples or docs that describe how this repository participates in the issue-to-PR loop

Repository-specific implementation code, handwritten design docs, and broad refactors are out of scope for automatic sync.

## Source Of Truth

Use `.github` for organization-wide shared assets and target repository metadata.

Recommended layout:

```text
.github/
  skills/
  templates/
    dogfood/
      AGENTS.md
      ISSUE_TEMPLATE/
        kaizen.yml
  dogfood/
    repositories.yml
  scripts/
    sync-kaizen-shared-skills.sh
    sync-dogfood-contracts.sh
```

`dogfood/repositories.yml` should describe each target repository's stable settings, such as verification commands, protected paths, issue label, and any component-specific adapter notes. Generated files should be derived from this data and the templates.

Avoid treating free-form `AGENTS.md` content as an unbounded overwrite target. Prefer one of these patterns:

- generate a clearly marked managed section inside `AGENTS.md`
- generate `.kaizen/dogfood.yml` and keep `AGENTS.md` as concise human guidance
- update whole files only when the file is explicitly owned by the dogfood sync

## Automation Choice

The daily sync should run in GitHub Actions, not Codex automations.

GitHub Actions is the better fit for the main sync because it can:

- run on a predictable daily schedule and through `workflow_dispatch`
- clone multiple repositories with an auditable token
- generate deterministic file changes
- push fixed sync branches
- create or update ready-for-review pull requests
- leave a durable run log in GitHub

Codex automations remain useful for review and coordination work:

- detecting ambiguous drift that cannot be fixed deterministically
- writing organization monitor reports
- filing focused `[monitor]` issues
- identifying ownership questions across components

Codex automations should not be the primary mechanism for daily cross-repository file updates.

## GitHub Actions Flow

The intended daily workflow is:

1. Run on a daily cron and on `workflow_dispatch`.
2. Check for `KAIZEN_SYNC_TOKEN`.
3. Check out `.github`.
4. Clone each target repository.
5. Apply shared skill updates.
6. Apply dogfooding contract updates from templates and repository metadata.
7. For each target repository, inspect only the managed paths.
8. If no managed paths changed, report `No dogfood sync changes`.
9. If managed paths changed, commit to a fixed branch.
10. Create or update a ready-for-review PR.

Use fixed branch names so reruns update existing PRs instead of creating duplicates:

```text
codex/sync-kaizen-dogfood
```

If shared skills and dogfooding contract updates stay in separate workflows, use separate branches:

```text
codex/sync-kaizen-shared-skills
codex/sync-kaizen-dogfood
```

The preferred long-term shape is one daily dogfood sync that includes skill synchronization.

Because the workflow reuses fixed branch names, repeated successful runs should normally update the existing sync PR for each target repository instead of accumulating a new PR every day.

## PR Requirements

Generated PRs must be normal ready-for-review pull requests.

Each PR should include:

- a summary of the managed files updated
- whether shared skills changed
- whether dogfooding contract files changed
- verification performed by the sync job
- a note that the PR was generated by the daily dogfood sync

Generated PRs must not:

- be drafts unless a human explicitly requests a draft
- merge themselves
- modify unmanaged application code
- overwrite repository-specific guidance outside managed sections

## Safety Boundaries

The sync should fail closed when ownership is unclear.

Do not automatically update:

- secrets or credentials
- production infrastructure
- dependency lockfiles unrelated to the contract
- arbitrary workflow files outside explicitly managed templates
- large free-form documentation pages
- files with local uncommitted changes in a manual run

If the sync detects a needed update that cannot be made deterministically, it should leave the repository unchanged and report a follow-up item. The organization monitor can turn that follow-up into a focused issue.

## Relationship To Existing Flows

### Shared Skill Sync

[Shared Skill Sync](./shared-skill-sync.md) is the current narrow implementation. It updates only `skills/`.

Daily dogfood sync should absorb or call the shared skill sync so the same daily loop keeps both shared skills and repository dogfooding contracts current.

### Organization Monitor

[Organization Monitor](./org-monitor.md) remains a read-mostly coordination loop. It should check whether daily dogfood sync is working, surface missed drift, and file issues for non-deterministic follow-up work.

The monitor should not replace the deterministic GitHub Actions sync.

### Issue-to-PR MVP

[Issue-to-PR MVP](./issue-to-pr-mvp.md) defines the runtime contract each target repository needs. Daily dogfood sync keeps that contract aligned as the components evolve.

## Initial Implementation Plan

1. Add `dogfood/repositories.yml` in `.github` with target repository metadata.
2. Add dogfood templates for managed files or managed sections.
3. Add `scripts/sync-dogfood-contracts.sh`.
4. Extend or replace the existing shared skill sync workflow with a daily scheduled workflow.
5. Keep the existing shared skill sync behavior available for manual emergency syncs.
6. Open generated PRs in target repositories and let humans review and merge them.

The first implementation should be conservative: update shared skills and a minimal `.kaizen/dogfood.yml` or managed `AGENTS.md` section before attempting broader generated files.
