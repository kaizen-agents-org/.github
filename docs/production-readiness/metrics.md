# Production Readiness Metrics

These metrics define what the weekly review should try to collect. Missing
metrics should be reported as gaps, not estimated.

## Core Outcome Metrics

| Metric | Meaning |
| --- | --- |
| Issue-to-PR success rate | Share of processed `kaizen` issues that produced a ready-for-review PR. |
| Verification failure rate | Share of processed issues that failed mechanical verification after retries. |
| Verifier block rate | Share of verifier runs that returned `block_pr` or `needs_context`. |
| Needs-human rate | Share of issues escalated to `kaizen:needs-human`. |
| PR guardian failure rate | Share of opened PRs where guardian follow-up ended with a blocker. |

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
| Open `kaizen` issue backlog | Number of eligible issues waiting for automated processing. |
| Repeated failure reasons | Most common failure causes across the review window. |
| Post-merge correction rate | Share of merged generated PRs that needed follow-up fixes or reverts. |
| Sync drift count | Number of dogfood or shared-skill drift findings. |

## Interpretation

A production-ready trend requires:

- real E2E smoke evidence, not only mocked integration tests;
- reproducible package verification across the core repositories;
- verifier behavior measured against fixtures or known outcomes;
- issue-link and PR-base checks enforced after PR creation;
- clear decline in repeated failures, needs-human escalations, and manual
  correction after merge.
