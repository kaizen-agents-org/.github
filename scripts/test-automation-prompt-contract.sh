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
cp "${repo_root}/docs/repo-improvement-scout.md" "${fixture}/docs/"
cp "${repo_root}/docs/production-readiness/README.md" \
  "${repo_root}/docs/production-readiness/checklist.md" \
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
  "Fetch \`origin main\` again immediately before writing." \
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
  'updated `origin\/main` ref, not from the current checkout' \
  'current checkout before fetching'

assert_rejected \
  "monitor verifies canonical organization source" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "Before any source fetch, verify that the \`.github\` checkout's \`origin\` URL" \
  "Trust the current .github origin"

assert_rejected \
  "monitor preserves fleet repository owner" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "pass the active registry entry's complete \`repository\` value unchanged as \`--repo <repository>\`" \
  "reconstruct \`--repo\` from the local checkout name"

assert_rejected \
  "monitor verifies checkout origin identity" \
  "automations/kaizen-agents-org-monitor.prompt.md" \
  "Before using any located checkout, read its \`origin\` URL" \
  "Trust any directory with the configured checkout name"

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
  'updated `origin\/main` ref, not from the current checkout' \
  'current checkout before fetching.'

assert_rejected \
  "weekly review verifies canonical organization source" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "Before any source fetch, verify that the \`.github\` checkout's \`origin\` URL" \
  "Trust the current .github origin"

assert_rejected \
  "weekly review pins readiness source documents" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "from exactly \`<sourceSha>\` using \`git show" \
  "from the current working tree"

assert_rejected \
  "weekly review pins target verification commit" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "record the corresponding remote head as \`<targetSha>\`." \
  "run verification on the current local branch."

assert_rejected \
  "weekly review prevents mixed source scope" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "restart the full review; never publish outputs derived from mixed source SHAs." \
  "continue publishing outputs derived from the earlier scope."

assert_rejected \
  "weekly review verifies checkout origin identity" \
  "automations/kaizen-agents-weekly-readiness-review.prompt.md" \
  "Before using any located checkout, read its \`origin\` URL" \
  "Trust any directory with the configured checkout name"

assert_rejected \
  "readiness checklist fleet verification scope" \
  "docs/production-readiness/checklist.md" \
  "For every validated \`weeklyReadiness: true\` entry, derive its canonical" \
  "Verify only the original runtime repositories"

assert_rejected \
  "readiness checklist three-file output contract" \
  "docs/production-readiness/checklist.md" \
  "updates exactly one \`..\\/metrics\\/<ISO-week>.md\` weekly metrics snapshot." \
  "omits the weekly metrics snapshot."

assert_rejected \
  "readiness issue creator fleet registry source" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  'updated `origin\/main` ref, not from the current checkout.' \
  'current checkout before fetching.'

assert_rejected \
  "readiness issue creator verifies canonical organization source" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "Before any source fetch, verify that the \`.github\` checkout's \`origin\` URL" \
  "Trust the current .github origin"

assert_rejected \
  "scout template refreshes default branch" \
  "onboarding/automations/scout.prompt.template.md" \
  "resolve the current default branch with" \
  "reuse the current local branch"

assert_rejected \
  "scout template binds git operations to target checkout" \
  "onboarding/automations/scout.prompt.template.md" \
  "use \`git -C <targetCheckout>\` for every git operation." \
  "run git operations from the current directory."

assert_rejected \
  "scout template binds GitHub operations to target repository" \
  "onboarding/automations/scout.prompt.template.md" \
  "Every issue or pull-request query and every mutation must pass explicit" \
  "Issue and pull-request operations may infer the repository."

assert_rejected \
  "scout template bootstraps organization execution labels" \
  "onboarding/automations/scout.prompt.template.md" \
  "with \`gh label create \"kaizen:authorized\" --repo {{REPOSITORY}}" \
  "without creating the missing label"

assert_rejected \
  "scout template preserves external authorization boundary" \
  "onboarding/automations/scout.prompt.template.md" \
  "For any other owner, never bootstrap execution labels" \
  "owner, bootstrap execution labels automatically"

assert_rejected \
  "readiness issue creator preserves fleet repository owner" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "pass the active registry entry's complete \`repository\`" \
  "reconstruct the repository from the local checkout"

assert_rejected \
  "readiness issue creator verifies checkout origin identity" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "Before using any located checkout, read its \`origin\` URL" \
  "Trust any directory with the configured checkout name"

assert_rejected \
  "readiness issue creator refreshes target default branch" \
  "automations/kaizen-agents-readiness-issue-creator.prompt.md" \
  "branch with \`git -C <localCheckout> fetch origin <defaultBranch>\`" \
  "trust the checkout's existing remote-tracking branch"

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

assert_rejected \
  "scout documentation opt-in scope" \
  "docs/repo-improvement-scout.md" \
  'scans exactly its explicitly configured `owner\/repository`.' \
  'is limited to the original four repositories.'

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
