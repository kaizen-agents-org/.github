# Production Readiness Reviews

This directory defines the weekly production-readiness review process for
Kaizen Agents.

The review is separate from the high-frequency organization monitor. The monitor
tracks operational drift and open work; the weekly readiness review decides
whether the system is becoming safer, more reproducible, and closer to sustained
real-world operation.

The readiness loop has three phases:

1. The weekly review produces a dated report and structured issue candidates.
2. The weekly review opens or updates a normal ready-for-review PR containing
   only the dated report and the readiness log index update.
3. After a human merges that report PR, the issue-creator automation consumes
   the latest dated report from `main` and creates focused, duplicate-free
   `kaizen` issues with the `[readiness-review]` title prefix when the
   candidates pass validation.

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
6. Create or update a ready-for-review PR that adds `logs/YYYY-MM-DD.md` and
   updates `../production-readiness-log.md`.
7. Leave issue creation to the issue-creator automation after the report PR is
   merged to `main`.

## Source-Managed Automation

The runtime Codex automation prompts are sourced from:

- `../../automations/kaizen-agents-weekly-readiness-review.prompt.md`
- `../../automations/kaizen-agents-readiness-issue-creator.prompt.md`

Runtime copies under `$CODEX_HOME/automations` are synced copies, not the source
of truth.

## Safety

The weekly readiness review may inspect broadly and propose focused issue
candidates. It may push a branch and open or update a ready-for-review PR only
for the dated report and readiness log index update. The issue-creator
automation may create focused follow-up issues only from an approved dated
report already merged to `main`. Neither automation may merge PRs or create
broad implementation work automatically.
