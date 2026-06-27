# Monthly Readiness Checklist

Use this checklist for each monthly readiness review.

## Repository State

- Confirm local checkout availability for `.github`, `kaizen-loop`,
  `builder-agent`, `verifier`, `coderabbit`, and `renovate-config`.
- Record local branch and upstream state.
- Distinguish local-only observations from default-branch facts.
- Check open PR and open `kaizen` issue counts per repository.
- List existing readiness, monitor, sync, CI, or production-hardening issues.

## Verification

- Run or cite the latest available verification for `kaizen-loop`:
  `npm test`, `npm run typecheck`, and `npm run build`.
- Run or cite the latest available verification for `builder-agent`:
  `npm test` and `npm run validate:json`.
- Run or cite the latest available verification for `verifier`:
  `pnpm typecheck`, `pnpm test`, and `pnpm schema:check`.
- Record exact failures, including whether they are environment/setup failures
  or product failures.

## End-To-End Evidence

- Check whether a sandbox or dogfood issue completed the full flow:
  issue selection, builder-agent, mechanical verification, verifier, PR creation,
  issue-link recognition, and PR guardian follow-up.
- Record the issue, branch, PR, verifier verdict, and linkage result when
  available.
- If no real E2E evidence exists, keep that as a readiness gap.

## Verifier Quality

- Check whether the verifier has an executable eval harness.
- Record seeded-bug, golden PR, false-positive, and reproducibility results when
  available.
- Note whether verifier behavior is still limited to MVP heuristics.

## Safety And Operations

- Check process termination, timeout, environment handling, disk preflight, and
  shutdown cleanup behavior against the safety docs.
- Check PR creation readiness: default branch target, non-draft status, and
  `closingIssuesReferences`.
- Check dogfood sync and shared-skill sync health.
- Check local fleet refresh readiness when practical.

## Metrics

- Record success, failure, blocked, and needs-human counts when available.
- Record verifier block/warning rates when available.
- Record processing time and repeated failure reasons when available.
- Record post-merge correction, revert, or follow-up-fix signals when available.

## Output

- Write a dated readiness report.
- Prepare a proposed entry for
  [Production Readiness Log](../production-readiness-log.md).
- Create at most three focused issues for concrete, duplicate-free follow-up
  work.
