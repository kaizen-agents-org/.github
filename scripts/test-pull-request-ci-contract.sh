#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/pull-request-contracts.yml"

test -s "${workflow}"
grep -Fq 'pull_request:' "${workflow}"
grep -Fq 'types: [opened, synchronize, reopened, ready_for_review]' "${workflow}"
grep -Fq 'cancel-in-progress: true' "${workflow}"
grep -Fq 'ref: ${{ steps.versions.outputs.kaizen_loop }}' "${workflow}"
grep -Fq 'run: bash scripts/run-pr-contracts.sh' "${workflow}"

if [[ "$(grep -Ec 'uses: actions/checkout@[0-9a-f]{40}' "${workflow}")" -ne 2 ]]; then
  echo 'both checkout actions must be pinned to full commit SHAs' >&2
  exit 1
fi

if [[ "$(grep -Fc 'persist-credentials: false' "${workflow}")" -ne 2 ]]; then
  echo 'both checkout actions must disable credential persistence' >&2
  exit 1
fi

grep -Eq 'uses: actions/setup-node@[0-9a-f]{40}' "${workflow}"

kaizen_loop_root="${KAIZEN_LOOP_ROOT:-}"
if [[ -z "${kaizen_loop_root}" ]]; then
  common_git_dir="$(git -C "${repo_root}" rev-parse --path-format=absolute --git-common-dir)"
  kaizen_loop_root="$(dirname "$(dirname "${common_git_dir}")")/kaizen-loop"
fi
node "${repo_root}/scripts/check-workflow-read-only-permissions.mjs" "${workflow}" "${kaizen_loop_root}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
missing_permissions_workflow="${tmp_dir}/missing-permissions.yml"
awk '
  /^permissions:$/ { skipping = 1; next }
  skipping && /^  / { next }
  { skipping = 0; print }
' "${workflow}" > "${missing_permissions_workflow}"
printf '\n# contents: read\n' >> "${missing_permissions_workflow}"
if node "${repo_root}/scripts/check-workflow-read-only-permissions.mjs" "${missing_permissions_workflow}" "${kaizen_loop_root}"; then
  echo 'workflow-level permissions must be required structurally' >&2
  exit 1
fi

echo 'PASS: pull-request contract CI remains read-only and complete'
