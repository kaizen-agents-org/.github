#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/pull-request-contracts.yml"

test -s "${workflow}"
grep -Fq 'pull_request:' "${workflow}"
grep -Fq 'types: [opened, synchronize, reopened, ready_for_review]' "${workflow}"
grep -Fq 'contents: read' "${workflow}"
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

echo 'PASS: pull-request contract CI remains read-only and complete'
