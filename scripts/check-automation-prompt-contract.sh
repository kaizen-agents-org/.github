#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
contract_doc="${repo_root}/docs/automation-roles.md"

scout="${repo_root}/automations/kaizen-agents-repo-improvement-scout.prompt.md"
monitor="${repo_root}/automations/kaizen-agents-org-monitor.prompt.md"
weekly_review="${repo_root}/automations/kaizen-agents-weekly-readiness-review.prompt.md"
readiness_creator="${repo_root}/automations/kaizen-agents-readiness-issue-creator.prompt.md"
scout_template="${repo_root}/onboarding/automations/scout.prompt.template.md"
fleet="${repo_root}/onboarding/fleet.json"
fleet_validator="${repo_root}/onboarding/scripts/validate-fleet.mjs"
readiness_readme="${repo_root}/docs/production-readiness/README.md"
readiness_template="${repo_root}/docs/production-readiness/template.md"

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

for file in "${contract_doc}" "${scout}" "${monitor}" "${weekly_review}" "${readiness_creator}" \
  "${scout_template}" "${fleet}" "${fleet_validator}" "${readiness_readme}" \
  "${readiness_template}"; do
  require_file "${file}"
done

node "${fleet_validator}" "${fleet}" >/dev/null

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

require_text "${scout_template}" '<!-- automation-contract: automation=scout; issues=[scout]; prs=none; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_text "${scout_template}" 'Created issue titles must start with `[scout]`.'
require_text "${scout_template}" 'Create no more than `{{CREATION_LIMIT}}` issues in one run.'
require_text "${scout_template}" 'Do not edit files, push branches, merge pull requests, create implementation'
for placeholder in REPOSITORY LABELS WIP_LIMIT CREATION_LIMIT; do
  placeholder_count="$(grep -o "{{${placeholder}}}" "${scout_template}" | wc -l | tr -d ' ')"
  [[ "${placeholder_count}" -ge 1 ]] ||
    fail "${scout_template} must contain {{${placeholder}}}"
done

require_text "${monitor}" 'Do not use this prompt as a general repo-improvement scout'
require_text "${monitor}" 'Read `onboarding/fleet.json` from the `kaizen-agents-org/.github` default branch'
require_text "${monitor}" 'this monitor must never edit it'
require_text "${monitor}" 'For every GitHub query or mutation, pass the active registry entry'\''s complete `repository` value unchanged as `--repo <repository>`'
require_text "${monitor}" 'Use the GitHub default branch, expected to be `origin/main` for these repositories, as the source of truth for documentation-backed findings.'
require_text "${monitor}" 'Use concise issue titles prefixed with `[monitor]`.'
require_text "${monitor}" 'Limit automatic issue creation to at most 1 issue per target repository per run.'
require_text "${monitor}" 'Do not merge PRs, push changes, or make broad code changes automatically. The monitor may propose small, deterministic documentation, prompt, or configuration follow-ups that should be handled in a normal ready-for-review PR, but it must not edit repository files, create implementation branches, or open implementation PRs unless the user has explicitly asked for implementation in this thread.'

require_text "${weekly_review}" 'normal ready-for-review PR'
require_text "${weekly_review}" 'Read `onboarding/fleet.json` from the `kaizen-agents-org/.github` default branch.'
require_text "${weekly_review}" 'never edit it from'
require_text "${weekly_review}" 'Fetch `origin main` before writing. Base the branch on the updated default'
require_text "${weekly_review}" 'Do not create GitHub issues from this weekly review prompt.'
require_text "${weekly_review}" 'containing only these repository-relative paths:'

require_text "${readiness_creator}" 'weekly readiness report PR has been merged to `main`'
require_text "${readiness_creator}" 'Read `onboarding/fleet.json` from the `kaizen-agents-org/.github` default branch.'
require_text "${readiness_creator}" 'Repositories with `weeklyReadiness: true` are the complete issue-creation scope'
require_text "${readiness_creator}" 'pass the active registry entry'\''s complete `repository`'
require_text "${readiness_creator}" 'read that report'
require_text "${readiness_creator}" 'only from `origin/main`'
require_text "${readiness_creator}" '`[readiness-review]`'
require_text "${readiness_creator}" 'Limit issue creation to at most three issues per target repository per run'
require_text "${readiness_creator}" 'Do not edit files, push branches, merge PRs, create implementation branches, or'
require_text "${readiness_creator}" 'open implementation PRs automatically. This automation only creates focused'

require_text "${readiness_readme}" 'for every validated'
require_text "${readiness_readme}" '`weeklyReadiness: true` fleet entry'
require_text "${readiness_readme}" 'for every repository in that same validated'
require_text "${readiness_template}" 'Populate one row for every validated `weeklyReadiness: true` entry'
require_text "${readiness_template}" '`onboarding/fleet.json`; do not substitute a remembered repository list.'

require_text "${contract_doc}" '| Improve | `Kaizen Agents repo improvement scout` | Find concrete repo-local improvement work for the normal Kaizen issue-to-PR loop. | Yes, `[scout]` issues. | No. |'
require_text "${contract_doc}" '| Maintain | `Kaizen Agents org monitor` | Check organization operation, sync, scheduler, CI, source-order, and drift health. | Yes, only focused `[monitor]` issues. | No. |'
require_text "${contract_doc}" '| Readiness-check | `Kaizen Agents weekly readiness review` | Evaluate whether the system is closer to real operation and publish an approval-ready dated report. | No. | Yes, only readiness report PRs in `.github`. |'
require_text "${contract_doc}" '| Readiness-check | `Kaizen Agents readiness issue creator` | Convert an approved readiness report on `main` into implementation backlog. | Yes, `[readiness-review]` issues. | No. |'
require_text "${contract_doc}" '`repo-improvement-scout` owns proactive improvement discovery. It should create small, actionable repo-local issues backed by default-branch docs or code evidence. It must not file organization operation issues, readiness-review issues, or implementation PRs.'
require_text "${contract_doc}" '`org-monitor` owns conservative maintenance. It should report broad state and create issues only for operational drift, sync failures, scheduler/fleet health, CI/check drift, documentation source-order gaps, or responsibility ambiguity that would make the automation system harder to operate. It must not become a general improvement scout.'
require_text "${contract_doc}" '`weekly-readiness-review` owns readiness assessment. It should inspect evidence, write the dated report, update the readiness index, write or update the weekly metrics snapshot, open or update a normal ready-for-review PR containing only the report file, readiness index, and weekly metrics file, and run `pr-guardian` on that report PR until it is merge-ready or blocked. It must not create GitHub issues or implementation PRs.'
require_text "${contract_doc}" '`readiness-issue-creator` owns approved-report issue creation. It runs as a daily post-merge poll and must read the latest dated readiness report from the `.github` default branch after the report PR is merged. It must not create issues from local-only reports, open PR contents, proposed report text, or previous automation memory.'
require_text "${contract_doc}" 'The reviewed repository scope for the organization monitor, weekly readiness'
require_text "${contract_doc}" 'the issue creator consumes the same `weeklyReadiness: true` entries'
require_text "${contract_doc}" 'They must not infer missing'
require_text "${contract_doc}" '| `repo-improvement-scout` | At most two issues per target repository per run. |'
require_text "${contract_doc}" '| `org-monitor` | At most one issue per target repository per run. |'
require_text "${contract_doc}" '| `readiness-issue-creator` | At most three issues per target repository per run. |'

echo "Automation prompt contract is present."
