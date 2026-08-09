#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/pull-request-contracts.yml"

test -s "${workflow}"
grep -Fq 'pull_request:' "${workflow}"
grep -Fq 'contents: read' "${workflow}"
grep -Fq 'cancel-in-progress: true' "${workflow}"
grep -Fq 'ref: ${{ steps.versions.outputs.kaizen_loop }}' "${workflow}"
grep -Fq 'run: bash scripts/run-pr-contracts.sh' "${workflow}"

if grep -Eq '(^|[[:space:]])(contents|pull-requests|issues|actions): write' "${workflow}"; then
  echo 'pull-request contract workflow must remain read-only' >&2
  exit 1
fi

echo 'PASS: pull-request contract CI remains read-only and complete'
