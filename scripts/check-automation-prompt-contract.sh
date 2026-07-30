#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
contract_doc="${repo_root}/docs/automation-roles.md"

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
  doc_count="$(grep -Fxc -- "${marker}" "${contract_doc}" || true)"
  [[ "${prompt_count}" == "1" ]] ||
    fail "${prompt} must contain exactly one matching contract marker"
  [[ "${doc_count}" == "1" ]] ||
    fail "${contract_doc} must contain exactly one matching marker for ${prompt}"
}

for file in "${contract_doc}" "${scout}" "${monitor}" "${weekly_review}" "${readiness_creator}"; do
  require_file "${file}"
done

for prompt in "${scout}" "${monitor}" "${weekly_review}" "${readiness_creator}"; do
  marker_count="$(grep -c '^[[:space:]]*<!-- automation-contract:' "${prompt}" || true)"
  [[ "${marker_count}" == "1" ]] ||
    fail "${prompt} must contain exactly one automation contract marker"
done
doc_marker_count="$(grep -c '^[[:space:]]*<!-- automation-contract:' "${contract_doc}" || true)"
[[ "${doc_marker_count}" == "4" ]] ||
  fail "${contract_doc} must contain exactly four automation contract markers"

require_text "${scout}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-repo-improvement-scout.prompt.md`.'
require_text "${monitor}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-org-monitor.prompt.md`.'
require_text "${weekly_review}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-weekly-readiness-review.prompt.md`.'
require_text "${readiness_creator}" 'Managed source: `kaizen-agents-org/.github/automations/kaizen-agents-readiness-issue-creator.prompt.md`.'

require_contract_marker "${scout}" '<!-- automation-contract: automation=scout; issues=[scout]; prs=none; per-repo-limit=2; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_contract_marker "${monitor}" '<!-- automation-contract: automation=monitor; issues=[monitor]; prs=none; per-repo-limit=1; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_contract_marker "${weekly_review}" '<!-- automation-contract: automation=weekly-readiness-review; issues=none; prs=readiness-report; per-repo-limit=0; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_contract_marker "${readiness_creator}" '<!-- automation-contract: automation=readiness-issue-creator; issues=[readiness-review]; prs=none; per-repo-limit=3; source=merged-default-branch-readiness-report; roles-doc=docs/automation-roles.md -->'

require_text "${scout}" 'prefix the title with `[scout]`'
require_text "${scout}" 'Use the GitHub default branch, expected to be `origin/main` for these repositories, as the source of truth.'
require_text "${scout}" 'Do not edit files, push branches, merge PRs, create implementation branches, open implementation PRs, or make broad code changes automatically.'
require_text "${scout}" 'Limit automatic issue creation to at most two issues per target repository per run.'
require_text "${scout}" 'Run `gh label list --repo kaizen-agents-org/<repo> --search "kaizen:authorized" --limit 100 --json name --jq '\''any(.name == "kaizen:authorized")'\''` and require an exact `true` result'
require_text "${scout}" 'then do the same for `kaizen:ready` with `--search "kaizen:ready"` and `any(.name == "kaizen:ready")`'
require_text "${scout}" 'If either label cannot be created and verified, do not create the issue'
require_text "${scout}" 'When creating an issue, add the `kaizen`, `kaizen:authorized`, and `kaizen:ready` labels'

require_text "${monitor}" 'Do not use this prompt as a general repo-improvement scout'
require_text "${monitor}" 'Use the GitHub default branch, expected to be `origin/main` for these repositories, as the source of truth for documentation-backed findings.'
require_text "${monitor}" 'Use concise issue titles prefixed with `[monitor]`.'
require_text "${monitor}" 'Limit automatic issue creation to at most 1 issue per target repository per run.'
require_text "${monitor}" 'Do not merge PRs, push changes, or make broad code changes automatically. The monitor may propose small, deterministic documentation, prompt, or configuration follow-ups that should be handled in a normal ready-for-review PR, but it must not edit repository files, create implementation branches, or open implementation PRs unless the user has explicitly asked for implementation in this thread.'

require_text "${weekly_review}" 'normal ready-for-review PR'
require_text "${weekly_review}" 'Fetch `origin main` before writing. Base the branch on the updated default'
require_text "${weekly_review}" 'Do not create GitHub issues from this weekly review prompt.'
require_text "${weekly_review}" 'containing only these repository-relative paths:'

require_text "${readiness_creator}" 'weekly readiness report PR has been merged to `main`'
require_text "${readiness_creator}" 'read that report'
require_text "${readiness_creator}" 'only from `origin/main`'
require_text "${readiness_creator}" '`[readiness-review]`'
require_text "${readiness_creator}" 'Limit issue creation to at most three issues per target repository per run'
require_text "${readiness_creator}" 'Do not edit files, push branches, merge PRs, create implementation branches, or'
require_text "${readiness_creator}" 'open implementation PRs automatically. This automation only creates focused'

require_text "${contract_doc}" '| Improve | `Kaizen Agents repo improvement scout` | Find concrete repo-local improvement work for the normal Kaizen issue-to-PR loop. | Yes, `[scout]` issues. | No. |'
require_text "${contract_doc}" '| Maintain | `Kaizen Agents org monitor` | Check organization operation, sync, scheduler, CI, source-order, and drift health. | Yes, only focused `[monitor]` issues. | No. |'
require_text "${contract_doc}" '| Readiness-check | `Kaizen Agents weekly readiness review` | Evaluate whether the system is closer to real operation and publish an approval-ready dated report. | No. | Yes, only readiness report PRs in `.github`. |'
require_text "${contract_doc}" '| Readiness-check | `Kaizen Agents readiness issue creator` | Convert an approved readiness report on `main` into implementation backlog. | Yes, `[readiness-review]` issues. | No. |'
require_text "${contract_doc}" '`repo-improvement-scout` owns proactive improvement discovery. It should create small, actionable repo-local issues backed by default-branch docs or code evidence. It must not file organization operation issues, readiness-review issues, or implementation PRs.'
require_text "${contract_doc}" '`org-monitor` owns conservative maintenance. It should report broad state and create issues only for operational drift, sync failures, scheduler/fleet health, CI/check drift, documentation source-order gaps, or responsibility ambiguity that would make the automation system harder to operate. It must not become a general improvement scout.'
require_text "${contract_doc}" '`weekly-readiness-review` owns readiness assessment. It should inspect evidence, write the dated report, update the readiness index, write or update the weekly metrics snapshot, open or update a normal ready-for-review PR containing only the report file, readiness index, and weekly metrics file, and run `pr-guardian` on that report PR until it is merge-ready or blocked. It must not create GitHub issues or implementation PRs.'
require_text "${contract_doc}" '`readiness-issue-creator` owns approved-report issue creation. It runs as a daily post-merge poll and must read the latest dated readiness report from the `.github` default branch after the report PR is merged. It must not create issues from local-only reports, open PR contents, proposed report text, or previous automation memory.'
require_text "${contract_doc}" '| `repo-improvement-scout` | At most two issues per target repository per run. |'
require_text "${contract_doc}" '| `org-monitor` | At most one issue per target repository per run. |'
require_text "${contract_doc}" '| `readiness-issue-creator` | At most three issues per target repository per run. |'

echo "Automation prompt contract is present."
