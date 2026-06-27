Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-monthly-readiness-review.prompt.md`.

Run the monthly Kaizen Agents production-readiness review across the local
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

Use the latest entry in `.github/docs/production-readiness-log.md` as the
baseline for the monthly delta. Separate default-branch documentation facts from
local-only observations. Before citing a document as issue basis, verify it
exists on the repository default branch when practical.

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

Produce a concise monthly readiness report with:

1. Review date.
2. Repositories reviewed.
3. Verification observed.
4. Metrics observed, explicitly marking unavailable metrics.
5. Delta since the previous readiness log entry.
6. Current findings ordered by production-readiness risk.
7. Recommended priority for the next month.
8. A proposed Markdown entry for `.github/docs/production-readiness-log.md`
   using `.github/docs/production-readiness/template.md`.

Do not edit files, push branches, merge PRs, or create broad implementation
changes automatically. If the proposed log entry should be committed, leave it
as report text for a human or a normal ready-for-review PR.

Create GitHub issues only when all of these are true:

- the issue is concrete and actionable;
- the target repository is clear;
- the finding is not already covered by an open issue or PR across the monitored
  repository set;
- the issue is supported by observed evidence or source-managed documentation;
- the work is small enough for the normal Kaizen issue-to-PR flow;
- the issue body includes evidence, affected repository, recommended action,
  and documentation basis when applicable.

Limit issue creation to at most three issues per run. Use the `kaizen` label and
prefix issue titles with `[readiness]`. If no issues are created, say why.

Do not treat this monthly review as approval for production-grade autonomous
maintenance. The review records readiness evidence and gaps; human review still
controls merge and production-readiness claims.
