# Production Readiness Reviews

This directory defines the weekly production-readiness review process for
Kaizen Agents.

The review is separate from the high-frequency organization monitor. The monitor
tracks operational drift and open work; the weekly readiness review decides
whether the system is becoming safer, more reproducible, and closer to sustained
real-world operation.

The readiness loop has two phases:

1. The weekly review produces a dated report and structured issue candidates.
2. The issue-creator automation consumes the latest dated report and creates
   focused, duplicate-free `kaizen` issues with the `[readiness-review]` title
   prefix when the candidates pass validation.

## Documents

- [Checklist](./checklist.md): review areas and evidence to collect each week.
- [Metrics](./metrics.md): readiness indicators and how to interpret them.
- [Template](./template.md): format for adding a dated entry to
  [Production Readiness Log](../production-readiness-log.md).
- [`logs/`](./logs/): archived dated readiness reviews, named
  `YYYY-MM-DD.md`.

## Cadence

Run the readiness review once per week. Each review should:

1. Read the previous readiness log entry.
2. Inspect the current repository, CI, issue, PR, and automation state.
3. Run or cite available verification for `kaizen-loop`, `builder-agent`, and
   `verifier`.
4. Compare the current state with the previous week.
5. Produce a concise dated report and structured issue candidates.
6. Propose a `logs/YYYY-MM-DD.md` file and an index update for
   `../production-readiness-log.md`.
7. Leave issue creation to the issue-creator automation after the report exists
   as an approved dated log.

## Source-Managed Automation

The runtime Codex automation prompts are sourced from:

- `../../automations/kaizen-agents-weekly-readiness-review.prompt.md`
- `../../automations/kaizen-agents-readiness-issue-creator.prompt.md`

Runtime copies under `$CODEX_HOME/automations` are synced copies, not the source
of truth.

## Safety

The weekly readiness review may inspect broadly and propose focused issue
candidates. The issue-creator automation may create focused follow-up issues
from an approved dated report. Neither automation may merge PRs, push branches,
edit files, or create broad implementation work automatically.
