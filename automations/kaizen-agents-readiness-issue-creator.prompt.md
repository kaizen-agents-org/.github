Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-readiness-issue-creator.prompt.md`.

Create focused Kaizen improvement issues from the latest production-readiness
review report.

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

- `.github/docs/documentation-sources.md`
- `.github/docs/production-readiness/README.md`
- `.github/docs/production-readiness/checklist.md`
- `.github/docs/production-readiness/metrics.md`
- `.github/docs/production-readiness/template.md`
- `.github/docs/production-readiness-log.md`

Use `.github/docs/production-readiness-log.md` as the readiness index. Locate
the latest dated report linked from the index, normally under
`.github/docs/production-readiness/logs/YYYY-MM-DD.md`. Prefer the latest
report on the `.github` repository default branch. If the latest local report is
not present on the default branch, treat it as local-only evidence and do not
create issues from it unless the automation run explicitly supplies that report
as approved input.

Create issues only from the report's `Issue Candidates` section. Do not infer
new issues directly from findings, priorities, or previous automation memory.
If the latest report has no `Issue Candidates` section, or every candidate is
marked blocked, duplicate, unclear, or report-only, create no issues and explain
why.

For each candidate, verify all of the following before creating an issue:

- the target repository is clear;
- the work is concrete, actionable, and small enough for the normal Kaizen
  issue-to-PR flow;
- the candidate is supported by observed evidence in the dated report;
- the candidate is supported by source-managed documentation in the canonical
  source order defined by `.github/docs/documentation-sources.md`;
- the cited documentation exists on the relevant repository default branch when
  practical;
- the work is not already covered by an open issue or PR anywhere in the
  monitored repository set;
- the target repository has fewer than four open issues labeled `kaizen`, unless
  the candidate is a concrete closed-loop health finding about sync, scheduler,
  or CI drift.

Before creating issues, establish current GitHub state per repository. Prefer
`gh issue list` and `gh pr list` with explicit `--repo
kaizen-agents-org/<repo>` queries, or cross-check GitHub connector results with
equivalent `gh` queries when both are available. Search existing open issues and
PRs across all monitored repositories using the candidate title, affected
component, file paths, and conceptual keywords.

Limit issue creation to at most three issues per run across the whole
organization. Use the `kaizen` label and prefix issue titles with
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

After issue creation, produce a concise report with:

1. Source report used.
2. Candidates evaluated.
3. Issues created, with repository and URL.
4. Candidates skipped, with reason.
5. Any verification or GitHub query that was unavailable.

Do not edit files, push branches, merge PRs, create implementation branches, or
open implementation PRs automatically. This automation only creates focused
follow-up issues from a readiness report and reports what it did.
