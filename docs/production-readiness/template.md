# Production Readiness Review Template

Create each review as `docs/production-readiness/logs/YYYY-MM-DD.md`, using the
review date as the file name. After adding a dated review file, update
[Production Readiness Log](../production-readiness-log.md) with a short index
entry and latest summary row.

```markdown
# Production Readiness Review: YYYY-MM-DD

## Scope

Reviewed repositories:

- `kaizen-agents-org/.github`
- `kaizen-agents-org/kaizen-loop`
- `kaizen-agents-org/builder-agent`
- `kaizen-agents-org/verifier`

## Summary

<One paragraph describing whether readiness improved, regressed, or stayed the
same since the previous entry.>

## Verification Observed

Passed:

- `<repo>`: `<commands or CI reference>`

Failed or unavailable:

- `<repo>`: `<failure or reason unavailable>`

## Metrics Observed

| Metric | Value | Evidence |
| --- | --- | --- |
| Issue-to-PR success rate | unavailable | <why> |
| Verification failure rate | unavailable | <why> |
| Verifier block rate | unavailable | <why> |
| Needs-human rate | unavailable | <why> |
| PR guardian failure rate | unavailable | <why> |
| Sandbox E2E pass count | unavailable | <why> |
| Verifier eval agreement | unavailable | <why> |
| Verifier false-positive rate | unavailable | <why> |
| PR linkage success rate | unavailable | <why> |
| Safety-check coverage | unavailable | <why> |
| Non-Node E2E pass count | unavailable | <why> |
| Stack-assumption issue count | unavailable | <why> |
| Open PR backlog | unavailable | <why> |
| Open `kaizen` issue backlog | unavailable | <why> |
| Repeated failure reasons | unavailable | <why> |
| Post-merge correction rate | unavailable | <why> |
| Sync drift count | unavailable | <why> |

## Repository / CI / PR State

- Repository state: <branch, upstream, and default-branch alignment>
- CI state: <latest relevant checks or reason unavailable>
- PR state: <open generated PR count, blockers, or reason unavailable>
- Stack-independence state: <completed non-Node E2E run, filed assumption
  issues, or reason unavailable>
- Explicit gaps: <metrics or state that could not be collected>

## Findings

1. <Finding title>

   Evidence: <specific observed evidence>

   Impact: <operational impact>

   Needed next step: <focused action>

## Priority

Recommended order:

1. <highest priority>
2. <next priority>
3. <next priority>

## Issue Candidates

These candidates are the only inputs the readiness issue-creator automation may
turn into GitHub issues. Created issue titles use the `[readiness-review]`
prefix.

| Candidate | Target repository | Status | Evidence | Documentation basis |
| --- | --- | --- | --- | --- |
| <short issue title> | `kaizen-agents-org/<repo>` | ready / blocked / duplicate / unclear / report-only | <report evidence> | <docs and headings> |

## Current Readiness Judgment

<Ready for continued dogfooding / not ready for production-grade autonomy /
other explicit judgment.>
```
