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

Path convention: when reading or writing files in the `kaizen-agents-org/.github`
repository checkout or its default-branch ref, use repository-relative paths
such as `docs/production-readiness-log.md`. When referring to those same files
from another repository or URL context, `.github/docs/...` means the `docs/...`
directory in `kaizen-agents-org/.github`.

Read these source-managed readiness docs first:

- `docs/automation-roles.md`
- `docs/metrics/README.md`
- `docs/production-readiness/README.md`
- `docs/production-readiness/checklist.md`
- `docs/production-readiness/metrics.md`
- `docs/production-readiness/template.md`
- `docs/production-readiness-log.md`

Use `docs/production-readiness-log.md` as the readiness index. Read the
latest dated review file linked from that index, normally under
`docs/production-readiness/logs/YYYY-MM-DD.md`, as the baseline for the
weekly delta. Separate default-branch documentation facts from local-only
observations. Before citing a document as issue basis, verify it exists on the
repository default branch when practical.

Read the latest weekly metrics file under `docs/metrics/` when one exists. For
the current review, collect `kaizen status --project <slug> --metrics --json`
for these slugs and write or update `docs/metrics/<ISO-week>.md` before writing
the dated readiness report:

- `kaizen-agents-org-.github`
- `kaizen-agents-org-kaizen-loop`
- `kaizen-agents-org-builder-agent`
- `kaizen-agents-org-verifier`

The weekly metrics file must include denominators for human-edit-free merge
rate, time-to-merge, Issue-to-PR success rate, verifier block rate,
needs-human rate, and open PR age. If a metric cannot be collected, mark it
unavailable with the denominator actually inspected and the reason the numerator
or timestamp is missing. Do not estimate missing values. The readiness report's
Metrics Observed section must cite the current weekly metrics file instead of
repeating a generic "metrics unavailable" finding when the snapshot exists.

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
4. Metrics observed, explicitly marking unavailable metrics. Cite
   `docs/metrics/<ISO-week>.md` and summarize its denominator-bearing rates.
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
10. The Markdown content written to
   `docs/production-readiness/logs/YYYY-MM-DD.md` using
   `docs/production-readiness/template.md`.
11. The index update written to `docs/production-readiness-log.md`.
12. The weekly metrics content written to `docs/metrics/<ISO-week>.md`.

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

After producing the report, create or update a normal ready-for-review PR in
`kaizen-agents-org/.github` containing only these repository-relative paths:

- `docs/production-readiness/logs/YYYY-MM-DD.md`
- `docs/production-readiness-log.md`
- `docs/metrics/<ISO-week>.md`

Fetch `origin main` before writing. Base the branch on the updated default
branch. Use a deterministic branch name such as
`codex/weekly-readiness-review-YYYY-MM-DD`. If a same-date readiness report PR
already exists, update that branch and PR instead of opening a duplicate. If the
same dated report already exists on `origin/main`, report that no report PR is
needed. The PR must be a normal ready-for-review PR, not a draft. The PR body
must explain that the separate readiness issue creator will only create issues
after this report PR is merged to `main`.

After opening or updating that report PR, run the project `pr-guardian`
workflow for the report PR. Continue until the report PR is merge-ready or has a
specific external blocker. If the guardian finds CI, CodeRabbit, Codex, bot, or
human feedback that applies to the report PR, fix only the allowed readiness
report and weekly metrics paths above or explain why a suggestion is not
applicable.

Do not edit files outside the allowed readiness report and weekly metrics paths
above. Do not merge PRs, create GitHub issues, create implementation branches,
or make broad implementation changes automatically.

Do not create GitHub issues from this weekly review prompt. The review should
produce a structured `Issue Candidates` section only. The separate
`kaizen-agents-readiness-issue-creator` automation consumes the latest dated
readiness report from `origin/main` after the report PR is merged and creates at
most three duplicate-free issues per target repository after applying its
stricter validation rules. Candidate titles should be written without the final
automation prefix; the issue creator adds
`[readiness-review]` to created GitHub issue titles. If a finding is not ready
for issue creation, mark it as blocked, duplicate, unclear, or report-only in the
issue candidates section.

Do not treat this weekly review as approval for production-grade autonomous
maintenance. The review records readiness evidence and gaps; human review still
controls merge and production-readiness claims.
