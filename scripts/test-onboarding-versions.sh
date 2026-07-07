#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
manifest="${repo_root}/onboarding/versions.json"

node "${repo_root}/scripts/validate-onboarding-versions.mjs" "${manifest}"

echo "PASS: onboarding versions manifest is valid"
