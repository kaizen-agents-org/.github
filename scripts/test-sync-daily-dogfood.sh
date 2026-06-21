#!/usr/bin/env bash
set -euo pipefail

# Regression test for scripts/sync-daily-dogfood.sh.
#
# Builds throwaway git target repositories, runs the sync against them, and
# asserts both the happy path (every manifest-managed path is copied and only
# managed paths change) and the safety property (genuinely unmanaged drift in a
# target aborts the sync). Guards against the directory-collapse false positive
# where `git status` reports an entire untracked directory (e.g. `skills/`)
# instead of the individual managed files beneath it.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="${repo_root}/.github/dogfood-sync/manifest.json"
sync_script="${repo_root}/scripts/sync-daily-dogfood.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to run this test" >&2
  exit 1
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_targets() {
  local parent="$1"
  while IFS= read -r repo; do
    mkdir -p "${parent}/${repo}"
    git -C "${parent}/${repo}" init -q
    git -C "${parent}/${repo}" config user.email "test@example.com"
    git -C "${parent}/${repo}" config user.name "test"
    : > "${parent}/${repo}/.keep"
    git -C "${parent}/${repo}" add -A
    git -C "${parent}/${repo}" commit -qm init
  done < <(jq -r '.targets[].name' "${manifest}")
}

# --- Happy path: managed paths copied, only managed paths change. ---
happy="$(mktemp -d)"
trap 'rm -rf "${happy}"' EXIT
make_targets "${happy}"

bash "${sync_script}" "${repo_root}" "${happy}" >/dev/null \
  || fail "sync aborted on a clean target set"

while IFS= read -r repo; do
  # Every managed path must match its source.
  while IFS=$'\t' read -r type source_path target_path; do
    case "${type}" in
      directory)
        diff -qr "${repo_root}/${source_path}" "${happy}/${repo}/${target_path}" >/dev/null \
          || fail "${repo}: managed directory ${target_path} does not match source"
        ;;
      file)
        diff -q "${repo_root}/${source_path}" "${happy}/${repo}/${target_path}" >/dev/null \
          || fail "${repo}: managed file ${target_path} does not match source"
        ;;
    esac
  done < <(
    jq -r --arg repo "${repo}" '
      .managedPaths[]
      | [.type, (.source // (.sourcePattern | gsub("\\{repo\\}"; $repo))), .target]
      | @tsv
    ' "${manifest}"
  )
done < <(jq -r '.targets[].name' "${manifest}")
echo "PASS: managed paths copied for every target"

# --- Safety: unmanaged drift in a target aborts the sync. ---
guard="$(mktemp -d)"
trap 'rm -rf "${happy}" "${guard}"' EXIT
make_targets "${guard}"
echo "rogue" > "${guard}/builder-agent/UNMANAGED_DRIFT.txt"

if bash "${sync_script}" "${repo_root}" "${guard}" >/dev/null 2>"${guard}/err.log"; then
  fail "sync did not abort on unmanaged drift"
fi
grep -q "unmanaged dogfood drift in builder-agent: UNMANAGED_DRIFT.txt" "${guard}/err.log" \
  || fail "sync aborted but did not report the unmanaged path"
echo "PASS: unmanaged drift aborts the sync"

echo "All sync-daily-dogfood tests passed."
