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

write_permission_pattern="(^|[[:space:]])permissions:[[:space:]]*['\"]?write-all['\"]?([[:space:]]|\$)|(^|[,{[:space:]])[[:space:]]*['\"]?[[:alnum:]_-]+['\"]?:[[:space:]]*['\"]?write['\"]?([,}#[:space:]]|\$)"
for write_permission_fixture in \
  'packages: write' \
  "packages: 'write'" \
  'checks: "write"' \
  '"id-token": "write"' \
  'permissions: write-all' \
  "permissions: 'write-all'" \
  'permissions: "write-all"' \
  "permissions: {contents: read, id-token: 'write'}"
do
  if ! grep -Eq "${write_permission_pattern}" <<< "${write_permission_fixture}"; then
    echo "write permission guard missed fixture: ${write_permission_fixture}" >&2
    exit 1
  fi
done

if grep -Eq "${write_permission_pattern}" "${workflow}"; then
  echo 'pull-request contract workflow must remain read-only' >&2
  exit 1
fi

echo 'PASS: pull-request contract CI remains read-only and complete'
