#!/usr/bin/env bash
set -euo pipefail

# Regression test for the daily dogfood sync contract.
#
# Validates that the deterministic, manifest-driven daily dogfood sync remains
# wired the way docs/daily-dogfood-sync.md describes: a scheduled daily workflow
# delegating to the manifest-driven sync workflow, executable source-issue link
# regression coverage, a complete manifest, present managed source paths, and
# the shared-skill fast path still callable.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

daily_workflow=".github/workflows/daily-dogfood-sync.yml"
dogfood_workflow=".github/workflows/sync-daily-dogfood.yml"
shared_skill_workflow=".github/workflows/sync-kaizen-shared-skills.yml"
sync_script="scripts/sync-daily-dogfood.sh"
pr_link_test="scripts/test-sync-daily-dogfood-pr-link.sh"
monitor_contract_check="scripts/check-org-monitor-contract.sh"
manifest=".github/dogfood-sync/manifest.json"
contract_doc="docs/daily-dogfood-sync.md"
scout_prompt="automations/kaizen-agents-repo-improvement-scout.prompt.md"
monitor_prompt="automations/kaizen-agents-org-monitor.prompt.md"
readiness_issue_prompt="automations/kaizen-agents-readiness-issue-creator.prompt.md"
bug_router_skill="skills/kaizen-bug-router/SKILL.md"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to validate ${manifest}" >&2
  exit 1
fi

for path in \
  "${daily_workflow}" \
  "${dogfood_workflow}" \
  "${shared_skill_workflow}" \
  "${sync_script}" \
  "${pr_link_test}" \
  "${monitor_contract_check}" \
  "${manifest}" \
  "${contract_doc}" \
  "${scout_prompt}" \
  "${monitor_prompt}" \
  "${readiness_issue_prompt}" \
  "${bug_router_skill}"; do
  if [[ ! -f "${path}" ]]; then
    echo "missing daily dogfood sync contract file: ${path}" >&2
    exit 1
  fi
done

# Issue-creating prompts must preserve the closed-loop requirement: generated
# implementation PRs close their source issues through GitHub-recognized links.
for issue_creator in "${scout_prompt}" "${monitor_prompt}" "${readiness_issue_prompt}" "${bug_router_skill}"; do
  grep -q "PR linkage requirement" "${issue_creator}"
  grep -q "Closes #<issue-number>" "${issue_creator}"
  grep -q "kaizen-agents-org/<repo>#<issue-number>" "${issue_creator}"
  grep -q "closingIssuesReferences" "${issue_creator}"
done

# Organization-owned issue creators must preserve the dogfooding execution
# authorization policy as well as the normal Kaizen intake label.
for issue_creator in "${scout_prompt}" "${monitor_prompt}" "${readiness_issue_prompt}"; do
  grep -Fq 'both the `kaizen` and `kaizen:authorized` labels' "${issue_creator}"
  grep -Fq 'at least triage permission' "${issue_creator}"
  grep -Fq 'external operation mode' "${issue_creator}"
done

# Daily workflow: scheduled, manually runnable, delegates to the dogfood sync.
grep -q "schedule:" "${daily_workflow}"
grep -q "workflow_dispatch:" "${daily_workflow}"
grep -q "source_issue:" "${daily_workflow}"
grep -q "uses: ./.github/workflows/sync-daily-dogfood.yml" "${daily_workflow}"
grep -Fq "source_issue: \${{ inputs.source_issue || '' }}" "${daily_workflow}"
if awk '
  /uses: \.\/\.github\/workflows\/sync-daily-dogfood\.yml[[:space:]]*$/ { in_job=1; next }
  in_job && (/^[[:space:]]{2}[A-Za-z0-9_-]+:/ || /^[A-Za-z0-9_-]+:/) { in_job=0 }
  in_job && /^[[:space:]]+require_token:[[:space:]]*true([[:space:]]*#.*)?$/ { found=1 }
  END { exit(found ? 0 : 1) }
' "${daily_workflow}"; then
  echo "scheduled daily dogfood sync must not force KAIZEN_SYNC_TOKEN to be required" >&2
  exit 1
fi

# Dogfood sync workflow: reusable, push-triggered for source contract merges,
# token-aware, deterministic, drift-aware, no auto-merge.
grep -q "workflow_call:" "${dogfood_workflow}"
grep -q "push:" "${dogfood_workflow}"
grep -q "branches:" "${dogfood_workflow}"
grep -q -- "- main" "${dogfood_workflow}"
grep -q '".github/dogfood-sync/\*\*"' "${dogfood_workflow}"
grep -q '".github/ISSUE_TEMPLATE/kaizen.yml"' "${dogfood_workflow}"
grep -q "require_token:" "${dogfood_workflow}"
grep -q "source_issue:" "${dogfood_workflow}"
grep -Fq "KAIZEN_SYNC_TOKEN:" "${dogfood_workflow}"
if ! grep -A2 "KAIZEN_SYNC_TOKEN:" "${dogfood_workflow}" | grep -q "required: false"; then
  echo "daily dogfood sync workflow must allow missing KAIZEN_SYNC_TOKEN in workflow_call" >&2
  exit 1
fi
grep -Fq "GH_TOKEN: \${{ secrets.KAIZEN_SYNC_TOKEN }}" "${dogfood_workflow}"
grep -Fq "github.event_name == 'push' || inputs.require_token == true" "${dogfood_workflow}"
grep -Fq "SOURCE_ISSUE: \${{ inputs.source_issue || '' }}" "${dogfood_workflow}"
grep -q "derive_source_issue_from_push" "${dogfood_workflow}"
grep -q "commits/\${GITHUB_SHA}/pulls" "${dogfood_workflow}"
grep -q "Dogfood sync source issue derived" "${dogfood_workflow}"
grep -Fq 'if [ "${TOKEN_REQUIRED}" = "true" ]; then' "${dogfood_workflow}"
grep -q "Daily dogfood sync blocked" "${dogfood_workflow}"
grep -q "available=false" "${dogfood_workflow}"
grep -q "Daily dogfood sync skipped" "${dogfood_workflow}"
grep -q "Verify managed copies" "${dogfood_workflow}"
grep -q "Assert no target drifts silently" "${dogfood_workflow}"
grep -q "Dogfood drift unresolved" "${dogfood_workflow}"
grep -q "Dogfood sync PR stale" "${dogfood_workflow}"
grep -Fq 'archive "origin/${branch}"' "${dogfood_workflow}"
grep -q "does not exactly match the manifest-managed source contracts" "${dogfood_workflow}"
grep -q "Daily dogfood sync incomplete" "${dogfood_workflow}"
grep -q "Report sync outcome" "${dogfood_workflow}"
grep -Fq "base=\"\$(jq -r '.defaultBranch' \"\${manifest}\")\"" "${dogfood_workflow}"
grep -Fq -- "--base \"\${base}\"" "${dogfood_workflow}"
grep -Fq "pr_head=\"\${branch}\"" "${dogfood_workflow}"
grep -q "gh pr ready" "${dogfood_workflow}"
grep -Fq '<!-- kaizen-pr-guardian:managed -->' "${dogfood_workflow}"
grep -q "ensure_existing_pr_contract" "${dogfood_workflow}"
grep -q "find_same_repo_pr" "${dogfood_workflow}"
grep -q "isCrossRepository,headRepositoryOwner" "${dogfood_workflow}"
grep -Fq '.isCrossRepository == false and .headRepositoryOwner.login == $owner' "${dogfood_workflow}"
grep -q "closingIssuesReferences" "${dogfood_workflow}"
grep -Fq "Closes \${source_issue}" "${dogfood_workflow}"
grep -q "Dogfood sync source issue not linked" "${dogfood_workflow}"
grep -q "Dogfood sync source issue link pending" "${dogfood_workflow}"
grep -q "body text alone is not accepted as proof" "${dogfood_workflow}"
grep -q "assert_pr_links_source_issue" "${dogfood_workflow}"
grep -q "Dogfood sync source issue not supplied" "${dogfood_workflow}"
grep -q "Source issue: not supplied by this automated sync run." "${dogfood_workflow}"
if grep -q -- "--draft" "${dogfood_workflow}"; then
  echo "daily dogfood sync workflow must create ready-for-review PRs, not drafts" >&2
  exit 1
fi
if grep -q "gh pr merge" "${dogfood_workflow}"; then
  echo "daily dogfood sync workflow must not merge PRs automatically" >&2
  exit 1
fi

# Shared-skill fast path stays callable.
grep -q "workflow_call:" "${shared_skill_workflow}"
grep -q "require_token:" "${shared_skill_workflow}"
grep -q "source_issue:" "${shared_skill_workflow}"
grep -q "required: true" "${shared_skill_workflow}"
grep -Fq 'TOKEN_REQUIRED: ${{ inputs.require_token == true }}' "${shared_skill_workflow}"
grep -Fq "SOURCE_ISSUE: \${{ inputs.source_issue || '' }}" "${shared_skill_workflow}"
grep -q "derive_source_issue_from_push" "${shared_skill_workflow}"
grep -q "commits/\${GITHUB_SHA}/pulls" "${shared_skill_workflow}"
grep -Fq 'if [ "${TOKEN_REQUIRED}" = "true" ]; then' "${shared_skill_workflow}"
grep -q "Shared skill sync blocked" "${shared_skill_workflow}"
grep -q "available=false" "${shared_skill_workflow}"
grep -q "Shared skill sync skipped" "${shared_skill_workflow}"
grep -q "Verify synced skill copies" "${shared_skill_workflow}"
grep -q "Assert no target drifts silently" "${shared_skill_workflow}"
grep -q "Shared skill drift unresolved" "${shared_skill_workflow}"
grep -q "Shared skill sync incomplete" "${shared_skill_workflow}"
grep -q "Report sync outcome" "${shared_skill_workflow}"
grep -q -- "--base main" "${shared_skill_workflow}"
grep -Fq '<!-- kaizen-pr-guardian:managed -->' "${shared_skill_workflow}"
grep -q "ensure_existing_pr_contract" "${shared_skill_workflow}"
grep -q "find_same_repo_pr" "${shared_skill_workflow}"
grep -q "isCrossRepository,headRepositoryOwner" "${shared_skill_workflow}"
grep -Fq '.isCrossRepository == false and .headRepositoryOwner.login == $owner' "${shared_skill_workflow}"
grep -q "closingIssuesReferences" "${shared_skill_workflow}"
grep -Fq "Closes \${source_issue}" "${shared_skill_workflow}"
grep -q "Shared skill sync source issue not linked" "${shared_skill_workflow}"
grep -q "assert_pr_links_source_issue" "${shared_skill_workflow}"
grep -q "Shared skill sync source issue not supplied" "${shared_skill_workflow}"
grep -q "Source issue: not supplied by this automated sync run." "${shared_skill_workflow}"

# Manifest is valid JSON and lists every target.
jq -e . "${manifest}" >/dev/null
jq -e '.defaultBranch == "main"' "${manifest}" >/dev/null

for repo in builder-agent verifier kaizen-loop coderabbit renovate-config; do
  if ! jq -e --arg repo "${repo}" '.targets[] | select(.name == $repo)' "${manifest}" >/dev/null; then
    echo "manifest is missing target repository: ${repo}" >&2
    exit 1
  fi
  grep -q "${repo}" "${contract_doc}"
done

# Every managed source path in the manifest must exist for each target.
while IFS= read -r repo; do
  while IFS=$'\t' read -r type source_path _target_path; do
    case "${type}" in
      directory)
        if [[ ! -d "${source_path}" ]]; then
          echo "manifest references missing source directory (${repo}): ${source_path}" >&2
          exit 1
        fi
        ;;
      file)
        if [[ ! -f "${source_path}" ]]; then
          echo "manifest references missing source file (${repo}): ${source_path}" >&2
          exit 1
        fi
        ;;
      *)
        echo "manifest has unsupported managed path type (${repo}): ${type}" >&2
        exit 1
        ;;
    esac
  done < <(
    jq -r --arg repo "${repo}" '
      .managedPaths[]
      | [
          .type,
          (.source // (.sourcePattern | gsub("\\{repo\\}"; $repo))),
          .target
        ]
      | @tsv
    ' "${manifest}"
  )
done < <(jq -r '.targets[].name' "${manifest}")

# Every manifest target must manage exactly one runtime config, and each config
# must stay on the current scheduler.jobs contract.
runtime_config_path_count="$(
  jq -er '
    [
      .managedPaths[]
      | select(.type == "file" and .target == ".kaizen/config.yml")
    ]
    | length
  ' "${manifest}"
)"
if [[ "${runtime_config_path_count}" -ne 1 ]]; then
  echo "manifest must contain exactly one managed .kaizen/config.yml path" >&2
  exit 1
fi

while IFS= read -r repo; do
  target_count="$(
    jq -er --arg repo "${repo}" '
      [
        .targets[]
        | select(.name == $repo)
      ]
      | length
    ' "${manifest}"
  )"
  if [[ "${target_count}" -ne 1 ]]; then
    echo "manifest must contain exactly one target entry for ${repo}" >&2
    exit 1
  fi

  config="$(
    jq -er --arg repo "${repo}" '
      [
        .managedPaths[]
        | select(.type == "file" and .target == ".kaizen/config.yml")
        | (.source // (.sourcePattern | gsub("\\{repo\\}"; $repo)))
      ] as $configs
      | if ($configs | length) == 1 then
          $configs[0]
        else
          empty
        end
    ' "${manifest}"
  )" || {
    echo "${repo} dogfood manifest must manage exactly one .kaizen/config.yml file" >&2
    exit 1
  }

  if ! awk '
    /^scheduler:$/ {
      in_scheduler=1
      next
    }
    in_scheduler && /^[^ ]/ {
      in_scheduler=0
      in_jobs=0
    }
    in_scheduler && /^  jobs:$/ {
      in_jobs=1
      found_jobs=1
      next
    }
    in_jobs && /^  [^ ]/ {
      in_jobs=0
    }
    in_jobs && /^    maintenance:$/ { maintenance=1 }
    in_jobs && /^    maintenance-followup:$/ { maintenance_followup=1 }
    in_jobs && /^    issue-watch:$/ { issue_watch=1 }
    END { exit(found_jobs && maintenance && maintenance_followup && issue_watch ? 0 : 1) }
  ' "${config}"; then
    echo "${repo} dogfood scheduler config must define scheduler.jobs maintenance, maintenance-followup, and issue-watch" >&2
    exit 1
  fi

  if grep -Eq "^[[:space:]]{2}(nightly|afternoon|poll):" "${config}"; then
    echo "${repo} dogfood scheduler config must use scheduler.jobs, not legacy scheduler keys" >&2
    exit 1
  fi
done < <(jq -r '.targets[].name' "${manifest}")

while IFS= read -r repo; do
  if ! awk '
    /^run:$/ {
      in_run=1
      next
    }
    in_run && /^[^ ]/ {
      in_run=0
    }
    in_run && /^  maxOpenPullRequests: 3$/ {
      found=1
    }
    END { exit(found ? 0 : 1) }
  ' ".github/dogfood-sync/targets/${repo}/.kaizen/config.yml"; then
    echo "${repo} dogfood runtime config must keep run.maxOpenPullRequests: 3" >&2
    exit 1
  fi
done < <(jq -r '.targets[].name' "${manifest}")

# Documented managed skills are present.
for skill in gh-link-issue-pr kaizen-bug-router pr-guardian; do
  grep -q "skills/${skill}" "${contract_doc}"
done

"${pr_link_test}"
"${monitor_contract_check}"

echo "Daily dogfood sync contract is present."
