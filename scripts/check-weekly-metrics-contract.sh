#!/usr/bin/env bash
set -euo pipefail

metrics_dir="docs/metrics"
metrics_readme="${metrics_dir}/README.md"
baseline="${metrics_dir}/2026-W28.md"
readiness_prompt="automations/kaizen-agents-weekly-readiness-review.prompt.md"
readiness_readme="docs/production-readiness/README.md"
metrics_doc="docs/production-readiness/metrics.md"

for path in \
  "${metrics_readme}" \
  "${baseline}" \
  "${readiness_prompt}" \
  "${readiness_readme}" \
  "${metrics_doc}"
do
  if [ ! -f "${path}" ]; then
    echo "missing weekly metrics contract file: ${path}" >&2
    exit 1
  fi
done

grep -Fq 'docs/metrics/<ISO-week>.md' "${readiness_prompt}"
grep -Fq 'docs/metrics/README.md' "${readiness_prompt}"
grep -Fq 'kaizen status --project' "${readiness_prompt}"
grep -Fq 'kaizen status --project <slug> --metrics --json' "${metrics_readme}"
grep -Fq 'metrics/<ISO-week>.md' "${readiness_readme}"
grep -Fiq 'human-edit-free merge rate' "${metrics_doc}"
grep -Fq 'weekly metrics file' "docs/automation-roles.md"

for required in \
  'Human-edit-free merge rate' \
  'Median time-to-merge' \
  'Issue-to-PR success rate' \
  'Verifier block rate' \
  'Needs-human rate' \
  'Open PR age'
do
  grep -Fq "${required}" "${baseline}"
done

grep -Eq '19 PRs / 73 processed issues' "${baseline}"
grep -Fq 'Ratio of `reviewWindow.prCreated` to `reviewWindow.processed`' "${baseline}"
grep -Eq '1 merged generated PR inspected' "${baseline}"
grep -Eq '20 blocked verifier decisions / 39 inferred verifier decisions' "${baseline}"
grep -Eq '8 open needs-human issues / 34 open `kaizen` issues' "${baseline}"

echo "Weekly metrics contract is present."
