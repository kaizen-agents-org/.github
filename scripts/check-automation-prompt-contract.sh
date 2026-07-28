#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
roles_doc="${repo_root}/docs/automation-roles.md"

scout="${repo_root}/automations/kaizen-agents-repo-improvement-scout.prompt.md"
monitor="${repo_root}/automations/kaizen-agents-org-monitor.prompt.md"
weekly_review="${repo_root}/automations/kaizen-agents-weekly-readiness-review.prompt.md"
readiness_creator="${repo_root}/automations/kaizen-agents-readiness-issue-creator.prompt.md"

fail() {
  echo "automation prompt contract check failed: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "${text}" "${file}" ||
    fail "${file} is missing required contract text: ${text}"
}

require_contract_marker() {
  local prompt="$1"
  local marker="$2"
  local prompt_count
  local doc_count

  prompt_count="$(grep -Fxc -- "${marker}" "${prompt}" || true)"
  doc_count="$(grep -Fxc -- "${marker}" "${roles_doc}" || true)"
  [[ "${prompt_count}" == "1" ]] ||
    fail "${prompt} must contain exactly one matching contract marker"
  [[ "${doc_count}" == "1" ]] ||
    fail "${roles_doc} must contain exactly one matching marker for ${prompt}"
}

for file in "${roles_doc}" "${scout}" "${monitor}" "${weekly_review}" "${readiness_creator}"; do
  require_file "${file}"
done

for prompt in "${scout}" "${monitor}" "${weekly_review}" "${readiness_creator}"; do
  marker_count="$(grep -c '^<!-- automation-contract:' "${prompt}" || true)"
  [[ "${marker_count}" == "1" ]] ||
    fail "${prompt} must contain exactly one automation contract marker"
done
doc_marker_count="$(grep -c '^<!-- automation-contract:' "${roles_doc}" || true)"
[[ "${doc_marker_count}" == "4" ]] ||
  fail "${roles_doc} must contain exactly four automation contract markers"

require_text "${scout}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-repo-improvement-scout.prompt.md`.'
require_text "${monitor}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-org-monitor.prompt.md`.'
require_text "${weekly_review}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-weekly-readiness-review.prompt.md`.'
require_text "${readiness_creator}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-readiness-issue-creator.prompt.md`.'

require_contract_marker "${scout}" '<!-- automation-contract: role=scout; issues=[scout]; prs=none; per-repo-limit=2; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_contract_marker "${monitor}" '<!-- automation-contract: role=monitor; issues=[monitor]; prs=none; per-repo-limit=1; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_contract_marker "${weekly_review}" '<!-- automation-contract: role=weekly-readiness-review; issues=none; prs=readiness-report; per-repo-limit=0; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_contract_marker "${readiness_creator}" '<!-- automation-contract: role=readiness-issue-creator; issues=[readiness-review]; prs=none; per-repo-limit=3; source=merged-default-branch-readiness-report; roles-doc=docs/automation-roles.md -->'

require_text "${scout}" 'prefix the title with `[scout]`'
require_text "${scout}" 'open implementation PRs'
require_text "${scout}" 'Limit automatic issue creation to at most two issues per target repository per run.'

require_text "${monitor}" 'Do not use this prompt as a general repo-improvement scout'
require_text "${monitor}" 'Use concise issue titles prefixed with `[monitor]`.'
require_text "${monitor}" 'Limit automatic issue creation to at most 1 issue per target repository per run.'

require_text "${weekly_review}" 'normal ready-for-review PR'
require_text "${weekly_review}" 'Do not create GitHub issues from this weekly review prompt.'
require_text "${weekly_review}" 'containing only these repository-relative paths:'

require_text "${readiness_creator}" 'weekly readiness report PR has been merged to `main`'
require_text "${readiness_creator}" 'read that report'
require_text "${readiness_creator}" 'only from `origin/main`'
require_text "${readiness_creator}" '`[readiness-review]`'
require_text "${readiness_creator}" 'Limit issue creation to at most three issues per target repository per run'
require_text "${readiness_creator}" 'open implementation PRs automatically'

echo "Automation prompt contract is present."
