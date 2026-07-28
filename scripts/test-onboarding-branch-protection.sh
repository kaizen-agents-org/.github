#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
apply_script="${repo_root}/onboarding/scripts/apply-branch-protection.sh"
tmp_parent="${TMPDIR:-/tmp}"
if [[ ! -d "${tmp_parent}" || ! -w "${tmp_parent}" ]]; then
  tmp_parent="/tmp"
fi
tmp="$(mktemp -d "${tmp_parent%/}/onboarding-protection-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

count=0
if [[ -f "${GH_STUB_DIR}/count" ]]; then
  read -r count < "${GH_STUB_DIR}/count"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${GH_STUB_DIR}/count"
printf '%s\n' "$@" > "${GH_STUB_DIR}/args.${count}"

input=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--input" ]]; then
    input="${2:-}"
    break
  fi
  shift
done
[[ -n "${input}" ]] || exit 91
cp "${input}" "${GH_STUB_DIR}/payload.${count}.json"
if [[ "${GH_STUB_FORBID:-false}" == true ]]; then
  echo "gh: Resource not accessible by personal access token (HTTP 403)" >&2
  exit 1
fi
echo "GH_MUTATION_${count}"
STUB
chmod +x "${tmp}/bin/gh"

run_apply() {
  GH_STUB_DIR="${tmp}" PATH="${tmp}/bin:${PATH}" \
    "${apply_script}" \
    --repo kaizen-agents-org/example \
    --branch release/v1 \
    --check "Kaizen contract"
}

run_apply > "${tmp}/first.out"

grep -Fxq -- "--method" "${tmp}/args.1" \
  || fail "gh api method flag was not supplied"
grep -Fxq -- "PUT" "${tmp}/args.1" \
  || fail "gh api did not use PUT"
grep -Fxq -- "repos/kaizen-agents-org/example/branches/release%2Fv1/protection" "${tmp}/args.1" \
  || fail "target endpoint was not resolved and encoded correctly"

jq -e '
  . == {
    required_status_checks: {
      strict: true,
      contexts: ["Kaizen contract"]
    },
    enforce_admins: true,
    required_pull_request_reviews: null,
    restrictions: null,
    required_conversation_resolution: true
  }
' "${tmp}/payload.1.json" >/dev/null \
  || fail "generated policy payload differs from the documented preset"

policy_line="$(grep -nF "Proposed branch-protection policy:" "${tmp}/first.out" | cut -d: -f1)"
mutation_line="$(grep -nF "GH_MUTATION_1" "${tmp}/first.out" | cut -d: -f1)"
[[ -n "${policy_line}" && -n "${mutation_line}" && "${policy_line}" -lt "${mutation_line}" ]] \
  || fail "resolved target and proposed policy were not printed before mutation"

run_apply > "${tmp}/second.out"
cmp "${tmp}/payload.1.json" "${tmp}/payload.2.json" \
  || fail "reapplying the same inputs generated a different policy"
[[ "$(cat "${tmp}/count")" == "2" ]] \
  || fail "expected one PUT per apply invocation"
echo "PASS: policy generation and repeated application are deterministic"

rm -f "${tmp}/count"
GH_STUB_DIR="${tmp}" PATH="${tmp}/bin:${PATH}" \
  "${apply_script}" \
  --repo kaizen-agents-org/example \
  --branch main \
  --check "Kaizen contract" \
  --dry-run > "${tmp}/dry-run.out"
[[ ! -e "${tmp}/count" ]] \
  || fail "dry-run invoked gh"
grep -Fq "Dry run: no GitHub mutation performed." "${tmp}/dry-run.out" \
  || fail "dry-run result was not reported"
grep -Fq '"required_conversation_resolution": true' "${tmp}/dry-run.out" \
  || fail "dry-run did not print the proposed policy"
echo "PASS: dry-run prints the policy without invoking GitHub"

rm -f "${tmp}/count"
if GH_STUB_FORBID=true GH_STUB_DIR="${tmp}" PATH="${tmp}/bin:${PATH}" \
  "${apply_script}" \
  --repo kaizen-agents-org/example \
  --branch main \
  --check "Kaizen contract" \
  > "${tmp}/forbidden.out" 2> "${tmp}/forbidden.err"; then
  fail "GitHub authorization failure was ignored"
fi
[[ "$(cat "${tmp}/count")" == "1" ]] \
  || fail "authorization failure did not stop after the rejected request"
grep -Fq "Proposed branch-protection policy:" "${tmp}/forbidden.out" \
  || fail "authorization failure occurred before the policy preview"
grep -Fq "HTTP 403" "${tmp}/forbidden.err" \
  || fail "GitHub authorization error was not preserved"
if grep -Fq "Applied branch protection" "${tmp}/forbidden.out"; then
  fail "authorization failure was reported as a successful application"
fi
echo "PASS: GitHub authorization failures stop without a success report"

assert_rejected_without_gh() {
  local label="$1"
  shift
  rm -f "${tmp}/count"
  if GH_STUB_DIR="${tmp}" PATH="${tmp}/bin:${PATH}" \
    "${apply_script}" "$@" > "${tmp}/rejected.out" 2> "${tmp}/rejected.err"; then
    fail "${label} was accepted"
  fi
  [[ ! -e "${tmp}/count" ]] \
    || fail "${label} reached GitHub before failing closed"
}

assert_rejected_without_gh "missing repository" \
  --branch main --check test
assert_rejected_without_gh "ambiguous repository" \
  --repo owner/one --repo owner/two --branch main --check test
assert_rejected_without_gh "missing branch" \
  --repo owner/repo --check test
assert_rejected_without_gh "ambiguous branch" \
  --repo owner/repo --branch main --branch trunk --check test
assert_rejected_without_gh "missing check" \
  --repo owner/repo --branch main
assert_rejected_without_gh "ambiguous check" \
  --repo owner/repo --branch main --check test --check lint
echo "PASS: missing and ambiguous target inputs fail closed"

echo "All branch-protection helper tests passed."
