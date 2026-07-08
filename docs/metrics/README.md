# Weekly Kaizen Metrics

This directory stores durable weekly Kaizen Agents metrics snapshots. Each file
is named by ISO week, for example `2026-W28.md`.

## Collection Contract

The weekly readiness review automation owns this directory. Before it writes the
dated readiness report, it should collect `kaizen status --project <slug> --metrics --json`
for each active readiness repository:

- `kaizen-agents-org/.github`
- `kaizen-agents-org/kaizen-loop`
- `kaizen-agents-org/builder-agent`
- `kaizen-agents-org/verifier`

The review PR should add or update exactly one weekly metrics file for the ISO
week under review, then cite that file from
`docs/production-readiness/logs/YYYY-MM-DD.md`.

## Required Denominators

Every weekly snapshot must include denominators for:

- human-edit-free merge rate;
- time-to-merge;
- Issue-to-PR success rate;
- verifier block rate;
- needs-human rate;
- open PR age.

If a value cannot be collected from the available `kaizen status --metrics`
output or GitHub state, record it as unavailable with the denominator that was
actually inspected. Do not estimate missing values.
