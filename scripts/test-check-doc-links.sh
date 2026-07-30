#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

output="$(LC_ALL=C LANG=C bash "${script_dir}/check-doc-links.sh")"

test "${output}" = "All docs Markdown links resolve."
