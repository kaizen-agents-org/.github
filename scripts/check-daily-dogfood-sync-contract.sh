#!/usr/bin/env bash
set -euo pipefail

# Regression test for the daily dogfood sync contract.
#
# Validates that the deterministic, manifest-driven daily dogfood sync remains
# wired the way docs/daily-dogfood-sync.md describes: a scheduled daily workflow
# delegating to the manifest-driven sync workflow, a complete manifest, present
# managed source paths, and the shared-skill fast path still callable.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

daily_workflow=".github/workflows/daily-dogfood-sync.yml"
dogfood_workflow=".github/workflows/sync-daily-dogfood.yml"
shared_skill_workflow=".github/workflows/sync-kaizen-shared-skills.yml"
sync_script="scripts/sync-daily-dogfood.sh"
manifest=".github/dogfood-sync/manifest.json"
contract_doc="docs/daily-dogfood-sync.md"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to validate ${manifest}" >&2
  exit 1
fi

for path in \
  "${daily_workflow}" \
  "${dogfood_workflow}" \
  "${shared_skill_workflow}" \
  "${sync_script}" \
  "${manifest}" \
  "${contract_doc}"; do
  if [[ ! -f "${path}" ]]; then
    echo "missing daily dogfood sync contract file: ${path}" >&2
    exit 1
  fi
done

# Daily workflow: scheduled, manually runnable, delegates to the dogfood sync.
grep -q "schedule:" "${daily_workflow}"
grep -q "workflow_dispatch:" "${daily_workflow}"
grep -q "uses: ./.github/workflows/sync-daily-dogfood.yml" "${daily_workflow}"

# Dogfood sync workflow: reusable, token-gated, deterministic, drift-aware, no auto-merge.
grep -q "workflow_call:" "${dogfood_workflow}"
grep -q "KAIZEN_SYNC_TOKEN" "${dogfood_workflow}"
grep -q "Daily dogfood sync blocked" "${dogfood_workflow}"
grep -q "Verify managed copies" "${dogfood_workflow}"
grep -q "Assert no target drifts silently" "${dogfood_workflow}"
grep -q "Dogfood drift unresolved" "${dogfood_workflow}"
grep -q "Daily dogfood sync incomplete" "${dogfood_workflow}"
grep -q "Report sync outcome" "${dogfood_workflow}"
grep -q -- "--base" "${dogfood_workflow}"
grep -q 'pr_head="${owner}:${branch}"' "${dogfood_workflow}"
grep -q "gh pr ready" "${dogfood_workflow}"
if grep -q -- "--draft" "${dogfood_workflow}"; then
  echo "daily dogfood sync workflow must create ready-for-review PRs, not drafts" >&2
  exit 1
fi

# Shared-skill fast path stays callable.
grep -q "workflow_call:" "${shared_skill_workflow}"
grep -q "required: true" "${shared_skill_workflow}"

# Manifest is valid JSON and lists every target.
jq -e . "${manifest}" >/dev/null

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

# Documented managed skills are present.
for skill in gh-link-issue-pr kaizen-bug-router pr-guardian; do
  grep -q "skills/${skill}" "${contract_doc}"
done

echo "Daily dogfood sync contract is present."
