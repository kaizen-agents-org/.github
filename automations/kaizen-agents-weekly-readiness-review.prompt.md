Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-weekly-readiness-review.prompt.md`.

Run the weekly Kaizen Agents production-readiness review across the local
repositories and GitHub remotes.

Repositories in scope:

- `kaizen-agents-org/.github`
- `kaizen-agents-org/kaizen-loop`
- `kaizen-agents-org/builder-agent`
- `kaizen-agents-org/verifier`

Use the local checkouts or worktrees provided by the Codex automation runtime.
Prefer running this review in a Codex worktree execution environment. Expected
local repository names are `.github`, `kaizen-loop`, `builder-agent`, and
`verifier`. If a checkout is unavailable, report that observation and continue
with GitHub remote checks.

Read these source-managed readiness docs first:

- `.github/docs/production-readiness/README.md`
- `.github/docs/production-readiness/checklist.md`
- `.github/docs/production-readiness/metrics.md`
- `.github/docs/production-readiness/template.md`
- `.github/docs/production-readiness-log.md`

Use `.github/docs/production-readiness-log.md` as the readiness index. Read the
latest dated review file linked from that index, normally under
`.github/docs/production-readiness/logs/YYYY-MM-DD.md`, as the baseline for the
weekly delta. Separate default-branch documentation facts from local-only
observations. Before citing a document as issue basis, verify it exists on the
repository default branch when practical.

Collect evidence for:

- local git status, branch/upstream alignment, and default-branch alignment;
- open PR counts and open `kaizen` issue counts per repository;
- existing readiness, monitor, sync, CI, verifier, or safety-hardening issues;
- CI/check status where available;
- `kaizen-loop` verification: `npm test`, `npm run typecheck`, `npm run build`;
- `builder-agent` verification: `npm test`, `npm run validate:json`;
- `verifier` verification: `pnpm typecheck`, `pnpm test`,
  `pnpm schema:check`;
- real sandbox or dogfood E2E evidence for issue-to-PR completion;
- `builder-agent` contract health: result artifact quality, self-review report
  usefulness, adapter/CLI reproducibility, backend/model selection behavior,
  fallback behavior, verifier-consumable output quality, and
  `discoveredIssues` output quality;
- verifier eval harness or seeded/golden corpus evidence;
- safety controls: process-tree termination, run-level timeout, environment
  allowlist, disk preflight, shutdown cleanup;
- PR readiness controls: default branch target, non-draft PRs, recognized
  `closingIssuesReferences`;
- dogfood sync, shared-skill sync, and fleet refresh readiness.

Produce a concise weekly readiness report with:

1. Review date.
2. Repositories reviewed.
3. Verification observed.
4. Metrics observed, explicitly marking unavailable metrics.
5. Delta since the previous readiness log entry.
6. Current findings ordered by production-readiness risk.
7. Repository-by-repository readiness coverage. Include every repository in
   scope. For each repository, list ready issue candidates or explicitly state
   why no repo-local candidate is ready. Do not let higher-priority findings in
   `kaizen-loop` or `verifier` hide `builder-agent` or `.github` follow-ups.
8. Recommended priority for the next week.
9. Issue candidates suitable for the follow-up issue-creator automation,
   grouped by target repository and including target repository, evidence,
   documentation basis, and skip reason when a finding is not ready for issue
   creation. The `builder-agent` row must be present even when it has no ready
   candidate.
10. A proposed Markdown file for
   `.github/docs/production-readiness/logs/YYYY-MM-DD.md` using
   `.github/docs/production-readiness/template.md`.
11. A proposed index update for `.github/docs/production-readiness-log.md`.

When producing issue candidates, evaluate ownership by repository responsibility
instead of by the broad system symptom. Use `builder-agent` for gaps in
implementation artifacts, self-review quality, adapter/CLI behavior, backend
selection/fallback, build-result schema fidelity, or outputs consumed by
`kaizen-loop` and `verifier`. Use `kaizen-loop` for orchestration, workspace,
policy, verification command execution, PR creation, scheduling, and run
metrics. Use `verifier` for independent review depth and verdict quality. Use
`.github` for organization documentation, automations, and sync source docs.
`coderabbit` and `renovate-config` are not weekly readiness targets; they may
appear only as downstream sync targets when `.github` sync evidence requires
mentioning them.

Do not edit files, push branches, merge PRs, or create broad implementation
changes automatically. If the proposed dated review file and index update should
be committed, leave them as report text for a human or a normal
ready-for-review PR.

Do not create GitHub issues from this weekly review prompt. The review should
produce a structured `Issue Candidates` section only. The separate
`kaizen-agents-readiness-issue-creator` automation consumes the latest dated
readiness report and creates at most three duplicate-free issues per target
repository after applying its stricter validation rules. Candidate titles should
be written without the final automation prefix; the issue creator adds
`[readiness-review]` to created GitHub issue titles. If a finding is not ready
for issue creation, mark it as blocked, duplicate, unclear, or report-only in the
issue candidates section.

Do not treat this weekly review as approval for production-grade autonomous
maintenance. The review records readiness evidence and gaps; human review still
controls merge and production-readiness claims.
