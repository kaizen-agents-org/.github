#!/usr/bin/env bash
set -euo pipefail

# Regression test for scripts/sync-kaizen-shared-skills.sh accepting linked
# Git worktrees, where .git is a file instead of a directory.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sync_script="${repo_root}/scripts/sync-kaizen-shared-skills.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_parent="${repo_root}/.tmp"
mkdir -p "${tmp_parent}"
tmp="$(mktemp -d "${tmp_parent}/sync-kaizen-shared-skills.XXXXXX")"
trap 'rm -rf "${tmp}"; rmdir "${tmp_parent}" 2>/dev/null || true' EXIT

base_repo="${tmp}/base"
worktree_repo="${tmp}/worktree"

git init -q "${base_repo}"
git -C "${base_repo}" config user.email "test@example.com"
git -C "${base_repo}" config user.name "test"
: > "${base_repo}/.keep"
git -C "${base_repo}" add -A
git -C "${base_repo}" commit -qm init
git -C "${base_repo}" worktree add -q -b skill-sync-target "${worktree_repo}"

[[ -f "${worktree_repo}/.git" ]] \
  || fail "test setup did not create a linked worktree with .git as a file"

bash "${sync_script}" "${repo_root}" "${worktree_repo}" >/dev/null \
  || fail "sync rejected a linked git worktree target"

mkdir -p "${worktree_repo}/docs"
if bash "${sync_script}" "${repo_root}" "${worktree_repo}/docs" >/dev/null 2>&1; then
  fail "sync accepted a nested directory inside a git worktree"
fi
[[ ! -e "${worktree_repo}/docs/skills" ]] \
  || fail "sync created skills under a nested target directory"

for skill in gh-link-issue-pr kaizen-bug-router pr-guardian; do
  diff -qr "${repo_root}/skills/${skill}" "${worktree_repo}/skills/${skill}" >/dev/null \
    || fail "synced skill does not match source: ${skill}"
done

invalid_source="${tmp}/invalid-source"
invalid_target="${tmp}/invalid-target"
mkdir -p "${invalid_source}/skills" "${invalid_source}/scripts"
cp -R "${repo_root}/skills/gh-link-issue-pr" "${invalid_source}/skills/"
cp -R "${repo_root}/skills/kaizen-bug-router" "${invalid_source}/skills/"
cp -R "${repo_root}/skills/pr-guardian" "${invalid_source}/skills/"
cp "${repo_root}/scripts/check-pr-guardian-contract.sh" "${invalid_source}/scripts/"
sed -i.bak 's/(.id | type == "string")/malformed guardian contract/' \
  "${invalid_source}/skills/pr-guardian/references/pr-feedback-audit.md"
rm "${invalid_source}/skills/pr-guardian/references/pr-feedback-audit.md.bak"
git init -q "${invalid_target}"
if bash "${sync_script}" "${invalid_source}" "${invalid_target}" >/dev/null 2>&1; then
  fail "sync accepted a malformed pr-guardian contract"
fi
[[ ! -e "${invalid_target}/skills" ]] \
  || fail "sync wrote target skills before validating the pr-guardian contract"

echo "PASS: shared skill sync accepts linked git worktree roots and rejects nested targets"
