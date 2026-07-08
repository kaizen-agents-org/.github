# Production Readiness Metrics

These metrics define what the weekly review should try to collect. Missing
metrics should be reported as gaps, not estimated.

## North-Star Metric

| Metric | Meaning | Denominator |
| --- | --- | --- |
| Human-edit-free merge rate | Share of generated PRs that merged without additional human-authored fixup commits after automation opened the PR. | Merged generated PRs inspected in the review window. |

## Core Outcome Metrics

| Metric | Meaning | Denominator |
| --- | --- | --- |
| Issue-to-PR success rate | Share of processed `kaizen` issues that produced a ready-for-review PR. | Processed `kaizen` issues in the review window. |
| Verification failure rate | Share of processed issues that failed mechanical verification after retries. | Processed `kaizen` issues in the review window. |
| Verifier block rate | Share of verifier decisions that returned `block_pr` or `needs_context`. | Verifier decisions in the review window. |
| Needs-human rate | Share of issues escalated to `kaizen:needs-human`, or point-in-time needs-human backlog when transition data is unavailable. | Processed issues for transition rate, or open `kaizen` issues for backlog rate. |
| PR guardian failure rate | Share of opened PRs where guardian follow-up ended with a blocker. | Guardian-eligible PRs in the review window. |
| Median time-to-merge | Median elapsed time from generated PR creation to merge. | Merged generated PRs inspected in the review window. |

## Readiness Evidence Metrics

| Metric | Meaning |
| --- | --- |
| Sandbox E2E pass count | Number of controlled end-to-end smoke runs that completed successfully. |
| Verifier eval agreement | Agreement between verifier verdicts and expected seeded/golden outcomes. |
| Verifier false-positive rate | Share of reported findings judged not actionable by review or eval labels. |
| PR linkage success rate | Share of generated PRs with recognized `closingIssuesReferences`. |
| Safety-check coverage | Whether timeout, process-tree kill, env allowlist, disk preflight, and shutdown cleanup are tested. |

## Operational Health Metrics

| Metric | Meaning |
| --- | --- |
| Open PR backlog | Number of open generated PRs waiting for review or fixes. |
| Open PR age | Oldest and median age of open generated PRs. |
| Open `kaizen` issue backlog | Number of eligible issues waiting for automated processing. |
| Repeated failure reasons | Most common failure causes across the review window. |
| Post-merge correction rate | Share of merged generated PRs that needed follow-up fixes or reverts. |
| Sync drift count | Number of dogfood or shared-skill drift findings. |

## Weekly Persistence

The weekly readiness review persists collected metrics under
`docs/metrics/<ISO-week>.md` before opening the readiness report PR. Each
snapshot should cite the source commands, cover `.github`, `kaizen-loop`,
`builder-agent`, and `verifier`, and include the denominator used for each
reported rate. Missing metrics stay visible as unavailable rows with the
inspected denominator and the reason the numerator could not be collected.

## Interpretation

A production-ready trend requires:

- real E2E smoke evidence, not only mocked integration tests;
- reproducible package verification across the core repositories;
- verifier behavior measured against fixtures or known outcomes;
- issue-link and PR-base checks enforced after PR creation;
- clear decline in repeated failures, needs-human escalations, and manual
  correction after merge.
