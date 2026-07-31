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
readiness_checklist="${repo_root}/docs/production-readiness/checklist.md"
readiness_template="${repo_root}/docs/production-readiness/template.md"
automations_readme="${repo_root}/automations/README.md"
org_monitor_doc="${repo_root}/docs/org-monitor.md"
scout_doc="${repo_root}/docs/repo-improvement-scout.md"

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
  "${readiness_checklist}" "${readiness_template}" "${automations_readme}" "${org_monitor_doc}" \
  "${scout_doc}"; do
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
require_text "${scout}" 'Run `gh label list --repo kaizen-agents-org/<repo> --search "kaizen:authorized" --limit 100 --json name --jq '\''any(.name == "kaizen:authorized")'\''` and require an exact `true` result'
require_text "${scout}" 'then do the same for `kaizen:ready` with `--search "kaizen:ready"` and `any(.name == "kaizen:ready")`'
require_text "${scout}" 'If either label cannot be created and verified, do not create the issue'
require_text "${scout}" 'When creating an issue, add the `kaizen`, `kaizen:authorized`, and `kaizen:ready` labels'

require_text "${scout_template}" '<!-- automation-contract: automation=scout; issues=[scout]; prs=none; source=default-branch; roles-doc=docs/automation-roles.md -->'
require_text "${scout_template}" 'Created issue titles must start with `[scout]`.'
require_text "${scout_template}" 'resolve the current default branch with'
require_text "${scout_template}" 'Never assume the'
require_text "${scout_template}" 'runner'\''s current directory is the target repository.'
require_text "${scout_template}" 'use `git -C <targetCheckout>` for every git operation.'
require_text "${scout_template}" 'Every issue or pull-request query and every mutation must pass explicit'
require_text "${scout_template}" '`--repo {{REPOSITORY}}`'
require_text "${scout_template}" 'For a target whose lowercased owner is `kaizen-agents-org`'
require_text "${scout_template}" 'bootstrap it'
require_text "${scout_template}" 'with `gh label create "kaizen:authorized" --repo {{REPOSITORY}}'
require_text "${scout_template}" '`gh label create'
require_text "${scout_template}" '"kaizen:ready" --repo {{REPOSITORY}}'
require_text "${scout_template}" 'For any other owner, never bootstrap execution labels'
require_text "${scout_template}" 'Create no more than `{{CREATION_LIMIT}}` issues in one run.'
require_text "${scout_template}" 'Do not edit files, push branches, merge pull requests, create implementation'
for placeholder in REPOSITORY LABELS WIP_LIMIT CREATION_LIMIT; do
  placeholder_count="$(grep -o "{{${placeholder}}}" "${scout_template}" | wc -l | tr -d ' ')"
  [[ "${placeholder_count}" -ge 1 ]] ||
    fail "${scout_template} must contain {{${placeholder}}}"
done

require_text "${monitor}" 'Do not use this prompt as a general repo-improvement scout'
require_text "${monitor}" 'Fetch `origin main` for `kaizen-agents-org/.github` before reading the fleet registry'
require_text "${monitor}" 'Before any source fetch, verify that the `.github` checkout'\''s `origin` URL'
require_text "${monitor}" 'is exactly `kaizen-agents-org/.github`.'
require_text "${monitor}" 'never load the fleet or source docs from an unverified remote.'
require_text "${monitor}" 'Read `onboarding/fleet.json` from the updated `origin/main` ref, not from the current checkout'
require_text "${monitor}" 'this monitor must never edit it'
require_text "${monitor}" 'Before using any located checkout, read its `origin` URL'
require_text "${monitor}" 'require it to match the active'
require_text "${monitor}" 'entry'\''s complete `repository` identity.'
require_text "${monitor}" 'Never accept a directory based only on'
require_text "${monitor}" 'its `localCheckout` name.'
require_text "${monitor}" 'For every GitHub query or mutation, pass the active registry entry'\''s complete `repository` value unchanged as `--repo <repository>`'
require_text "${monitor}" 'Resolve each active entry'\''s default branch with `gh repo view <repository> --json defaultBranchRef'
require_text "${monitor}" 'do not assume it is `main`'
require_text "${monitor}" 'Fleet membership grants observation scope, not write authorization.'
require_text "${monitor}" 'For the write-authorization comparison only, normalize the owner segment of `<repository>` to lowercase'
require_text "${monitor}" 'only when that normalized owner is exactly `kaizen-agents-org`'
require_text "${monitor}" 'Use concise issue titles prefixed with `[monitor]`.'
require_text "${monitor}" 'Limit automatic issue creation to at most 1 issue per target repository per run.'
require_text "${monitor}" 'Do not merge PRs, push changes, or make broad code changes automatically. The monitor may propose small, deterministic documentation, prompt, or configuration follow-ups that should be handled in a normal ready-for-review PR, but it must not edit repository files, create implementation branches, or open implementation PRs unless the user has explicitly asked for implementation in this thread.'

require_text "${weekly_review}" 'normal ready-for-review PR'
require_text "${weekly_review}" 'Before any source fetch, verify that the `.github` checkout'\''s `origin` URL'
require_text "${weekly_review}" 'repository identity must be exactly `kaizen-agents-org/.github`.'
require_text "${weekly_review}" 'publish a report PR from an unverified remote.'
require_text "${weekly_review}" 'Fetch `origin main` for `kaizen-agents-org/.github` before reading the fleet'
require_text "${weekly_review}" 'updated `origin/main` ref, not from the current checkout'
require_text "${weekly_review}" 'record that commit'
require_text "${weekly_review}" 'as `<sourceSha>`'
require_text "${weekly_review}" 'Read the registry, every source-managed readiness document listed below'
require_text "${weekly_review}" 'from exactly `<sourceSha>` using `git show'
require_text "${weekly_review}" 'Never read'
require_text "${weekly_review}" 'those inputs from the current working tree.'
require_text "${weekly_review}" 'Before using any located checkout, read its `origin` URL'
require_text "${weekly_review}" 'require it to match the scoped'
require_text "${weekly_review}" 'entry'\''s complete `repository` identity.'
require_text "${weekly_review}" 'For every scoped repository, resolve its current default branch with `gh repo'
require_text "${weekly_review}" 'record the corresponding remote head as `<targetSha>`.'
require_text "${weekly_review}" 'run verification only in an isolated detached worktree at'
require_text "${weekly_review}" '`<targetSha>`, never in its current working tree.'
require_text "${weekly_review}" 'GitHub CI/check evidence explicitly tied to `<targetSha>`.'
require_text "${weekly_review}" 'repository-specific verification for every scoped registry entry'
require_text "${weekly_review}" 'never edit it from'
require_text "${weekly_review}" 'Fetch `origin main` again immediately before writing and compare its commit to'
require_text "${weekly_review}" 'restart the full review; never publish outputs derived from mixed source SHAs.'
require_text "${weekly_review}" 'Do not create GitHub issues from this weekly review prompt.'
require_text "${weekly_review}" 'containing only these repository-relative paths:'

require_text "${readiness_creator}" 'weekly readiness report PR has been merged to `main`'
require_text "${readiness_creator}" 'Before any source fetch, verify that the `.github` checkout'\''s `origin` URL'
require_text "${readiness_creator}" 'repository identity must be exactly `kaizen-agents-org/.github`.'
require_text "${readiness_creator}" 'never load the fleet or report from an'
require_text "${readiness_creator}" 'unverified remote.'
require_text "${readiness_creator}" 'Fetch `origin main` for `kaizen-agents-org/.github` before reading the fleet'
require_text "${readiness_creator}" 'Read `onboarding/fleet.json` from the'
require_text "${readiness_creator}" 'updated `origin/main` ref, not from the current checkout.'
require_text "${readiness_creator}" 'Repositories with `weeklyReadiness: true` are the complete issue-creation scope'
require_text "${readiness_creator}" 'pass the active registry entry'\''s complete `repository`'
require_text "${readiness_creator}" 'Before using any located checkout, read its `origin` URL'
require_text "${readiness_creator}" 'require it to match the active'
require_text "${readiness_creator}" 'entry'\''s complete `repository` identity.'
require_text "${readiness_creator}" 'use the configured repository'\''s'
require_text "${readiness_creator}" 'GitHub default-branch content instead.'
require_text "${readiness_creator}" 'For every candidate target, resolve its current default branch with `gh repo'
require_text "${readiness_creator}" 'branch with `git -C <localCheckout> fetch origin <defaultBranch>`'
require_text "${readiness_creator}" 'only from the updated `origin/<defaultBranch>` ref'
require_text "${readiness_creator}" 'create no issue from stale local evidence.'
require_text "${readiness_creator}" 'Fleet membership grants observation scope, not write authorization.'
require_text "${readiness_creator}" 'only when'
require_text "${readiness_creator}" 'write-authorization comparison only, normalize the owner segment of'
require_text "${readiness_creator}" 'only when that normalized'
require_text "${readiness_creator}" 'owner is exactly `kaizen-agents-org`'
require_text "${readiness_creator}" 'PRs across every validated `weeklyReadiness: true` fleet entry, including the'
require_text "${readiness_creator}" 'candidate'\''s target repository'
require_text "${readiness_creator}" 'read that report'
require_text "${readiness_creator}" 'only from `origin/main`'
require_text "${readiness_creator}" '`[readiness-review]`'
require_text "${readiness_creator}" 'Limit issue creation to at most three issues per target repository per run'
require_text "${readiness_creator}" 'Do not edit files, push branches, merge PRs, create implementation branches, or'
require_text "${readiness_creator}" 'open implementation PRs automatically. This automation only creates focused'

require_text "${readiness_readme}" 'for every validated'
require_text "${readiness_readme}" '`weeklyReadiness: true` fleet entry'
require_text "${readiness_readme}" 'for every repository in that same validated'
require_text "${readiness_readme}" 'the readiness log index update, and one weekly metrics'
require_text "${readiness_readme}" 'snapshot under `../metrics/<ISO-week>.md`.'
require_text "${readiness_checklist}" 'confirm local checkout availability for every'
require_text "${readiness_checklist}" '`weeklyReadiness: true` entry'
require_text "${readiness_checklist}" 'For every validated `weeklyReadiness: true` entry, derive its canonical'
require_text "${readiness_checklist}" 'do not assume a Node.js'
require_text "${readiness_checklist}" 'updates exactly one `../metrics/<ISO-week>.md` weekly metrics snapshot.'
require_text "${readiness_template}" 'Populate one row for every validated `weeklyReadiness: true` entry'
require_text "${readiness_template}" '`onboarding/fleet.json`; do not substitute a remembered repository list.'
require_text "${readiness_template}" 'Use each candidate'\''s complete `<owner/repository>` fleet identity as'
require_text "${readiness_template}" 'the target; do not reconstruct it with a fixed organization prefix.'
require_text "${automations_readme}" 'Entries with `monitor: true` in [`onboarding/fleet.json`](../onboarding/fleet.json)'
require_text "${automations_readme}" 'Entries with `weeklyReadiness: true` in [`onboarding/fleet.json`](../onboarding/fleet.json)'
require_text "${org_monitor_doc}" 'every entry with `monitor: true`; there is no separately maintained repository'
require_text "${org_monitor_doc}" 'An entry with `monitor: false` is not an active'
require_text "${scout_doc}" 'There are two supported scout deployment modes.'
require_text "${scout_doc}" 'The fixed organization-wide scout'
require_text "${scout_doc}" 'An opt-in per-repository scout rendered from'
require_text "${scout_doc}" 'scans exactly its explicitly configured `owner/repository`.'
require_text "${scout_doc}" 'That target may be a'
require_text "${scout_doc}" 'newly onboarded organization repository or an external repository'
require_text "${scout_doc}" 'The four fixed targets'
require_text "${scout_doc}" 'cannot also be enabled as per-repository scouts'
require_text "${scout_doc}" 'An external'
require_text "${scout_doc}" 'opt-in scout never bootstraps these labels automatically.'

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
require_text "${contract_doc}" 'Fleet membership is observation scope, not write authorization.'
require_text "${contract_doc}" 'only for repositories whose lowercased owner is exactly `kaizen-agents-org`.'
require_text "${contract_doc}" 'This comparison must not alter the complete repository identity passed to GitHub;'
require_text "${contract_doc}" 'They must not infer missing'
require_text "${contract_doc}" '| `repo-improvement-scout` | At most two issues per target repository per run. |'
require_text "${contract_doc}" '| `org-monitor` | At most one issue per target repository per run. |'
require_text "${contract_doc}" '| `readiness-issue-creator` | At most three issues per target repository per run. |'

echo "Automation prompt contract is present."
