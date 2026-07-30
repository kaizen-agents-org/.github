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

assert_append_rejected() {
  local name="$1"
  local file="$2"
  local text="$3"
  local original="${repo_root}/${file}"

  printf '\n  %s\n' "${text}" >> "${fixture}/${file}"
  if bash "${checker}" "${fixture}" >/dev/null 2>&1; then
    echo "mutation was not rejected: ${name}" >&2
    exit 1
  fi
  cp "${original}" "${fixture}/${file}"
}

assert_rejected \
  "scout PR boundary" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "Do not edit files, push branches, merge PRs, create implementation branches, open implementation PRs, or make broad code changes automatically." \
  "Edit files, push branches, merge PRs, create implementation branches, open implementation PRs, or make broad code changes automatically."

assert_rejected \
  "scout issue prefix" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "issues=\\[scout\\]" \
  "issues=[monitor]"

assert_rejected \
  "scout source of truth" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "Use the GitHub default branch, expected to be \`origin\\/main\` for these repositories, as the source of truth." \
  "Use the current local feature branch for these repositories as the source of truth."

assert_rejected \
  "scout per-repository limit" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "per-repo-limit=2" \
  "per-repo-limit=3"

assert_rejected \
  "scout queue-selection label verification" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  'then do the same for `kaizen:ready` with `--search \"kaizen:ready\"` and `any(.name == \"kaizen:ready\")`' \
  'then continue without verifying the queue-selection label'

assert_rejected \
  "scout authorization-label exact-name query" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "--limit 100 --json name --jq 'any(.name == \"kaizen:authorized\")'" \
  "--limit 100"

assert_rejected \
  "scout queue-selection fail-closed behavior" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "If either label cannot be created and verified, do not create the issue" \
  "If either label cannot be created and verified, create the issue without it"

assert_rejected \
  "scout queue-selection label application" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  'When creating an issue, add the `kaizen`, `kaizen:authorized`, and `kaizen:ready` labels' \
  'When creating an issue, add the `kaizen` and `kaizen:authorized` labels'

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
  "monitor source of truth" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "Use the GitHub default branch, expected to be \`origin\\/main\` for these repositories, as the source of truth for documentation-backed findings." \
  "Use the current local feature branch for these repositories as the source of truth for documentation-backed findings."

assert_rejected \
  "monitor PR boundary" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "Do not merge PRs, push changes, or make broad code changes automatically." \
  "Merge PRs, push changes, and make broad code changes automatically."

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
  "weekly review source of truth" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "Fetch \`origin main\` before writing." \
  "Use the current local feature branch before writing."

assert_rejected \
  "readiness creator source" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "source=merged-default-branch-readiness-report" \
  "source=open-readiness-pr"

assert_rejected \
  "readiness creator report source prose" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "only from \`origin\\/main\`." \
  "only from the current local feature branch."

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
  "readiness creator PR boundary" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "Do not edit files, push branches, merge PRs, create implementation branches, or" \
  "Edit files, push branches, merge PRs, create implementation branches, or"

assert_rejected \
  "role documentation marker alignment" \
  "docs/automation-roles.md" \
  "automation=scout" \
  "automation=repo-scout"

assert_rejected \
  "role documentation scout PR boundary" \
  "docs/automation-roles.md" \
  "| Improve | \`Kaizen Agents repo improvement scout\` | Find concrete repo-local improvement work for the normal Kaizen issue-to-PR loop. | Yes, \`\[scout\]\` issues. | No. |" \
  "| Improve | \`Kaizen Agents repo improvement scout\` | Find concrete repo-local improvement work for the normal Kaizen issue-to-PR loop. | Yes, \`[scout]\` issues. | Yes. |"

assert_rejected \
  "role documentation monitor boundary" \
  "docs/automation-roles.md" \
  "It must not become a general improvement scout." \
  "It must become a general improvement scout."

assert_rejected \
  "role documentation scout limit" \
  "docs/automation-roles.md" \
  "At most two issues per target repository per run." \
  "At most twenty issues per target repository per run."

assert_append_rejected \
  "indented duplicate prompt marker" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "<!-- automation-contract: automation=scout; issues=[monitor]; prs=implementation; per-repo-limit=9; source=default-branch; roles-doc=docs/automation-roles.md -->"

assert_append_rejected \
  "indented duplicate documentation marker" \
  "docs/automation-roles.md" \
  "<!-- automation-contract: automation=scout; issues=[monitor]; prs=implementation; per-repo-limit=9; source=default-branch; roles-doc=docs/automation-roles.md -->"

echo "Automation prompt contract mutations are rejected."
