#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
enable="${repo_root}/onboarding/scripts/enable-scout.sh"
validator="${repo_root}/onboarding/scripts/validate-fleet.mjs"
fixture_base="${KAIZEN_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
fixture="$(mktemp -d "${fixture_base%/}/scout-fleet-contract.XXXXXX")"
trap 'rm -rf "${fixture}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

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

echo "PASS: scout enablement and fleet registry contracts are enforced"
