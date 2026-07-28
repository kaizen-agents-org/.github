#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="${repo_root}/scripts/check-automation-prompt-contract.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/automation-prompt-contract.XXXXXX")"
trap 'rm -rf "${fixture}"' EXIT

mkdir -p "${fixture}/automations" "${fixture}/docs"
cp "${repo_root}"/automations/*.prompt.md "${fixture}/automations/"
cp "${repo_root}/docs/automation-roles.md" "${fixture}/docs/"

bash "${checker}" "${fixture}" >/dev/null

assert_rejected() {
  local name="$1"
  local file="$2"
  local old="$3"
  local replacement="$4"
  local original="${repo_root}/${file}"

  sed "s/${old}/${replacement}/" "${original}" >"${fixture}/${file}"
  if bash "${checker}" "${fixture}" >/dev/null 2>&1; then
    echo "mutation was not rejected: ${name}" >&2
    exit 1
  fi
  cp "${original}" "${fixture}/${file}"
}

assert_rejected \
  "scout PR boundary" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "prs=none" \
  "prs=implementation"

assert_rejected \
  "scout issue prefix" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "issues=\\[scout\\]" \
  "issues=[monitor]"

assert_rejected \
  "scout per-repository limit" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "per-repo-limit=2" \
  "per-repo-limit=3"

assert_rejected \
  "monitor issue prefix" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "issues=\\[monitor\\]" \
  "issues=[scout]"

assert_rejected \
  "monitor scout boundary" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "Do not use this prompt as a general repo-improvement scout" \
  "Use this prompt as a general repo-improvement scout"

assert_rejected \
  "weekly review issue boundary" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "issues=none" \
  "issues=[readiness-review]"

assert_rejected \
  "weekly review PR boundary" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "prs=readiness-report" \
  "prs=implementation"

assert_rejected \
  "readiness creator source" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "source=merged-default-branch-readiness-report" \
  "source=open-readiness-pr"

assert_rejected \
  "readiness creator issue prefix" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "issues=\\[readiness-review\\]" \
  "issues=[scout]"

assert_rejected \
  "readiness creator per-repository limit" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "per-repo-limit=3" \
  "per-repo-limit=4"

assert_rejected \
  "role documentation alignment" \
  "docs/automation-roles.md" \
  "automation=scout" \
  "automation=repo-scout"

echo "Automation prompt contract mutations are rejected."
