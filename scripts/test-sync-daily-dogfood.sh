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
guardian_contract_check="${repo_root}/scripts/check-pr-guardian-contract.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to run this test" >&2
  exit 1
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- Contract: weak guardian guidance must never be distributed. ---
bash "${guardian_contract_check}" >/dev/null \
  || fail "strict pr-guardian source contract was rejected"

weak_guardian="$(mktemp)"
trap 'rm -f "${weak_guardian}"' EXIT
sed \
  -e 's/isDraft,mergeable,mergeStateStatus/isDraft,mergeStateStatus/' \
  -e 's/including outdated threads/only current threads/' \
  "${repo_root}/skills/pr-guardian/SKILL.md" > "${weak_guardian}"
if bash "${guardian_contract_check}" "${weak_guardian}" >/dev/null 2>&1; then
  fail "contract check accepted weakened pr-guardian guidance"
fi
rm -f "${weak_guardian}"
trap - EXIT
echo "PASS: weakened pr-guardian guidance is rejected before sync"

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

make_worktree_targets() {
  local base_parent="$1"
  local worktree_parent="$2"
  local repo

  while IFS= read -r repo; do
    git init -q "${base_parent}/${repo}"
    git -C "${base_parent}/${repo}" config user.email "test@example.com"
    git -C "${base_parent}/${repo}" config user.name "test"
    : > "${base_parent}/${repo}/.keep"
    git -C "${base_parent}/${repo}" add -A
    git -C "${base_parent}/${repo}" commit -qm init
    git -C "${base_parent}/${repo}" worktree add -q -b "dogfood-sync-${repo}" "${worktree_parent}/${repo}"
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

# --- Regression: linked git worktree targets are valid repositories. ---
worktree_base="$(mktemp -d)"
worktree_targets="$(mktemp -d)"
trap 'rm -rf "${happy}" "${worktree_base}" "${worktree_targets}"' EXIT
make_worktree_targets "${worktree_base}" "${worktree_targets}"

[[ -f "${worktree_targets}/builder-agent/.git" ]] \
  || fail "test setup did not create a linked worktree with .git as a file"

bash "${sync_script}" "${repo_root}" "${worktree_targets}" >/dev/null \
  || fail "sync rejected linked git worktree targets"
echo "PASS: linked git worktree targets are accepted"

# --- Safety: unmanaged drift in a target aborts the sync. ---
guard="$(mktemp -d)"
trap 'rm -rf "${happy}" "${worktree_base}" "${worktree_targets}" "${guard}"' EXIT
make_targets "${guard}"
echo "rogue" > "${guard}/builder-agent/UNMANAGED_DRIFT.txt"

if bash "${sync_script}" "${repo_root}" "${guard}" >/dev/null 2>"${guard}/err.log"; then
  fail "sync did not abort on unmanaged drift"
fi
grep -q "unmanaged dogfood drift in builder-agent: UNMANAGED_DRIFT.txt" "${guard}/err.log" \
  || fail "sync aborted but did not report the unmanaged path"
echo "PASS: unmanaged drift aborts the sync"

# --- Safety: unsafe manifest target paths abort before copy/delete. ---
unsafe_source="$(mktemp -d)"
unsafe_targets="$(mktemp -d)"
trap 'rm -rf "${happy}" "${worktree_base}" "${worktree_targets}" "${guard}" "${unsafe_source}" "${unsafe_targets}"' EXIT
mkdir -p "${unsafe_source}/.github/dogfood-sync" "${unsafe_targets}/builder-agent"
git -C "${unsafe_targets}/builder-agent" init -q
git -C "${unsafe_targets}/builder-agent" config user.email "test@example.com"
git -C "${unsafe_targets}/builder-agent" config user.name "test"
: > "${unsafe_targets}/builder-agent/.keep"
git -C "${unsafe_targets}/builder-agent" add -A
git -C "${unsafe_targets}/builder-agent" commit -qm init
echo "safe" > "${unsafe_source}/safe.txt"
cat > "${unsafe_source}/.github/dogfood-sync/manifest.json" <<'JSON'
{
  "targets": [{"name": "builder-agent"}],
  "managedPaths": [
    {"type": "file", "source": "safe.txt", "target": "../ESCAPE.txt"}
  ]
}
JSON

if bash "${sync_script}" "${unsafe_source}" "${unsafe_targets}" >/dev/null 2>"${unsafe_targets}/err.log"; then
  fail "sync did not abort on unsafe target path"
fi
grep -q "unsafe managed target path for builder-agent: ../ESCAPE.txt" "${unsafe_targets}/err.log" \
  || fail "sync aborted but did not report the unsafe target path"
[[ ! -e "${unsafe_targets}/ESCAPE.txt" ]] \
  || fail "sync wrote outside the target repository"
echo "PASS: unsafe target paths abort before copy"

# --- Safety: unsafe manifest source paths abort before read/copy. ---
unsafe_source_path_source="$(mktemp -d)"
unsafe_source_path_targets="$(mktemp -d)"
trap 'rm -rf "${happy}" "${worktree_base}" "${worktree_targets}" "${guard}" "${unsafe_source}" "${unsafe_targets}" "${unsafe_source_path_source}" "${unsafe_source_path_targets}"' EXIT
mkdir -p "${unsafe_source_path_source}/.github/dogfood-sync" "${unsafe_source_path_targets}/builder-agent"
git -C "${unsafe_source_path_targets}/builder-agent" init -q
git -C "${unsafe_source_path_targets}/builder-agent" config user.email "test@example.com"
git -C "${unsafe_source_path_targets}/builder-agent" config user.name "test"
: > "${unsafe_source_path_targets}/builder-agent/.keep"
git -C "${unsafe_source_path_targets}/builder-agent" add -A
git -C "${unsafe_source_path_targets}/builder-agent" commit -qm init
cat > "${unsafe_source_path_source}/.github/dogfood-sync/manifest.json" <<'JSON'
{
  "targets": [{"name": "builder-agent"}],
  "managedPaths": [
    {"type": "file", "source": "../SECRET.txt", "target": "safe.txt"}
  ]
}
JSON

if bash "${sync_script}" "${unsafe_source_path_source}" "${unsafe_source_path_targets}" >/dev/null 2>"${unsafe_source_path_targets}/err.log"; then
  fail "sync did not abort on unsafe source path"
fi
grep -q "unsafe managed source path for builder-agent: ../SECRET.txt" "${unsafe_source_path_targets}/err.log" \
  || fail "sync aborted but did not report the unsafe source path"
[[ ! -e "${unsafe_source_path_targets}/builder-agent/safe.txt" ]] \
  || fail "sync wrote target file from an unsafe source path"
echo "PASS: unsafe source paths abort before copy"

echo "All sync-daily-dogfood tests passed."
