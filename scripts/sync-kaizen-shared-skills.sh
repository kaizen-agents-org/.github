#!/usr/bin/env bash
set -euo pipefail

source_root="${1:-$(pwd)}"
shift || true

if [[ ! -d "${source_root}/skills" ]]; then
  echo "source root must contain a skills directory: ${source_root}" >&2
  exit 1
fi

if [[ "$#" -eq 0 ]]; then
  set -- \
    "${source_root}/../builder-agent" \
    "${source_root}/../verifier" \
    "${source_root}/../kaizen-loop" \
    "${source_root}/../coderabbit" \
    "${source_root}/../renovate-config"
fi

skills=(
  "gh-link-issue-pr"
  "kaizen-bug-router"
  "pr-guardian"
)

for target_root in "$@"; do
  target_top_level="$(git -C "${target_root}" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "${target_top_level}" ]]; then
    echo "target root must be a git repository: ${target_root}" >&2
    exit 1
  fi
  if ! target_abs="$(cd "${target_root}" 2>/dev/null && pwd -P)"; then
    echo "target root must be a git repository: ${target_root}" >&2
    exit 1
  fi
  if ! target_top_level_abs="$(cd "${target_top_level}" 2>/dev/null && pwd -P)"; then
    echo "target root must be a git repository: ${target_root}" >&2
    exit 1
  fi
  if [[ "${target_abs}" != "${target_top_level_abs}" ]]; then
    echo "target root must be the git repository root: ${target_root}" >&2
    exit 1
  fi

  mkdir -p "${target_root}/skills"

  for skill in "${skills[@]}"; do
    if [[ ! -d "${source_root}/skills/${skill}" ]]; then
      echo "missing source skill: ${source_root}/skills/${skill}" >&2
      exit 1
    fi

    rm -rf "${target_root}/skills/${skill}"
    cp -R "${source_root}/skills/${skill}" "${target_root}/skills/${skill}"
    diff -qr "${source_root}/skills/${skill}" "${target_root}/skills/${skill}" >/dev/null
  done

  echo "Synced ${#skills[@]} skills into ${target_root}"
done
