#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture_base="${KAIZEN_TEST_TMPDIR:-/tmp}"
real_mktemp="$(command -v mktemp)"
fixture_root="$("${real_mktemp}" -d "${fixture_base%/}/onboarding-versions-sandbox.XXXXXX")"
trap 'rm -rf "${fixture_root}"' EXIT
sandbox_tmp="${fixture_root}/sandbox"
mkdir -p "${sandbox_tmp}"

cat > "${fixture_root}/mktemp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 || "$1" != "-d" ]]; then
  echo "mktemp must receive -d and one explicit template" >&2
  exit 1
fi
template="$2"
if [[ "${template}" != "${KAIZEN_TEST_TMPDIR%/}/"* ]]; then
  echo "mktemp template must stay under KAIZEN_TEST_TMPDIR" >&2
  exit 1
fi

exec "${REAL_MKTEMP}" "$@"
SH
chmod +x "${fixture_root}/mktemp"

if PATH="${fixture_root}:${PATH}" \
  REAL_MKTEMP="${real_mktemp}" \
  KAIZEN_TEST_TMPDIR="${sandbox_tmp}" \
  mktemp -d "/tmp/onboarding-versions.XXXXXX" >/dev/null 2>&1; then
  echo "FAIL: sandbox stub accepted a template outside KAIZEN_TEST_TMPDIR" >&2
  exit 1
fi

PATH="${fixture_root}:${PATH}" \
  REAL_MKTEMP="${real_mktemp}" \
  KAIZEN_TEST_TMPDIR="${sandbox_tmp}" \
  bash "${script_dir}/test-onboarding-versions.sh"
