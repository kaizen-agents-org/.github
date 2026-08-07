#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TMPDIR="${KAIZEN_TEST_TMPDIR:-/tmp}"
export COPYFILE_DISABLE=1
fixture="$(mktemp -d "${TMPDIR}/kaizen-selection-contract.XXXXXX")"
error_log="${fixture}/contract-error.log"
trap 'rm -rf "${fixture}"' EXIT

tar -C "${repo_root}" -cf - .github .kaizen automations docs scripts skills \
  | tar -C "${fixture}" -xf -

bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" >/dev/null

sed -i.bak '/^    mode: canonical-main$/d' \
  "${fixture}/.github/dogfood-sync/targets/verifier/.kaizen/config.yml"
if bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" > /dev/null 2>"${error_log}"; then
  echo "contract unexpectedly accepted a dogfood config without canonical-main Verifier updates" >&2
  exit 1
fi
grep -q 'dogfood runtime config must opt into verifier canonical-main updates with timeoutMinutes: 15' "${error_log}"
mv "${fixture}/.github/dogfood-sync/targets/verifier/.kaizen/config.yml.bak" \
  "${fixture}/.github/dogfood-sync/targets/verifier/.kaizen/config.yml"

sed -i.bak '/SEMANTIC_EVAL_WRITE_METRICS=false pnpm eval:semantic:ci/d' \
  "${fixture}/.github/dogfood-sync/targets/verifier/.kaizen/config.yml"
if bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" > /dev/null 2>"${error_log}"; then
  echo "contract unexpectedly accepted verifier config without semantic eval CI" >&2
  exit 1
fi
grep -Fq 'verifier dogfood verification is missing:' "${error_log}"
mv "${fixture}/.github/dogfood-sync/targets/verifier/.kaizen/config.yml.bak" \
  "${fixture}/.github/dogfood-sync/targets/verifier/.kaizen/config.yml"

sed -i.bak '/SEMANTIC_EVAL_WRITE_METRICS=false pnpm eval:semantic:ci/d' \
  "${fixture}/.github/dogfood-sync/targets/verifier/AGENTS.md"
if bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" > /dev/null 2>"${error_log}"; then
  echo "contract unexpectedly accepted verifier guidance without semantic eval CI" >&2
  exit 1
fi
grep -Fq 'verifier dogfood guidance is missing:' "${error_log}"
mv "${fixture}/.github/dogfood-sync/targets/verifier/AGENTS.md.bak" \
  "${fixture}/.github/dogfood-sync/targets/verifier/AGENTS.md"

scout_prompt="${fixture}/automations/kaizen-agents-repo-improvement-scout.prompt.md"
mutated_prompt="${fixture}/scout.prompt.md"
sed 's/`kaizen`, `kaizen:authorized`, and `kaizen:ready` labels/`kaizen` and `kaizen:authorized` labels/' \
  "${scout_prompt}" > "${mutated_prompt}"
mv "${mutated_prompt}" "${scout_prompt}"

if bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" > /dev/null 2>"${error_log}"; then
  echo "FAIL: contract accepted a trusted issue creator without kaizen:ready" >&2
  exit 1
fi

grep -Fq \
  'trusted issue creator must add configured selection label kaizen:ready: automations/kaizen-agents-repo-improvement-scout.prompt.md' \
  "${error_log}"

rm -rf "${fixture}"
mkdir -p "${fixture}"
tar -C "${repo_root}" -cf - .github .kaizen automations docs scripts skills \
  | tar -C "${fixture}" -xf -
sed -i.bak 's/ and `kaizen:ready`//' "${fixture}/skills/kaizen-bug-router/SKILL.md"
rm "${fixture}/skills/kaizen-bug-router/SKILL.md.bak"
if bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" >/dev/null 2>&1; then
  echo "FAIL: contract accepted bug routing without kaizen:ready" >&2
  exit 1
fi

rm -rf "${fixture}"
mkdir -p "${fixture}"
tar -C "${repo_root}" -cf - .github .kaizen automations docs scripts skills \
  | tar -C "${fixture}" -xf -
sed -i.bak 's/ and `kaizen:ready`//' \
  "${fixture}/.github/dogfood-sync/targets/builder-agent/AGENTS.md"
rm "${fixture}/.github/dogfood-sync/targets/builder-agent/AGENTS.md.bak"
if bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" >/dev/null 2>&1; then
  echo "FAIL: contract accepted managed AGENTS without kaizen:ready" >&2
  exit 1
fi

echo "PASS: trusted issue creators must include the configured selection label"
