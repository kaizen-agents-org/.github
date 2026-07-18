#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${1:-${repo_root}/skills/pr-guardian/SKILL.md}"

require_contract() {
  local pattern="$1"
  local description="$2"
  if ! grep -Fq -- "${pattern}" "${skill}"; then
    echo "pr-guardian contract missing ${description}: ${pattern}" >&2
    exit 1
  fi
}

require_contract 'isDraft,mergeable,mergeStateStatus' 'explicit draft and mergeability inspection'
require_contract 'paginate every connection until `hasNextPage=false`' 'complete paginated feedback inspection'
require_contract 'references/pr-feedback-audit.md' 'executable thread-aware audit'
require_contract 'reply to each addressed thread' 'per-thread reply behavior'
require_contract '`resolveReviewThread`' 'thread resolution behavior'
require_contract 'including outdated threads' 'outdated unresolved thread handling'
require_contract 'pin the new head SHA' 'current-head evidence reset'
require_contract 'two passing snapshots at least 30 seconds apart' 'post-review stabilization'
require_contract '`mergeable=MERGEABLE`' 'GitHub mergeability gate'
require_contract '`mergeStateStatus=CLEAN` or `HAS_HOOKS`' 'clean merge-state gate'
require_contract 'observed final state' 'truthful no-fix reporting'

skill_dir="$(cd "$(dirname "${skill}")" && pwd)"
reference="${skill_dir}/references/pr-feedback-audit.md"
if [[ ! -f "${reference}" ]]; then
  echo "pr-guardian contract missing audit reference: ${reference}" >&2
  exit 1
fi

executable="$(
  awk '
    /^```(sh|bash|shell)$/ { in_shell = 1; next }
    /^```$/ { in_shell = 0; next }
    in_shell { print }
  ' "${reference}"
)"

for pattern in \
  'while :; do' \
  'cursor=${cursor}' \
  'hasNextPage' \
  'endCursor' \
  'reviewThreads(first:100, after:$cursor)' \
  'comments(first:100, after:$cursor)' \
  '--paginate' \
  'pulls/<pr>/reviews?per_page=100' \
  'pulls/<pr>/comments?per_page=100' \
  'issues/<pr>/comments?per_page=100' \
  'commits/<head-sha>/check-runs?per_page=100' \
  'check-runs/<check-run-id>/annotations?per_page=100' \
  'gh api --method POST' \
  '/replies' \
  'resolveReviewThread(input:{threadId:$threadId})'; do
  if ! grep -Fq -- "${pattern}" <<<"${executable}"; then
    echo "pr-guardian audit reference missing executable contract: ${pattern}" >&2
    exit 1
  fi
done

reply_line="$(grep -nF -- 'gh api --method POST' <<<"${executable}" | head -1 | cut -d: -f1)"
resolve_line="$(grep -nF -- 'resolveReviewThread(input:{threadId:$threadId})' <<<"${executable}" | head -1 | cut -d: -f1)"
if [[ -z "${reply_line}" || -z "${resolve_line}" || "${reply_line}" -ge "${resolve_line}" ]]; then
  echo 'pr-guardian audit reference must reply before resolveReviewThread' >&2
  exit 1
fi

echo "PASS: pr-guardian source preserves the merge-readiness contract"
