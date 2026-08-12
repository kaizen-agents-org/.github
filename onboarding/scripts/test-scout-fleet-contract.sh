#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
enable="${repo_root}/onboarding/scripts/enable-scout.sh"
validator="${repo_root}/onboarding/scripts/validate-fleet.mjs"
workflow="${repo_root}/onboarding/automations/scout.workflow.yml"
fixture_base="${KAIZEN_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
fixture="$(mktemp -d "${fixture_base%/}/scout-fleet-contract.XXXXXX")"
trap 'rm -rf "${fixture}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

grep -Fq 'organization monitor, weekly readiness review, and downstream readiness issue' \
  "${repo_root}/onboarding/README.md" \
  || fail "onboarding docs omit the downstream readiness issue creator"
grep -Fq '`weeklyReadiness: true` adds the repository to the read-only weekly review' \
  "${repo_root}/onboarding/README.md" \
  || fail "onboarding docs omit the weeklyReadiness consumer effects"
grep -Fq 'fleet membership is not write authorization' \
  "${repo_root}/onboarding/README.md" \
  || fail "onboarding docs treat fleet scope as write authorization"

grep -Fq 'persist-credentials: false' "${workflow}" \
  || fail "scout checkout persists a mutation-capable job token"
grep -Fq 'issues: write' "${workflow}" \
  || fail "normal scout lacks issue creation permission"
grep -Fq 'scout-dry-run:' "${workflow}" \
  || fail "scout does not isolate dry runs in a read-only job"
[[ "$(grep -Ec '^  issues: read$' "${workflow}")" -eq 1 ]] \
  || fail "dry-run default must grant exactly read-only issue access"
grep -Fq 'scout-target:' "${repo_root}/onboarding/automations/scout.prompt.template.md" \
  || fail "rendered scout prompt lacks a machine-readable target"
grep -Fq 'rendered_target="$(sed -n' "${workflow}" \
  || fail "scout runner does not parse the declared target"
grep -Fq '@anthropic-ai/claude-code@2.1.228' "${workflow}" \
  || fail "scout runner does not pin Claude Code"
if grep -Fq '@anthropic-ai/claude-code@latest' "${workflow}"; then
  fail "scout runner installs an unreviewed latest Claude Code release"
fi
grep -Fq -- '--permission-mode dontAsk' "${workflow}" \
  || fail "scout does not deny unlisted tools"
grep -Fq -- '--disallowedTools "Edit,Write"' "${workflow}" \
  || fail "scout does not explicitly disallow file mutation tools"
if grep -Fq -- '--permission-mode acceptEdits' "${workflow}"; then
  fail "scout automatically accepts file edits"
fi
grep -Fq 'git update-ref "refs/remotes/origin/${default_branch}" HEAD' "${workflow}" \
  || fail "scout runner does not prepare an authoritative default-branch ref"
grep -Fq 'Bash(git -C ${GITHUB_WORKSPACE} log:*)' "${workflow}" \
  || fail "scout git reads do not name the verified checkout"
if grep -Eq 'Bash\(git (log|show|diff):\*\)' "${workflow}"; then
  fail "scout allows git reads that omit the verified checkout"
fi
if grep -Fq 'Bash(gh:*)' "${workflow}"; then
  fail "scout grants unrestricted gh access"
fi
grep -Fq 'Bash(gh issue create:*)' "${workflow}" \
  || fail "scout cannot create eligible findings"
grep -Fq 'Bash(gh label create:*)' "${workflow}" \
  || fail "organization scout cannot bootstrap required execution labels"
if sed -n '/if \[ "${KAIZEN_SCOUT_DRY_RUN}" = "true" \]; then/,/else/p' "${workflow}" \
  | grep -Eq 'Bash\(gh (issue|label) create:\*\)'; then
  fail "dry-run scout receives a mutation tool"
fi

prompt_targets_repository() {
  local prompt_file="$1"
  local repository="$2"
  local rendered_target
  rendered_target="$(sed -n 's/^<!-- scout-target: \([^[:space:]]*\) -->$/\1/p' "$prompt_file")"
  [[ "$(printf '%s' "$rendered_target" | tr '[:upper:]' '[:lower:]')" == \
     "$(printf '%s' "$repository" | tr '[:upper:]' '[:lower:]')" ]]
}

printf '%s\n' \
  '<!-- scout-target: other/repository -->' \
  'Scout owner/repository only as an incidental mention.' \
  > "${fixture}/wrong-target-prompt.md"
if prompt_targets_repository "${fixture}/wrong-target-prompt.md" owner/repository; then
  fail "incidental repository mention bypassed declared-target validation"
fi
printf '%s\n' '<!-- scout-target: OWNER/REPOSITORY -->' \
  > "${fixture}/case-target-prompt.md"
prompt_targets_repository "${fixture}/case-target-prompt.md" owner/repository \
  || fail "declared-target validation is case-sensitive"

node -e '
const fs = require("fs");
const now = new Date();
function isoWeek(date) {
  const value = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  value.setUTCDate(value.getUTCDate() + 4 - (value.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(value.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((value - yearStart) / 86400000) + 1) / 7);
  return `${value.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}
fs.writeFileSync(process.argv[1], JSON.stringify({
  version: 1,
  repository: "owner/repository",
  metrics: {
    isoWeek: isoWeek(now),
    processed: 8,
    prsCreated: 3,
    openPullRequests: 1
  },
  readiness: {
    reviewedAt: now.toISOString().slice(0, 10),
    scoutEligible: true
  }
}, null, 2));
' "${fixture}/readiness.json"

run_dry() {
  "${enable}" \
    --repo owner/repository \
    --readiness-evidence "${fixture}/readiness.json" \
    --output "${fixture}/scout.md" \
    --labels "kaizen,team:maintenance" \
    --wip-limit 4 \
    --creation-limit 2 \
    --dry-run
}

run_dry > "${fixture}/dry-1.out"
run_dry > "${fixture}/dry-2.out"
cmp "${fixture}/dry-1.out" "${fixture}/dry-2.out" \
  || fail "identical inputs did not render deterministically"
[[ ! -e "${fixture}/scout.md" ]] \
  || fail "dry-run wrote the output file"
grep -Fq 'Scout `owner/repository`' "${fixture}/dry-1.out" \
  || fail "repository placeholder was not rendered"
grep -Fq '`kaizen`, `team:maintenance`' "${fixture}/dry-1.out" \
  || fail "label placeholder was not rendered"
grep -Fq 'Create no more than `2` issues' "${fixture}/dry-1.out" \
  || fail "creation limit placeholder was not rendered"

if "${enable}" \
  --repo owner/repository \
  --readiness-evidence "${fixture}/readiness.json" \
  --output "${fixture}/missing-kaizen.md" \
  --labels "team:maintenance" \
  --dry-run >"${fixture}/missing-kaizen.out" 2>&1; then
  fail "scout accepted labels without the mandatory kaizen intake label"
fi

node -e \
  'const fs=require("fs"),v=JSON.parse(fs.readFileSync(process.argv[1]));v.repository=process.argv[3];fs.writeFileSync(process.argv[2],JSON.stringify(v))' \
  "${fixture}/readiness.json" \
  "${fixture}/org-readiness.json" \
  "KAIZEN-AGENTS-ORG/repository"
"${enable}" \
  --repo KAIZEN-AGENTS-ORG/repository \
  --readiness-evidence "${fixture}/org-readiness.json" \
  --output "${fixture}/org-scout.md" \
  --dry-run >"${fixture}/org-dry.out"
grep -Fq '`kaizen`, `kaizen:authorized`, `kaizen:ready`' "${fixture}/org-dry.out" \
  || fail "organization scout defaults omitted execution-gate labels"
if "${enable}" \
  --repo KAIZEN-AGENTS-ORG/repository \
  --readiness-evidence "${fixture}/org-readiness.json" \
  --output "${fixture}/org-missing-gates.md" \
  --labels "kaizen" \
  --dry-run >"${fixture}/org-missing-gates.out" 2>&1; then
  fail "organization scout accepted labels without execution gates"
fi

for fixed_target in \
  KAIZEN-AGENTS-ORG/.GITHUB \
  kaizen-agents-org/builder-agent \
  kaizen-agents-org/kaizen-loop \
  kaizen-agents-org/verifier; do
  fixed_slug="${fixed_target##*/}"
  node -e \
    'const fs=require("fs"),v=JSON.parse(fs.readFileSync(process.argv[1]));v.repository=process.argv[3];fs.writeFileSync(process.argv[2],JSON.stringify(v))' \
    "${fixture}/readiness.json" \
    "${fixture}/fixed-${fixed_slug}.json" \
    "${fixed_target}"
  if "${enable}" \
    --repo "${fixed_target}" \
    --readiness-evidence "${fixture}/fixed-${fixed_slug}.json" \
    --output "${fixture}/fixed-${fixed_slug}.md" \
    --dry-run >"${fixture}/fixed-${fixed_slug}.out" 2>&1; then
    fail "per-repository scout accepted fixed organization target ${fixed_target}"
  fi
done

touch "${fixture}/existing.md"
if "${enable}" \
  --repo owner/repository \
  --readiness-evidence "${fixture}/readiness.json" \
  --output "${fixture}/existing.md" \
  --dry-run >"${fixture}/dry-existing.out" 2>&1; then
  fail "dry-run accepted an existing output"
fi
if "${enable}" \
  --repo owner/repository \
  --readiness-evidence "${fixture}/readiness.json" \
  --output "${fixture}/missing/scout.md" \
  --dry-run >"${fixture}/dry-missing-parent.out" 2>&1; then
  fail "dry-run accepted a missing output directory"
fi

if "${enable}" \
  --repo owner/repository \
  --readiness-evidence "${fixture}/readiness.json" \
  --output "${fixture}/scout.md" >"${fixture}/unconfirmed.out" 2>&1; then
  fail "enablement succeeded without confirmation"
fi
[[ ! -e "${fixture}/scout.md" ]] \
  || fail "failed confirmation wrote the output file"

"${enable}" \
  --repo owner/repository \
  --readiness-evidence "${fixture}/readiness.json" \
  --output "${fixture}/scout.md" \
  --confirm owner/repository > "${fixture}/enabled.out"
[[ -s "${fixture}/scout.md" ]] \
  || fail "confirmed enablement did not install the prompt"
grep -Fq 'Scout prompt enabled for owner/repository' "${fixture}/enabled.out" \
  || fail "enablement was not reported"

if "${enable}" \
  --repo owner/repository \
  --readiness-evidence "${fixture}/readiness.json" \
  --output "${fixture}/scout.md" \
  --confirm owner/repository >"${fixture}/overwrite.out" 2>&1; then
  fail "enablement overwrote an existing output"
fi

expect_evidence_rejection() {
  local name="$1"
  local expression="$2"
  node -e \
    'const fs=require("fs"),p=process.argv[1],e=process.argv[2],v=JSON.parse(fs.readFileSync(process.argv[3]));Function("v",e)(v);fs.writeFileSync(p,JSON.stringify(v))' \
    "${fixture}/${name}.json" "${expression}" "${fixture}/readiness.json"
  if "${enable}" \
    --repo owner/repository \
    --readiness-evidence "${fixture}/${name}.json" \
    --output "${fixture}/${name}.md" \
    --dry-run >"${fixture}/${name}.out" 2>&1; then
    fail "invalid evidence passed: ${name}"
  fi
  [[ ! -e "${fixture}/${name}.md" ]] \
    || fail "invalid evidence wrote output: ${name}"
}

expect_evidence_rejection wrong-repository 'v.repository="owner/other"'
expect_evidence_rejection no-throughput 'v.metrics.prsCreated=0'
expect_evidence_rejection wip-full 'v.metrics.openPullRequests=4'
expect_evidence_rejection not-approved 'v.readiness.scoutEligible=false'
expect_evidence_rejection stale-review 'v.readiness.reviewedAt="2020-01-01";v.metrics.isoWeek="2020-W01"'

node "${validator}" "${repo_root}/onboarding/fleet.json" >/dev/null
cp "${repo_root}/onboarding/fleet.json" "${fixture}/fleet.json"
node -e \
  'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.repositories.push({...v.repositories[0],projectSlug:"other",localCheckout:"other"});fs.writeFileSync(p,JSON.stringify(v))' \
  "${fixture}/fleet.json"
if node "${validator}" "${fixture}/fleet.json" >"${fixture}/fleet.out" 2>&1; then
  fail "duplicate fleet repository passed validation"
fi
grep -Fq 'repository is duplicated' "${fixture}/fleet.out" \
  || fail "duplicate fleet failure was not specific"

cp "${repo_root}/onboarding/fleet.json" "${fixture}/fleet.json"
node -e \
  'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.repositories.push({...v.repositories[0],repository:v.repositories[0].repository.toUpperCase(),projectSlug:"case-variant",localCheckout:"case-variant"});fs.writeFileSync(p,JSON.stringify(v))' \
  "${fixture}/fleet.json"
if node "${validator}" "${fixture}/fleet.json" >"${fixture}/fleet-case.out" 2>&1; then
  fail "case-insensitive duplicate fleet repository passed validation"
fi
grep -Fq 'repository is duplicated' "${fixture}/fleet-case.out" \
  || fail "case-insensitive duplicate fleet failure was not specific"

cp "${repo_root}/onboarding/fleet.json" "${fixture}/fleet.json"
node -e \
  'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.repositories.push({...v.repositories[0],repository:"other/repository",projectSlug:"checkout-case",localCheckout:v.repositories[0].localCheckout.toUpperCase()});fs.writeFileSync(p,JSON.stringify(v))' \
  "${fixture}/fleet.json"
if node "${validator}" "${fixture}/fleet.json" >"${fixture}/fleet-checkout-case.out" 2>&1; then
  fail "case-insensitive duplicate local checkout passed validation"
fi
grep -Fq 'localCheckout is duplicated' "${fixture}/fleet-checkout-case.out" \
  || fail "case-insensitive duplicate checkout failure was not specific"

cp "${repo_root}/onboarding/fleet.json" "${fixture}/fleet.json"
node -e \
  'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.repositories[0].unexpected=true;fs.writeFileSync(p,JSON.stringify(v))' \
  "${fixture}/fleet.json"
if node "${validator}" "${fixture}/fleet.json" >"${fixture}/fleet-schema.out" 2>&1; then
  fail "unknown fleet schema field passed validation"
fi
grep -Fq 'must contain exactly' "${fixture}/fleet-schema.out" \
  || fail "fleet schema failure was not specific"

cp "${repo_root}/onboarding/fleet.json" "${fixture}/fleet.json"
node -e \
  'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.repositories[0].monitor=false;v.repositories[0].weeklyReadiness=false;fs.writeFileSync(p,JSON.stringify(v))' \
  "${fixture}/fleet.json"
if node "${validator}" "${fixture}/fleet.json" >"${fixture}/fleet-no-consumer.out" 2>&1; then
  fail "fleet entry without a read-only consumer passed validation"
fi
grep -Fq 'must enable at least one read-only fleet consumer' "${fixture}/fleet-no-consumer.out" \
  || fail "missing read-only-consumer failure was not specific"

echo "PASS: scout enablement and fleet registry contracts are enforced"
