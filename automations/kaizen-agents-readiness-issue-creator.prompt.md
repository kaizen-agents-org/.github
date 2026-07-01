Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-readiness-issue-creator.prompt.md`.

Create focused Kaizen improvement issues from the latest production-readiness
review report.

This automation is a daily post-merge poll. It should create issues only after
the weekly readiness report PR has been merged to `main`; if no new approved
report is available, it should report that and create no issues.

Repositories in scope:

- `kaizen-agents-org/.github`
- `kaizen-agents-org/kaizen-loop`
- `kaizen-agents-org/builder-agent`
- `kaizen-agents-org/verifier`

Use the local checkouts or worktrees provided by the Codex automation runtime.
Prefer running this issue creator in a Codex worktree execution environment.
Expected local repository names are `.github`, `kaizen-loop`, `builder-agent`,
and `verifier`. If a checkout is unavailable, report that observation and
continue with GitHub remote checks.

Path convention: when reading from the `kaizen-agents-org/.github` repository
checkout or its default-branch ref, organization docs are repository-relative
paths under `docs/...`. When referring to those same files from another
repository or URL context, `.github/docs/...` means the `docs/...` directory in
`kaizen-agents-org/.github`.

Read these source-managed readiness docs first:

- `docs/automation-roles.md`
- `docs/documentation-sources.md`
- `docs/production-readiness/README.md`
- `docs/production-readiness/checklist.md`
- `docs/production-readiness/metrics.md`
- `docs/production-readiness/template.md`
- `docs/production-readiness-log.md`

Fetch `origin main` for `kaizen-agents-org/.github` before selecting a report.
Use only `docs/production-readiness-log.md` from the updated
`origin/main` ref as the readiness index. Locate the latest dated report linked
from that index, normally under
`docs/production-readiness/logs/YYYY-MM-DD.md`, and read that report
only from `origin/main`. Do not create issues from local-only reports, open PR
contents, proposed report text, unmerged branches, or previous automation
memory. If no dated report is available on `origin/main`, create no issues and
report that no approved readiness report exists yet.

Create issues only from the report's `Issue Candidates` section. Do not infer
new issues directly from findings, priorities, or previous automation memory.
If the latest report has no `Issue Candidates` section, or every candidate is
marked blocked, duplicate, unclear, or report-only, create no issues and explain
why.
Skip candidates targeting repositories outside the active scope above, including
`kaizen-agents-org/coderabbit` and `kaizen-agents-org/renovate-config`; mention
them as out of scope in the final report instead of creating issues.

For each candidate, verify all of the following before creating an issue:

- the target repository is clear;
- the work is concrete, actionable, and small enough for the normal Kaizen
  issue-to-PR flow;
- the candidate is supported by observed evidence in the dated report;
- the candidate is supported by source-managed documentation in the canonical
  source order defined by `docs/documentation-sources.md`;
- the cited documentation exists on the relevant repository default branch when
  practical;
- the work is not already covered by an open issue or PR for the same target
  repository and same actionable follow-up, or by an explicit cross-repo
  coordination issue that owns that exact work;
- the target repository has fewer than four open issues labeled `kaizen`, unless
  the candidate is a concrete closed-loop health finding about sync, scheduler,
  or CI drift.

Before creating issues, establish current GitHub state per repository. Prefer
`gh issue list` and `gh pr list` with explicit `--repo
kaizen-agents-org/<repo>` queries, or cross-check GitHub connector results with
equivalent `gh` queries when both are available. Search existing open issues and
PRs across all monitored repositories using the candidate title, affected
component, file paths, and conceptual keywords. Treat duplicate prevention as
repo-scoped by default: related work in another repository should be mentioned in
the duplicate-check summary, but it must not by itself block a concrete
repo-local issue.

Limit issue creation to at most three issues per target repository per run from
the approved dated report. Do not apply an organization-wide cap, and do not let
one repository's open `kaizen` issue count block another repository's eligible
candidate. Use the `kaizen` label and prefix issue titles with
`[readiness-review]` so it is clear they were created from the readiness review
automation. Each issue body must include:

- summary of the improvement;
- source report path and review date;
- evidence from the report;
- affected repository or repositories;
- recommended action;
- documentation basis with document paths, headings, and why each source
  supports the issue scope;
- duplicate-check summary.

Each created issue must also include a `PR linkage requirement` section. State
that the implementation PR for this issue must target the repository default
branch, include `Closes #<issue-number>` for same-repository work or `Closes
kaizen-agents-org/<repo>#<issue-number>` for cross-repository work in the PR
body, and verify `gh pr view <pr> --json baseRefName,closingIssuesReferences,isDraft`
before reporting the PR ready. Do not rely on a PR title, branch name, or issue
comment as proof that GitHub will close the issue on merge.

After issue creation, produce a concise report with:

1. Source report used.
2. Candidates evaluated.
3. Issues created, with repository and URL.
4. Candidates skipped, with reason.
5. Any verification or GitHub query that was unavailable.

Do not edit files, push branches, merge PRs, create implementation branches, or
open implementation PRs automatically. This automation only creates focused
follow-up issues from a readiness report and reports what it did.
