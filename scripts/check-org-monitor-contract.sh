#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prompt="${1:-${repo_root}/automations/kaizen-agents-org-monitor.prompt.md}"

require_contract() {
  local pattern="$1"
  local description="$2"
  if ! grep -Fq -- "${pattern}" "${prompt}"; then
    echo "org-monitor contract missing ${description}: ${pattern}" >&2
    exit 1
  fi
}

require_contract 'stable duplicate-ownership key' 'a stable sync-drift ownership key'
require_contract 'the target repository, each affected managed path or component, and the concrete actionable follow-up' 'key fields'
require_contract 'compute its SHA-256 digest' 'canonical ownership-key digest'
require_contract '<!-- monitor-ownership-key: sha256:<digest> -->' 'persisted ownership marker'
require_contract 'for that exact `monitor-ownership-key` marker and digest' 'exact ownership-marker search'
require_contract 'repeated drift for `skills/pr-guardian` in one target repository with the same reconcile action is one ownership key' 'repeated managed-path regression case'
require_contract 'exact proposed title' 'exact-title search'
require_contract 'each exact managed path or component name' 'managed-path search'
require_contract 'relevant source ref or branch when available' 'source-ref search'
require_contract 'Inspect the returned issue and PR bodies' 'body inspection'
require_contract 'Repeat that exact duplicate search immediately before each `gh issue create` call' 'pre-create recheck'
require_contract 'If any required open-issue or open-PR query fails' 'fail-closed query handling'
require_contract 'acquire an atomic single-flight claim for the digest' 'overlapping-run single-flight claim'
require_contract 'Never remove or overwrite another run' 'claim ownership safety'
require_contract 'it never bypasses duplicate suppression' 'health-exception boundary'
require_contract 'Exactly one organization-wide installation of this monitor may be enabled' 'single organization-wide installation'
require_contract 'read-only with respect to the local Kaizen runtime' 'read-only local runtime boundary'
require_contract 'never write, prune, rebuild, or reconcile production `registry.json`, workspaces, scheduler jobs, run locks, or machine inventory.' 'runtime mutation prohibition'
require_contract 'Do not run a mutating `kaizen fleet` command' 'mutating fleet prohibition'
require_contract 'kaizen fleet --manifest ~/.kaizen/fleet.yml --prune --dry-run --json' 'manifest-backed read-only fleet plan'
require_contract 'must not omit `--dry-run`' 'dry-run enforcement'

if grep -Eq -- 'kaizen[[:space:]]+fleet([^[:alnum:]_]|$).*--root([=[:space:]]|$)' "${prompt}"; then
  echo 'org-monitor contract contains unsafe checkout-parent fleet discovery' >&2
  exit 1
fi

echo "PASS: org-monitor source preserves sync-drift duplicate suppression"
