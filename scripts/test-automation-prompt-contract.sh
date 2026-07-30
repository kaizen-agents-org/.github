#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="${repo_root}/scripts/check-automation-prompt-contract.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/automation-prompt-contract.XXXXXX")"
trap 'rm -rf "${fixture}"' EXIT

mkdir -p "${fixture}/automations" "${fixture}/docs/production-readiness" \
  "${fixture}/onboarding/automations" "${fixture}/onboarding/scripts"
cp "${repo_root}"/automations/*.prompt.md "${fixture}/automations/"
cp "${repo_root}/automations/README.md" "${fixture}/automations/"
cp "${repo_root}/docs/automation-roles.md" "${fixture}/docs/"
cp "${repo_root}/docs/org-monitor.md" "${fixture}/docs/"
cp "${repo_root}/docs/production-readiness/README.md" \
  "${repo_root}/docs/production-readiness/template.md" \
  "${fixture}/docs/production-readiness/"
cp "${repo_root}/onboarding/fleet.json" "${fixture}/onboarding/"
cp "${repo_root}/onboarding/automations/scout.prompt.template.md" \
  "${fixture}/onboarding/automations/"
cp "${repo_root}/onboarding/scripts/validate-fleet.mjs" \
  "${fixture}/onboarding/scripts/"

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
  "monitor default branch resolution" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "do not assume it is \`main\`" \
  "assume it is \`main\`"

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

assert_rejected \
  "monitor fleet registry source" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  'Read `onboarding\/fleet.json` from the `kaizen-agents-org\/.github` default branch' \
  'Use an inferred repository list'

assert_rejected \
  "monitor preserves fleet repository owner" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "pass the active registry entry's complete \`repository\` value unchanged as \`--repo <repository>\`" \
  "reconstruct \`--repo\` from the local checkout name"

assert_rejected \
  "monitor external write boundary" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "Fleet membership grants observation scope, not write authorization." \
  "Fleet membership grants write authorization."

assert_rejected \
  "monitor normalizes owner for write boundary" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "normalize the owner segment of \`<repository>\` to lowercase" \
  "compare the owner segment of \`<repository>\` exactly as written"

assert_rejected \
  "weekly fleet registry source" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  'Read `onboarding\/fleet.json` from the `kaizen-agents-org\/.github` default branch.' \
  'Use a remembered repository list.'

assert_rejected \
  "readiness issue creator fleet registry source" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  'Read `onboarding\/fleet.json` from the `kaizen-agents-org\/.github` default branch.' \
  'Use a remembered repository list.'

assert_rejected \
  "readiness issue creator preserves fleet repository owner" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "pass the active registry entry's complete \`repository\`" \
  "reconstruct the repository from the local checkout"

assert_rejected \
  "readiness issue creator external write boundary" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "Fleet membership grants observation scope, not write authorization." \
  "Fleet membership grants write authorization."

assert_rejected \
  "readiness issue creator normalizes owner for write boundary" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "normalize the owner segment of" \
  "compare the owner segment of"

assert_rejected \
  "readiness issue creator duplicate-search fleet scope" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "every validated \`weeklyReadiness: true\` fleet entry" \
  "only monitored fleet entries"

assert_rejected \
  "readiness cadence fleet denominator" \
  "docs/production-readiness/README.md" \
  "for every repository in that same validated" \
  "for only the original four repositories in the"

assert_rejected \
  "readiness template fleet scope" \
  "docs/production-readiness/template.md" \
  'Populate one row for every validated `weeklyReadiness: true` entry' \
  'Populate rows for the original four repositories'

assert_rejected \
  "readiness candidate full repository identity" \
  "docs/production-readiness/template.md" \
  "Use each candidate's complete \`<owner\\/repository>\` fleet identity as" \
  "Use each candidate's repository name only as"

assert_rejected \
  "runtime monitor fleet scope" \
  "automations/README.md" \
  'Entries with `monitor: true` in \[`onboarding\/fleet.json`\](..\/onboarding\/fleet.json)' \
  '`.github`, `builder-agent`, `kaizen-loop`, `verifier`'

assert_rejected \
  "monitor documentation fleet scope" \
  "docs/org-monitor.md" \
  'every entry with `monitor: true`; there is no separately maintained repository' \
  'only the original four repositories are monitored'

cp "${repo_root}/onboarding/fleet.json" "${fixture}/onboarding/fleet.json"
node -e \
  'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.repositories.push({...v.repositories[0]});fs.writeFileSync(p,JSON.stringify(v))' \
  "${fixture}/onboarding/fleet.json"
if bash "${checker}" "${fixture}" >/dev/null 2>&1; then
  echo "mutation was not rejected: duplicate fleet repository" >&2
  exit 1
fi
cp "${repo_root}/onboarding/fleet.json" "${fixture}/onboarding/fleet.json"

assert_append_rejected \
  "indented duplicate prompt marker" \
  "automations/kaizen-agents-repo-improvement-scout.prompt.md" \
  "<!-- automation-contract: automation=scout; issues=[monitor]; prs=implementation; per-repo-limit=9; source=default-branch; roles-doc=docs/automation-roles.md -->"

assert_append_rejected \
  "indented duplicate documentation marker" \
  "docs/automation-roles.md" \
  "<!-- automation-contract: automation=scout; issues=[monitor]; prs=implementation; per-repo-limit=9; source=default-branch; roles-doc=docs/automation-roles.md -->"

echo "Automation prompt contract mutations are rejected."
bash "${repo_root}/onboarding/scripts/test-scout-fleet-contract.sh"
