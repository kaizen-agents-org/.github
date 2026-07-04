#!/usr/bin/env bash
set -euo pipefail

# Regression test for the daily dogfood sync workflow's source issue assertion.
# It extracts the workflow function and drives it with a fake gh command so the
# test covers retry behavior and keeps body-only fallback from bypassing
# closingIssuesReferences without network access.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/sync-daily-dogfood.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to run this test" >&2
  exit 1
fi

tmp_parent="${TMPDIR:-/tmp}"
if [[ ! -d "${tmp_parent}" || ! -w "${tmp_parent}" ]]; then
  tmp_parent="/tmp"
fi
tmp="$(mktemp -d "${tmp_parent%/}/sync-daily-dogfood-pr-link.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

awk '
  function trimmed(line) {
    sub(/^[[:space:]]*/, "", line)
    sub(/[[:space:]]*$/, "", line)
    return line
  }
  !capture && trimmed($0) == "assert_pr_links_source_issue() {" {
    capture = 1
  }
  capture {
    line = $0
    sub(/^[[:space:]]*/, "", line)
    print line
    if (trimmed($0) == "}") {
      found = 1
      exit
    }
  }
  END {
    if (!found) {
      print "assert_pr_links_source_issue function not found" > "/dev/stderr"
      exit 1
    }
  }
' "${workflow}" > "${tmp}/assertion.sh"

grep -q "Dogfood sync source issue link pending" "${tmp}/assertion.sh" \
  || fail "assertion function does not contain a propagation retry notice"

mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

state="${GH_STUB_STATE:?}"
mode="${GH_STUB_MODE:?}"
mkdir -p "${state}"

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
{"baseRefName":"main","body":"Closes kaizen-agents-org/.github#86","closingIssuesReferences":[],"isDraft":false}
JSON
      else
        cat <<'JSON'
{"baseRefName":"main","body":"Closes kaizen-agents-org/.github#86","closingIssuesReferences":[{"repository":{"owner":{"login":"kaizen-agents-org"},"name":".github"},"number":86,"url":"https://github.com/kaizen-agents-org/.github/issues/86"}],"isDraft":false}
JSON
      fi
      ;;
    body_only)
      cat <<'JSON'
{"baseRefName":"main","body":"Closes kaizen-agents-org/.github#86","closingIssuesReferences":[],"isDraft":false}
JSON
      ;;
    invalid)
      cat <<'JSON'
{"baseRefName":"main","body":"Source issue: kaizen-agents-org/.github#86","closingIssuesReferences":[],"isDraft":false}
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

source_issue="kaizen-agents-org/.github#86"
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
    assert_pr_links_source_issue "builder-agent" "https://github.com/kaizen-agents-org/builder-agent/pull/86"
}

run_assertion retry > "${tmp}/retry.out"
retry_count="$(cat "${tmp}/retry-state/pr_view_count")"
[ "${retry_count}" -eq 2 ] \
  || fail "retry mode should stop after linked issue appears on the second gh pr view"
grep -q "source issue link pending" "${tmp}/retry.out" \
  || fail "retry mode should emit a pending-link notice before succeeding"
echo "PASS: daily dogfood linked issue propagation is retried"

if ( run_assertion body_only ) > "${tmp}/body-only.out" 2>&1; then
  fail "body-only mode should fail when closingIssuesReferences never contains the source issue"
fi
body_only_count="$(cat "${tmp}/body_only-state/pr_view_count")"
[ "${body_only_count}" -eq 5 ] \
  || fail "body-only mode should exhaust the bounded retry window"
grep -q "body text alone is not accepted as proof" "${tmp}/body-only.out" \
  || fail "body-only mode should explain that body text is not proof of linkage"
echo "PASS: daily dogfood exact closing keyword without closingIssuesReferences still fails"

if ( run_assertion invalid ) > "${tmp}/invalid.out" 2>&1; then
  fail "invalid mode should fail when closingIssuesReferences and exact body line are both missing"
fi
grep -q "source issue not linked" "${tmp}/invalid.out" \
  || fail "invalid mode should explain the missing source issue linkage"
echo "PASS: daily dogfood missing closing reference still fails"

echo "All sync-daily-dogfood PR link tests passed."
