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
    "${source_root}/../kaizen-loop"
fi

skills=(
  "gh-link-issue-pr"
  "kaizen-bug-router"
)

for target_root in "$@"; do
  if [[ ! -d "${target_root}/.git" ]]; then
    echo "target root must be a git repository: ${target_root}" >&2
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
  done

  echo "Synced ${#skills[@]} skills into ${target_root}"
done
