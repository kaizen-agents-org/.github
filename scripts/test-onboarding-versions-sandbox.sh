#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture_base="${KAIZEN_TEST_TMPDIR:-/tmp}"
real_mktemp="$(command -v mktemp)"
fixture_root="$("${real_mktemp}" -d "${fixture_base%/}/onboarding-versions-sandbox.XXXXXX")"
trap 'rm -rf "${fixture_root}"' EXIT
sandbox_tmp="${fixture_root}/tmp"
mkdir "${sandbox_tmp}"

cat > "${fixture_root}/mktemp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

template_root="${KAIZEN_TEST_TMPDIR%/}/"
template_found=false
for arg in "$@"; do
  if [[ "${arg}" == "${template_root}"* ]]; then
    template_found=true
    break
  fi
done

if [[ "${template_found}" != true ]]; then
  echo "mktemp template must be rooted under ${KAIZEN_TEST_TMPDIR}" >&2
  exit 1
fi

exec "${REAL_MKTEMP}" "$@"
SH
chmod +x "${fixture_root}/mktemp"

PATH="${fixture_root}:${PATH}" \
  REAL_MKTEMP="${real_mktemp}" \
  KAIZEN_TEST_TMPDIR="${sandbox_tmp}" \
  bash "${script_dir}/test-onboarding-versions.sh"
