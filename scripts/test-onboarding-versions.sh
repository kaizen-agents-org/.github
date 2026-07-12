#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
manifest="${repo_root}/onboarding/versions.json"
tmp_manifest="$(mktemp)"
tmp_error="$(mktemp)"
trap 'rm -f "${tmp_manifest}" "${tmp_error}"' EXIT

node "${repo_root}/scripts/validate-onboarding-versions.mjs" "${manifest}"

printf 'null\n' > "${tmp_manifest}"
if node "${repo_root}/scripts/validate-onboarding-versions.mjs" "${tmp_manifest}"; then
  echo "FAIL: null manifest should be rejected" >&2
  exit 1
fi

cat > "${tmp_manifest}" <<'JSON'
{
  "kaizen-loop": "v0.01.0",
  "builder-agent": "v0.1.0",
  "verifier": "v0.1.0"
}
JSON
if node "${repo_root}/scripts/validate-onboarding-versions.mjs" "${tmp_manifest}"; then
  echo "FAIL: leading-zero versions should be rejected" >&2
  exit 1
fi

cat > "${tmp_manifest}" <<'JSON'
{
  "kaizen-loop": "v0.1.0",
  "builder-agent": "v0.1.0",
  "kaizen-loop": "v0.2.0",
  "verifier": "v0.1.0"
}
JSON
if node "${repo_root}/scripts/validate-onboarding-versions.mjs" "${tmp_manifest}" 2> "${tmp_error}"; then
  echo "FAIL: duplicate component keys should be rejected" >&2
  exit 1
fi
if ! grep -Fq "duplicate component key: kaizen-loop" "${tmp_error}"; then
  echo "FAIL: duplicate component key error should identify the key" >&2
  cat "${tmp_error}" >&2
  exit 1
fi

echo "PASS: onboarding versions manifest is valid"
