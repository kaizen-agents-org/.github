# Production Readiness Log Template

Copy this template into
[Production Readiness Log](../production-readiness-log.md) for each monthly
entry.

```markdown
## YYYY-MM-DD

### Scope

Reviewed repositories:

- `kaizen-agents-org/.github`
- `kaizen-agents-org/kaizen-loop`
- `kaizen-agents-org/builder-agent`
- `kaizen-agents-org/verifier`
- `kaizen-agents-org/coderabbit`
- `kaizen-agents-org/renovate-config`

### Summary

<One paragraph describing whether readiness improved, regressed, or stayed the
same since the previous entry.>

### Verification Observed

Passed:

- `<repo>`: `<commands or CI reference>`

Failed or unavailable:

- `<repo>`: `<failure or reason unavailable>`

### Metrics Observed

| Metric | Value | Evidence |
| --- | --- | --- |
| Issue-to-PR success rate | unavailable | <why> |
| Sandbox E2E pass count | unavailable | <why> |
| Verifier eval agreement | unavailable | <why> |
| PR linkage success rate | unavailable | <why> |

### Findings

1. <Finding title>

   Evidence: <specific observed evidence>

   Impact: <operational impact>

   Needed next step: <focused action>

### Priority

Recommended order:

1. <highest priority>
2. <next priority>
3. <next priority>

### Current Readiness Judgment

<Ready for continued dogfooding / not ready for production-grade autonomy /
other explicit judgment.>
```
