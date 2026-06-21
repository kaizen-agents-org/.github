#!/usr/bin/env bash
set -euo pipefail

source_root="${1:-$(pwd)}"
target_parent="${2:-${source_root}/..}"
manifest="${source_root}/.github/dogfood-sync/manifest.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read ${manifest}" >&2
  exit 1
fi

if [[ ! -f "${manifest}" ]]; then
  echo "missing daily dogfood sync manifest: ${manifest}" >&2
  exit 1
fi

is_managed_path() {
  local changed_path="$1"
  shift

  local managed_path
  for managed_path in "$@"; do
    if [[ "${changed_path}" == "${managed_path}" || "${changed_path}" == "${managed_path}/"* ]]; then
      return 0
    fi
  done

  return 1
}

while IFS= read -r repo; do
  target_root="${target_parent}/${repo}"
  if [[ ! -d "${target_root}/.git" ]]; then
    echo "target root must be a git repository: ${target_root}" >&2
    exit 1
  fi

  managed_targets=()
  while IFS=$'\t' read -r type source target; do
    source_path="${source_root}/${source}"
    target_path="${target_root}/${target}"
    managed_targets+=("${target}")

    case "${type}" in
      directory)
        if [[ ! -d "${source_path}" ]]; then
          echo "missing source directory for ${repo}: ${source}" >&2
          exit 1
        fi
        mkdir -p "$(dirname "${target_path}")"
        rm -rf "${target_path}"
        cp -R "${source_path}" "${target_path}"
        diff -qr "${source_path}" "${target_path}" >/dev/null
        ;;
      file)
        if [[ ! -f "${source_path}" ]]; then
          echo "missing source file for ${repo}: ${source}" >&2
          exit 1
        fi
        mkdir -p "$(dirname "${target_path}")"
        cp "${source_path}" "${target_path}"
        diff -q "${source_path}" "${target_path}" >/dev/null
        ;;
      *)
        echo "unsupported managed path type for ${repo}: ${type}" >&2
        exit 1
        ;;
    esac
  done < <(
    jq -r --arg repo "${repo}" '
      .managedPaths[]
      | [
          .type,
          (.source // (.sourcePattern | gsub("\\{repo\\}"; $repo))),
          .target
        ]
      | @tsv
    ' "${manifest}"
  )

  unmanaged_changes=0
  while IFS= read -r status_line; do
    [[ -z "${status_line}" ]] && continue
    changed_path="${status_line:3}"
    changed_path="${changed_path#\"}"
    changed_path="${changed_path%\"}"
    if ! is_managed_path "${changed_path}" "${managed_targets[@]}"; then
      echo "unmanaged dogfood drift in ${repo}: ${changed_path}" >&2
      unmanaged_changes=1
    fi
  done < <(git -C "${target_root}" status --porcelain --untracked-files=all)

  if [[ "${unmanaged_changes}" -ne 0 ]]; then
    echo "refusing to continue because ${repo} has drift outside manifest-managed paths" >&2
    exit 1
  fi

  echo "Synced ${#managed_targets[@]} dogfood paths into ${repo}"
done < <(jq -r '.targets[].name' "${manifest}")
