#!/usr/bin/env bash
set -euo pipefail

repo=""
branch=""
required_check=""
dry_run=false
repo_seen=false
branch_seen=false
check_seen=false

usage() {
  cat >&2 <<'USAGE'
usage: apply-branch-protection.sh --repo <owner/repo> --branch <name> --check <required-check-name> [--dry-run]

Applies the Kaizen organization branch-protection policy with one required
status check, strict status checks, conversation resolution, and admin
enforcement. This admin-operated command is intentionally separate from
kaizen init.
USAGE
}

fail() {
  echo "error: $*" >&2
  usage
  exit 1
}

require_option_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "${value}" && "${value}" != --* ]] \
    || fail "${option} requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ "${repo_seen}" == false ]] || fail "--repo may be supplied only once"
      require_option_value "$1" "${2:-}"
      repo="$2"
      repo_seen=true
      shift 2
      ;;
    --branch)
      [[ "${branch_seen}" == false ]] || fail "--branch may be supplied only once"
      require_option_value "$1" "${2:-}"
      branch="$2"
      branch_seen=true
      shift 2
      ;;
    --check)
      [[ "${check_seen}" == false ]] || fail "--check may be supplied only once"
      require_option_value "$1" "${2:-}"
      required_check="$2"
      check_seen=true
      shift 2
      ;;
    --dry-run)
      [[ "${dry_run}" == false ]] || fail "--dry-run may be supplied only once"
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ "${repo_seen}" == true ]] || fail "--repo is required"
[[ "${branch_seen}" == true ]] || fail "--branch is required"
[[ "${check_seen}" == true ]] || fail "--check is required"

for command_name in jq git; do
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command not found: ${command_name}"
done

[[ "${repo}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]] \
  || fail "--repo must be an explicit owner/repo"
validated_branch="$(git check-ref-format --branch "${branch}" 2>/dev/null)" \
  || fail "--branch is not a valid branch name: ${branch}"
[[ "${validated_branch}" == "${branch}" ]] \
  || fail "--branch must be an explicit branch name, not checkout shorthand: ${branch}"
[[ "${required_check}" =~ [^[:space:]] ]] \
  || fail "--check must contain a non-whitespace character"
[[ ! "${required_check}" =~ [[:cntrl:]] ]] \
  || fail "--check must not contain control characters"

tmp_parent="${TMPDIR:-/tmp}"
if [[ ! -d "${tmp_parent}" || ! -w "${tmp_parent}" ]]; then
  tmp_parent="/tmp"
fi
payload_file="$(mktemp "${tmp_parent%/}/kaizen-branch-protection.XXXXXX")"
trap 'rm -f "${payload_file}"' EXIT

jq -n --arg check "${required_check}" '{
  required_status_checks: {
    strict: true,
    contexts: [$check]
  },
  enforce_admins: true,
  required_pull_request_reviews: null,
  restrictions: null,
  required_conversation_resolution: true
}' > "${payload_file}"

encoded_branch="$(jq -rn --arg branch "${branch}" '$branch | @uri')"
endpoint="repos/${repo}/branches/${encoded_branch}/protection"

printf 'Target repository: %s\n' "${repo}"
printf 'Target branch: %s\n' "${branch}"
printf 'Required check: %s\n' "${required_check}"
printf 'Proposed branch-protection policy:\n'
cat "${payload_file}"

if [[ "${dry_run}" == true ]]; then
  echo "Dry run: no GitHub mutation performed."
  exit 0
fi

command -v gh >/dev/null 2>&1 \
  || fail "required command not found: gh"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "${endpoint}" \
  --input "${payload_file}"

printf 'Applied branch protection to %s@%s.\n' "${repo}" "${branch}"
