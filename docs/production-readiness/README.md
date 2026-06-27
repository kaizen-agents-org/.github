# Production Readiness Reviews

This directory defines the monthly production-readiness review process for
Kaizen Agents.

The review is separate from the high-frequency organization monitor. The monitor
tracks operational drift and open work; the monthly readiness review decides
whether the system is becoming safer, more reproducible, and closer to sustained
real-world operation.

## Documents

- [Checklist](./checklist.md): review areas and evidence to collect each month.
- [Metrics](./metrics.md): readiness indicators and how to interpret them.
- [Template](./template.md): format for adding a dated entry to
  [Production Readiness Log](../production-readiness-log.md).

## Cadence

Run the readiness review once per month. Each review should:

1. Read the previous readiness log entry.
2. Inspect the current repository, CI, issue, PR, and automation state.
3. Run or cite available verification for `kaizen-loop`, `builder-agent`, and
   `verifier`.
4. Compare the current state with the previous month.
5. Produce a concise dated report and a proposed log entry.
6. Create focused follow-up issues only when they are concrete, duplicate-free,
   and supported by documentation or observed evidence.

## Source-Managed Automation

The runtime Codex automation prompt is sourced from
`../../automations/kaizen-agents-monthly-readiness-review.prompt.md`. Runtime
copies under `$CODEX_HOME/automations` are synced copies, not the source of
truth.

## Safety

The monthly readiness review may inspect broadly and create focused issues. It
must not merge PRs, push branches, edit files, or create broad implementation
work automatically.
