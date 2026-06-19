#!/usr/bin/env bash
set -euo pipefail

daily_workflow=".github/workflows/daily-dogfood-sync.yml"
shared_skill_workflow=".github/workflows/sync-kaizen-shared-skills.yml"
contract_doc="docs/daily-dogfood-sync.md"

for path in "${daily_workflow}" "${shared_skill_workflow}" "${contract_doc}"; do
  if [[ ! -f "${path}" ]]; then
    echo "missing daily dogfood sync contract file: ${path}" >&2
    exit 1
  fi
done

grep -q "schedule:" "${daily_workflow}"
grep -q "workflow_dispatch:" "${daily_workflow}"
grep -q "uses: ./.github/workflows/sync-kaizen-shared-skills.yml" "${daily_workflow}"
grep -q "workflow_call:" "${shared_skill_workflow}"

for skill in gh-link-issue-pr kaizen-bug-router pr-guardian; do
  grep -q "skills/${skill}" "${contract_doc}"
done

echo "Daily dogfood sync contract is present."
