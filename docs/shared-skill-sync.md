# Shared Skill Sync

This document describes how shared Kaizen Agents skills are made available inside the core projects and how updates are propagated.

## Goal

Each core project should support the same operating workflows:

- Creating implementation PRs that correctly link and close their source issues.
- Filing Kaizen Agents bugs in the repository that owns the failure.
- Falling back to `kaizen-loop` when a bug spans projects or ownership is unclear.
- Guarding opened PRs until they are mergeable, including CI monitoring and review-comment follow-up.

The shared skills make those workflows available in:

- `kaizen-loop`
- `builder-agent`
- `verifier`
- `coderabbit`
- `renovate-config`

## Source Of Truth

The organization-level `.github` repository owns the shared skill source:

```text
skills/
  gh-link-issue-pr/
  kaizen-bug-router/
  pr-guardian/
```

The core projects vendor copies of those directories under their own `skills/` directory. Their `AGENTS.md` files tell Codex to use the local copies when opening issue-linked PRs or routing Kaizen bug reports.

## Update Flow

When shared skills change in `.github`:

1. The change is reviewed and merged in `.github`.
2. `.github/workflows/sync-kaizen-shared-skills.yml` runs on `main`.
3. The workflow copies `.github/skills` into:
   - `builder-agent/skills`
   - `verifier/skills`
   - `kaizen-loop/skills`
   - `coderabbit/skills`
   - `renovate-config/skills`
4. If a target project changes, the workflow updates or creates a ready-for-review PR in that project.
5. A human reviews and merges each sync PR.

The sync workflow does not merge PRs automatically.

## Manual Sync

For local or emergency syncs, run the script from a checkout where `.github`, `builder-agent`, `verifier`, `kaizen-loop`, `coderabbit`, and `renovate-config` are siblings:

```sh
cd kaizen-agents-org/.github
scripts/sync-kaizen-shared-skills.sh "$PWD" \
  "$PWD/../builder-agent" \
  "$PWD/../verifier" \
  "$PWD/../kaizen-loop" \
  "$PWD/../coderabbit" \
  "$PWD/../renovate-config"
```

Then review, test as needed, and open normal ready-for-review PRs in the target repositories.

## Optional Secret

`KAIZEN_SYNC_TOKEN` is optional and only needed to enable cross-repository sync. If the secret is missing, the workflow exits successfully after reporting a skipped sync instead of failing `main`.

When configured, the token must be able to:

- clone `kaizen-agents-org/builder-agent`, `kaizen-agents-org/verifier`, `kaizen-agents-org/kaizen-loop`, `kaizen-agents-org/coderabbit`, and `kaizen-agents-org/renovate-config`
- push branches to those repositories
- create pull requests in those repositories

The workflow uses a fixed branch name, `codex/sync-kaizen-shared-skills`, per target repository and updates an existing open sync PR instead of creating duplicate PRs.

## Relationship To Issue-to-PR MVP

The shared skills are not the runtime loop by themselves. They support the MVP by making the same agent-facing procedures available in each project:

- `gh-link-issue-pr` keeps generated PRs connected to their source GitHub issues.
- `kaizen-bug-router` turns observed Kaizen Agents bugs into routed GitHub issues.
- `pr-guardian` monitors opened PRs until checks and review feedback are resolved or a real blocker is reported.
- `.kaizen/config.yml` and `.github/ISSUE_TEMPLATE/kaizen.yml` remain the per-repository runtime contract for issue selection and PR creation.

## Relationship To Daily Dogfood Sync

This workflow is intentionally narrow: it updates shared skills only.

[Daily Dogfood Sync](./daily-dogfood-sync.md) is the broader intended loop for keeping each repository's dogfooding contract aligned as Kaizen Agents components change. The daily loop should include this shared-skill sync behavior, but also handle deterministic contract files such as `.kaizen` configuration, issue templates, and managed agent guidance.
