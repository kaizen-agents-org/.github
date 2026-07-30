Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-readiness-issue-creator.prompt.md`.
<!-- automation-contract: automation=readiness-issue-creator; issues=[readiness-review]; prs=none; per-repo-limit=3; source=merged-default-branch-readiness-report; roles-doc=docs/automation-roles.md -->

Create focused Kaizen improvement issues from the latest production-readiness
review report.

This automation is a daily post-merge poll. It should create issues only after
the weekly readiness report PR has been merged to `main`; if no new approved
report is available, it should report that and create no issues.

Fetch `origin main` for `kaizen-agents-org/.github` before reading the fleet
registry, readiness docs, or report index. Read `onboarding/fleet.json` from the
updated `origin/main` ref, not from the current checkout.
Repositories with `weeklyReadiness: true` are the complete issue-creation scope,
matching the upstream weekly review. Validate that fetched registry before use;
if it is missing or invalid, report the scope as unavailable and create no
issues. Never edit the registry or substitute a remembered or inferred
repository list.

Use the local checkouts or worktrees provided by the Codex automation runtime.
Prefer running this issue creator in a Codex worktree execution environment.
Resolve expected local repository names from each active registry entry's
`localCheckout`. If a checkout is unavailable, report that observation and
continue with GitHub remote checks.

Before using any located checkout, read its `origin` URL, normalize supported
HTTPS/SSH GitHub URL forms and casing, and require it to match the active
entry's complete `repository` identity. Never accept a directory based only on
its `localCheckout` name. If origin is missing, ambiguous, or belongs to a fork
or different repository, do not use that checkout to validate a candidate's
documentation basis; report the mismatch and use the configured repository's
GitHub default-branch content instead.

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

Using the already fetched `origin/main`, select the report only after the fleet
registry and source-managed readiness docs have been read from that same ref.
Use only `docs/production-readiness-log.md` from the updated `origin/main` ref
as the readiness index. Locate the latest dated report linked from that index,
normally under
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
Skip candidates whose complete target `repository` value is not an active
`weeklyReadiness: true` registry entry; mention them as out of scope in the final
report instead of creating issues.

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

Fleet membership grants observation scope, not write authorization. For the
write-authorization comparison only, normalize the owner segment of
`<repository>` to lowercase; continue passing the original complete `repository`
value unchanged to every GitHub operation. Automatically create issues,
bootstrap labels, or apply authorization/queue labels only when that normalized
owner is exactly `kaizen-agents-org`. For any other owner, keep the candidate
report-only and never perform a GitHub mutation, even when the automation
credentials happen to have write access; external operation requires explicit
human authorization outside this automation.

Before creating issues, establish current GitHub state per repository. For every
GitHub query or mutation, pass the active registry entry's complete `repository`
value unchanged as `--repo <repository>`; never reconstruct it from an owner and
`localCheckout`. Prefer `gh issue list` and `gh pr list` with explicit `--repo
<repository>` queries, or cross-check GitHub connector results with equivalent
`gh` queries when both are available. Search existing open issues and
PRs across every validated `weeklyReadiness: true` fleet entry, including the
candidate's target repository, using the candidate title, affected component,
file paths, and conceptual keywords. Treat duplicate prevention as repo-scoped
by default: related work in another repository should be mentioned in the
duplicate-check summary, but it must not by itself block a concrete repo-local
issue.

Limit issue creation to at most three issues per target repository per run from
the approved dated report. Do not apply an organization-wide cap, and do not let
one repository's open `kaizen` issue count block another repository's eligible
candidate.

Before creating the first issue in each target repository, verify both execution
gate labels. Run `gh label list --repo <repository> --search
"kaizen:authorized" --limit 100 --json name --jq 'any(.name ==
"kaizen:authorized")'` and require an exact `true` result, then do the same for
`kaizen:ready` with `--search "kaizen:ready"` and `any(.name ==
"kaizen:ready")`. If a label is absent, bootstrap it with `gh label create
"kaizen:authorized" --repo <repository> --color "5319E7"
--description "Approved for Kaizen execution"` or `gh label create
"kaizen:ready" --repo <repository> --color "0E8A16" --description
"Eligible for scheduled Kaizen selection"`, as applicable, then re-run the same
exact-name query. Label creation requires write permission; triage permission is
sufficient only to apply an existing label. If the automation lacks write
permission, report that a maintainer with write permission must pre-provision
the labels. If either label cannot be created and verified, do not create the
issue; report the candidate as blocked by missing execution-gate label setup.
Never create an issue while allowing a missing `kaizen:authorized` or
`kaizen:ready` label to be silently dropped.

Add the `kaizen`, `kaizen:authorized`, and `kaizen:ready` labels and prefix issue
titles with `[readiness-review]` so it is clear they were created from the
readiness review automation. Authorization and queue selection are separate
gates: `kaizen:authorized` records trusted execution approval, while
`kaizen:ready` makes the issue eligible for the fleet's opt-in scheduled
selector. This automatic authorization and selection is the explicit
`kaizen-agents-org` dogfooding policy documented in `docs/automation-roles.md`;
do not generalize it to external operation mode, where human authorization and
queue selection remain explicit maintainer actions. The actor applying
`kaizen:authorized` must have at least triage permission in the target repository
so `kaizen-loop` accepts the label event. Each issue body must include:

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
<repository>#<issue-number>` for cross-repository work in the PR
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
