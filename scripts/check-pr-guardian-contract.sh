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

reference="${repo_root}/skills/pr-guardian/references/pr-feedback-audit.md"
if [[ ! -f "${reference}" ]]; then
  echo "pr-guardian contract missing audit reference: ${reference}" >&2
  exit 1
fi

for pattern in 'reviewThreads(first:100, after:$cursor)' '/replies' 'resolveReviewThread' 'hasNextPage'; do
  if ! grep -Fq -- "${pattern}" "${reference}"; then
    echo "pr-guardian audit reference missing executable contract: ${pattern}" >&2
    exit 1
  fi
done

echo "PASS: pr-guardian source preserves the merge-readiness contract"
