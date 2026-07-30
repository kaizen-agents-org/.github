#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture_base="${KAIZEN_TEST_TMPDIR:-/tmp}"
real_mktemp="$(command -v mktemp)"
fixture_root="$("${real_mktemp}" -d "${fixture_base%/}/onboarding-versions-sandbox.XXXXXX")"
trap 'rm -rf "${fixture_root}"' EXIT

cat > "${fixture_root}/mktemp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "mktemp must receive an explicit template" >&2
  exit 1
fi

exec "${REAL_MKTEMP}" "$@"
SH
chmod +x "${fixture_root}/mktemp"

PATH="${fixture_root}:${PATH}" \
  REAL_MKTEMP="${real_mktemp}" \
  KAIZEN_TEST_TMPDIR="${fixture_base}" \
  bash "${script_dir}/test-onboarding-versions.sh"
