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
3. After a human merges that report PR, the issue-creator automation's daily
   post-merge poll consumes the latest dated report from `main` and creates
   focused, duplicate-free `kaizen` issues with the `[readiness-review]` title
   prefix when the candidates pass validation.

## Documents

- [Checklist](./checklist.md): review areas and evidence to collect each week.
- [Metrics](./metrics.md): readiness indicators and how to interpret them.
- [`../metrics/`](../metrics/): durable weekly `kaizen status --metrics`
  snapshots named by ISO week.
- [Template](./template.md): format for adding a dated entry to
  [Production Readiness Log](../production-readiness-log.md).
- [`logs/`](./logs/): archived dated readiness reviews, named
  `YYYY-MM-DD.md`.

## Cadence

Run the readiness review once per week. Each review should:

1. Read the previous readiness log entry.
2. Read the latest weekly metrics snapshot under `../metrics/` when present.
3. Inspect the current repository, CI, issue, PR, and automation state.
4. Run or cite available verification for `kaizen-loop`, `builder-agent`, and
   `verifier`.
5. Collect or update `../metrics/<ISO-week>.md` with denominator-bearing
   `kaizen status --metrics` results for `.github`, `kaizen-loop`,
   `builder-agent`, and `verifier`.
6. Compare the current state with the previous week.
7. Produce a concise dated report and structured issue candidates that cite the
   weekly metrics snapshot.
8. Create or update a ready-for-review PR that adds `logs/YYYY-MM-DD.md`,
   updates `../production-readiness-log.md`, and adds or updates exactly one
   `../metrics/<ISO-week>.md` file.
9. Run `pr-guardian` on that report PR until it is merge-ready or blocked.
10. Leave issue creation to the issue-creator automation after the report PR is
   merged to `main`; the issue creator checks daily so it does not depend on a
   one-hour merge window.

## Source-Managed Automation

The runtime Codex automation prompts are sourced from:

- `../../automations/kaizen-agents-weekly-readiness-review.prompt.md`
- `../../automations/kaizen-agents-readiness-issue-creator.prompt.md`

Runtime copies under `$CODEX_HOME/automations` are synced copies, not the source
of truth.

## Safety

The weekly readiness review may inspect broadly and propose focused issue
candidates. It may push a branch and open or update a ready-for-review PR only
for the dated report, readiness log index update, and one weekly metrics file,
then run `pr-guardian` for that report PR. The issue-creator automation may
create focused follow-up issues only from an approved dated report already
merged to `main`. Neither automation may merge PRs or create broad
implementation work automatically.
