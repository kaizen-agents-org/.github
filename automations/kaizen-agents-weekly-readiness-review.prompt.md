Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-weekly-readiness-review.prompt.md`.

Run the weekly Kaizen Agents production-readiness review across the local
repositories and GitHub remotes.

Repositories in scope:

- `kaizen-agents-org/.github`
- `kaizen-agents-org/kaizen-loop`
- `kaizen-agents-org/builder-agent`
- `kaizen-agents-org/verifier`
- `kaizen-agents-org/coderabbit`
- `kaizen-agents-org/renovate-config`

Use local checkouts provided by the Codex automation runtime. Expected local
repository names are `.github`, `kaizen-loop`, `builder-agent`, `verifier`,
`coderabbit`, and `renovate-config`. If a checkout is unavailable, report that
observation and continue with GitHub remote checks.

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
7. Recommended priority for the next week.
8. Issue candidates suitable for the follow-up issue-creator automation,
   including target repository, evidence, documentation basis, and skip reason
   when a finding is not ready for issue creation.
9. A proposed Markdown file for
   `.github/docs/production-readiness/logs/YYYY-MM-DD.md` using
   `.github/docs/production-readiness/template.md`.
10. A proposed index update for `.github/docs/production-readiness-log.md`.

Do not edit files, push branches, merge PRs, or create broad implementation
changes automatically. If the proposed dated review file and index update should
be committed, leave them as report text for a human or a normal
ready-for-review PR.

Do not create GitHub issues from this weekly review prompt. The review should
produce a structured `Issue Candidates` section only. The separate
`kaizen-agents-readiness-issue-creator` automation consumes the latest dated
readiness report and creates at most three duplicate-free issues after applying
its stricter validation rules. Candidate titles should be written without the
final automation prefix; the issue creator adds `[readiness-review]` to created
GitHub issue titles. If a finding is not ready for issue creation, mark it as
blocked, duplicate, unclear, or report-only in the issue candidates section.

Do not treat this weekly review as approval for production-grade autonomous
maintenance. The review records readiness evidence and gaps; human review still
controls merge and production-readiness claims.
