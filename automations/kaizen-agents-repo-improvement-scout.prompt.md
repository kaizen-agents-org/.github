Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-repo-improvement-scout.prompt.md`.

Scout the active Kaizen Agents repositories for concrete repo-local improvement issues and create focused GitHub issues for the normal Kaizen issue-to-PR loop.

This automation is the improve layer defined by the organization automation roles doc. In a checkout of `kaizen-agents-org/.github`, read it at `docs/automation-roles.md`; from another repository or URL context, `.github/docs/automation-roles.md` means that same file in the organization `.github` repository. It owns proactive repo-local improvement discovery. Do not create `[monitor]` operation issues or `[readiness-review]` issues from this prompt.

Active repositories: `kaizen-agents-org/.github`, `kaizen-agents-org/builder-agent`, `kaizen-agents-org/kaizen-loop`, and `kaizen-agents-org/verifier`. Do not scout `coderabbit` or `renovate-config`; they are downstream shared-configuration repositories and are out of scope unless cited only as sync context for a `.github` finding.

Use the local checkouts or worktrees provided by the Codex automation runtime instead of assuming a workstation-specific absolute path. Prefer running this scout in a Codex worktree execution environment. The expected local repository names are `.github`, `builder-agent`, `kaizen-loop`, and `verifier`. If a local checkout cannot be located, report that local observation as unavailable and continue with GitHub remote checks.

Use the GitHub default branch, expected to be `origin/main` for these repositories, as the source of truth. Before using local files as issue evidence, fetch the target repository with `git -C <repo> fetch --prune origin` when a local checkout is available, then read from the updated default-branch ref or from an isolated temporary worktree created from `origin/main`. Do not create issues from local-only files, feature-branch-only files, dirty worktree changes, or stale unmerged content.

Path convention: when reading from the `kaizen-agents-org/.github` repository checkout or its default-branch ref, organization docs are repository-relative paths under `docs/...`. When referring to the organization docs from another repository or URL context, `.github/docs/...` means the `docs/...` directory in `kaizen-agents-org/.github`.

Read the source-managed organization docs first when available on the `.github` default branch: `docs/architecture.md`, `docs/documentation-sources.md`, `docs/issue-to-pr-mvp.md`, `docs/implementation-status.md`, `docs/repo-improvement-scout.md`, and relevant project-local README/docs from each target repository default branch. Project-local docs may add repository-specific detail, but they must not silently override the organization-level responsibility model.

For each active repository, perform a repo-local improvement scan:

- `.github`: organization documentation, automation prompts, sync source docs, dogfood/shared-skill source contracts, and guidance consistency.
- `builder-agent`: requirement understanding, implementation artifacts, self-review quality, adapter/CLI behavior, backend/model selection, fallback behavior, build-result schema fidelity, and outputs consumed by `kaizen-loop` and `verifier`.
- `kaizen-loop`: orchestration, workspace lifecycle, issue selection, verification command execution, verifier integration, policy/reflection, PR creation/linkage, scheduler, run reporting, and fleet commands.
- `verifier`: independent review depth, verdict quality, schema fidelity, eval harnesses, seeded/golden corpus, false-positive controls, and reproducibility.

Do not create operation, sync, scheduler, CI/check, documentation source-order, fleet refresh, or production-readiness issues unless the finding is also a concrete repo-local improvement in the target repository. Those concerns belong to the monitor or readiness-check layer.

For each repository, inspect default-branch docs and code enough to identify small, actionable improvements. Prefer issues that the normal Kaizen scheduler can complete as one focused PR. Good issue candidates have concrete evidence, a clear owner repository, a bounded expected change, and a documentation basis. Do not create broad roadmap epics, speculative ideas, vague cleanup issues, duplicate issues, or issues that require secrets, billing, production infrastructure, destructive data changes, or human policy decisions before implementation can start.

Before creating issues, establish current GitHub state per active repository. Prefer `gh issue list` and `gh pr list` with explicit `--repo kaizen-agents-org/<repo>` queries. Record counts for open PRs, open `kaizen` issues, and existing scout/monitor/readiness issues per repository. Search open issues and PRs in the target repository first using the proposed title, paths, component names, and conceptual keywords. Search other active repositories only to identify related context; related work elsewhere should be linked in the issue body, but it does not block a repo-local issue unless it clearly owns the same exact work.

Create GitHub issues for concrete, actionable improvements when all of the following are true: the target repository is one of the four active repositories, the improvement is supported by cited default-branch documentation or code evidence, the work is not already covered by an open issue or PR for the same target repository and same actionable follow-up, the issue is ready for the next Kaizen poll/nightly run without clarification, and the target repository has fewer than four open issues labeled `kaizen`. Limit automatic issue creation to at most two issues per target repository per run. Do not apply an organization-wide cap; each active repository should get its own fair chance to create eligible repo-local issues. If there are more eligible findings for a repository, report that repository's extras without creating them.

When creating an issue, add the `kaizen` label and prefix the title with `[scout]`. Each issue body must include:

- summary of the improvement;
- target repository and affected paths or components;
- observed evidence from default branch, including file paths and short descriptions;
- recommended action;
- documentation basis, with source paths, headings when available, and why each source supports the scope;
- duplicate-check summary;
- related issues or PRs, if any.

Produce a concise scout report with: repositories scanned, verified GitHub state, issues created with URLs, eligible findings skipped due target repo issue limit or per-run limit, duplicate findings, repo-local "no issue created" reasons, and any unavailable checks. Do not edit files, push branches, merge PRs, create implementation branches, open implementation PRs, or make broad code changes automatically.
