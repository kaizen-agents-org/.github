#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TMPDIR="${KAIZEN_TEST_TMPDIR:-/tmp}"
export COPYFILE_DISABLE=1
fixture="$(mktemp -d "${TMPDIR}/kaizen-selection-contract.XXXXXX")"
trap 'rm -rf "${fixture}"' EXIT

tar -C "${repo_root}" -cf - .github .kaizen automations docs scripts skills \
  | tar -C "${fixture}" -xf -

bash "${fixture}/scripts/check-daily-dogfood-sync-contract.sh" "${fixture}" >/dev/null

scout_prompt="${fixture}/automations/kaizen-agents-repo-improvement-scout.prompt.md"
mutated_prompt="${fixture}/scout.prompt.md"
sed 's/`kaizen`, `kaizen:authorized`, and `kaizen:ready` labels/`kaizen` and `kaizen:authorized` labels/' \
  "${scout_prompt}" > "${mutated_prompt}"
mv "${mutated_prompt}" "${scout_prompt}"

error_log="${fixture}/contract-error.log"
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
