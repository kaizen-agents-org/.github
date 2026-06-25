#!/usr/bin/env bash
set -euo pipefail

# Regression test for the shared-skill sync workflow's source issue assertion.
# It extracts the workflow function and drives it with a fake gh command so the
# test covers retry and delayed-link fallback behavior without network access.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/sync-kaizen-shared-skills.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

awk '
  /^          ensure_existing_pr_links_source_issue\(\) \{/ && capture { exit }
  /^          assert_pr_links_source_issue\(\) \{/ { capture = 1 }
  capture {
    sub(/^          /, "")
    print
  }
' "${workflow}" > "${tmp}/assertion.sh"

grep -q "Shared skill sync source issue link pending" "${tmp}/assertion.sh" \
  || fail "assertion function does not contain a propagation retry notice"
grep -q "Shared skill sync source issue link delayed" "${tmp}/assertion.sh" \
  || fail "assertion function does not contain delayed-link fallback warning"

mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

state="${GH_STUB_STATE:?}"
mode="${GH_STUB_MODE:?}"
mkdir -p "${state}"

if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  echo "main"
  exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  count_file="${state}/pr_view_count"
  count=0
  if [ -f "${count_file}" ]; then
    count="$(cat "${count_file}")"
  fi
  count=$((count + 1))
  echo "${count}" > "${count_file}"

  case "${mode}" in
    retry)
      if [ "${count}" -lt 2 ]; then
        cat <<'JSON'
{"baseRefName":"main","body":"Closes kaizen-agents-org/.github#49","closingIssuesReferences":[],"isDraft":false}
JSON
      else
        cat <<'JSON'
{"baseRefName":"main","body":"Closes kaizen-agents-org/.github#49","closingIssuesReferences":[{"repository":{"owner":{"login":"kaizen-agents-org"},"name":".github"},"number":49,"url":"https://github.com/kaizen-agents-org/.github/issues/49"}],"isDraft":false}
JSON
      fi
      ;;
    delayed)
      cat <<'JSON'
{"baseRefName":"main","body":"Closes kaizen-agents-org/.github#49","closingIssuesReferences":[],"isDraft":false}
JSON
      ;;
    invalid)
      cat <<'JSON'
{"baseRefName":"main","body":"Source issue: kaizen-agents-org/.github#49","closingIssuesReferences":[],"isDraft":false}
JSON
      ;;
    *)
      echo "unexpected GH_STUB_MODE=${mode}" >&2
      exit 2
      ;;
  esac
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 2
SH
chmod +x "${tmp}/bin/gh"

source_issue="kaizen-agents-org/.github#49"
export source_issue
export PATH="${tmp}/bin:${PATH}"

sleep() {
  :
}

# shellcheck source=/dev/null
source "${tmp}/assertion.sh"

run_assertion() {
  local mode="$1"
  local state="${tmp}/${mode}-state"
  rm -rf "${state}"
  mkdir -p "${state}"
  GH_STUB_MODE="${mode}" GH_STUB_STATE="${state}" \
    assert_pr_links_source_issue "verifier" "https://github.com/kaizen-agents-org/verifier/pull/29"
}

run_assertion retry > "${tmp}/retry.out"
retry_count="$(cat "${tmp}/retry-state/pr_view_count")"
[ "${retry_count}" -eq 2 ] \
  || fail "retry mode should stop after linked issue appears on the second gh pr view"
grep -q "source issue link pending" "${tmp}/retry.out" \
  || fail "retry mode should emit a pending-link notice before succeeding"
echo "PASS: linked issue propagation is retried"

run_assertion delayed > "${tmp}/delayed.out"
delayed_count="$(cat "${tmp}/delayed-state/pr_view_count")"
[ "${delayed_count}" -eq 5 ] \
  || fail "delayed mode should exhaust the bounded retry window"
grep -q "source issue link delayed" "${tmp}/delayed.out" \
  || fail "delayed mode should warn instead of failing when body/base/draft checks pass"
echo "PASS: exact closing keyword on a ready default-branch PR is accepted as delayed linkage"

if ( run_assertion invalid ) > "${tmp}/invalid.out" 2>&1; then
  fail "invalid mode should fail when closingIssuesReferences and exact body line are both missing"
fi
grep -q "source issue not linked" "${tmp}/invalid.out" \
  || fail "invalid mode should explain the missing source issue linkage"
echo "PASS: missing closing reference still fails"

echo "All sync-kaizen-shared-skills PR link tests passed."
