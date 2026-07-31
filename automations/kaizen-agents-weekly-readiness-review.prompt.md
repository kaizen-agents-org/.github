Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-weekly-readiness-review.prompt.md`.
<!-- automation-contract: automation=weekly-readiness-review; issues=none; prs=readiness-report; per-repo-limit=0; source=default-branch; roles-doc=docs/automation-roles.md -->

Run the weekly Kaizen Agents production-readiness review across the local
repositories and GitHub remotes.

Before any source fetch, verify that the `.github` checkout's `origin` URL.
After normalizing supported HTTPS/SSH GitHub forms and casing, the source
repository identity must be exactly `kaizen-agents-org/.github`. If the
canonical source checkout or origin cannot be verified, report the review as
blocked and do not derive fleet scope or
publish a report PR from an unverified remote.

Fetch `origin main` for `kaizen-agents-org/.github` before reading the fleet
registry or source-managed readiness docs. Read `onboarding/fleet.json` from the
updated `origin/main` ref, not from the current checkout, and record that commit
as `<sourceSha>`. Repositories with
`weeklyReadiness: true` are the complete review scope. Validate that fetched
registry before use; if it is missing or invalid, report scope collection as
blocked and do not substitute a remembered or inferred list. The registry is
reviewed configuration and is read-only to this automation; never edit it from a
readiness review.

Read the registry, every source-managed readiness document listed below, the
readiness index, and the prior report from exactly `<sourceSha>` using `git show
<sourceSha>:<path>` or a detached worktree created at `<sourceSha>`. Never read
those inputs from the current working tree. Treat a missing file at that commit
as unavailable source evidence rather than falling back to local content.

Use the local checkouts or worktrees provided by the Codex automation runtime.
Prefer running this review in a Codex worktree execution environment. Resolve
expected local repository names from each scoped registry entry's
`localCheckout`. If a checkout is unavailable, report that observation and
continue with GitHub remote checks.

Before using any located checkout, read its `origin` URL, normalize supported
HTTPS/SSH GitHub URL forms and casing, and require it to match the scoped
entry's complete `repository` identity. Never accept a directory based only on
its `localCheckout` name. If origin is missing, ambiguous, or belongs to a fork
or different repository, do not run status or verification commands there;
report the mismatch and use the configured repository's GitHub default-branch
content and CI evidence instead.

For every scoped repository, resolve its current default branch with `gh repo
view <repository> --json defaultBranchRef --jq '.defaultBranchRef.name'` and
record the corresponding remote head as `<targetSha>`. For a verified checkout,
fetch that branch and run verification only in an isolated detached worktree at
`<targetSha>`, never in its current working tree. Otherwise cite only current
GitHub CI/check evidence explicitly tied to `<targetSha>`. If neither
commit-pinned verification path is available, mark verification unavailable;
do not attribute stale or feature-branch results to the fleet target.

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
the current review, collect `kaizen status --project <projectSlug> --metrics
--json` for every scoped registry entry, using its `projectSlug`, and write or
update `docs/metrics/<ISO-week>.md` before writing the dated readiness report.

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
- repository-specific verification for every scoped registry entry: derive the
  canonical commands from that repository's default-branch CI configuration,
  package/build metadata, and documentation, then run or cite those commands;
  do not assume a Node.js stack or reuse another repository's commands;
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
   creation. Every scoped registry entry must have a row even when it has no
   ready candidate.
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
Repositories not enabled for weekly readiness in the registry may appear only
as downstream or cross-repository context when evidence requires mentioning
them.

After producing the report, create or update a normal ready-for-review PR in
`kaizen-agents-org/.github` containing only these repository-relative paths:

- `docs/production-readiness/logs/YYYY-MM-DD.md`
- `docs/production-readiness-log.md`
- `docs/metrics/<ISO-week>.md`

Fetch `origin main` again immediately before writing and compare its commit to
`<sourceSha>`. If it changed, discard the derived report, metrics, and candidate
scope, reload the registry and readiness sources from the new commit, and
restart the full review; never publish outputs derived from mixed source SHAs.
Only after the final fetch still matches `<sourceSha>`, base the branch on that
updated default branch. Use a deterministic branch name such as
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
