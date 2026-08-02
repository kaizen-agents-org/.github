#!/bin/sh
# Install the Kaizen toolchain at the versions pinned by onboarding/versions.json.
#
# The manifest is the only place that names a version. Callers ask for "the
# pinned set", never for a specific tag, so moving to npm or a container
# registry later does not change how anyone invokes this script.
#
# Re-running is the supported update path: components already at the pinned
# version are left alone.
set -eu

owner=${KAIZEN_INSTALL_OWNER:-kaizen-agents-org}
manifest=''
dry_run=0
force=0

usage() {
  cat >&2 <<'USAGE'
Usage: install-kaizen.sh [--manifest FILE] [--dry-run] [--force]

  --manifest FILE  Version manifest to install from.
                   Defaults to onboarding/versions.json next to this script.
  --dry-run        Print what would be installed without changing anything.
  --force          Reinstall even when the pinned version is already present.

Environment:
  KAIZEN_INSTALL_OWNER  GitHub owner to install from (default kaizen-agents-org).
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest)
      [ "$#" -ge 2 ] || { echo "error: --manifest requires a file path" >&2; exit 2; }
      manifest=$2
      shift 2
      ;;
    --dry-run) dry_run=1; shift ;;
    --force) force=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "$manifest" ]; then
  manifest="$script_dir/../versions.json"
fi
if [ ! -f "$manifest" ]; then
  echo "error: version manifest not found: $manifest" >&2
  exit 2
fi

for required in node git npm; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "error: $required must be installed and on PATH" >&2
    exit 2
  }
done

# Read a component version from the manifest, rejecting anything that is not a
# v0.x.y release tag so a malformed manifest cannot turn into a git ref.
read_version() {
  node -e '
    const fs = require("node:fs");
    const [file, component] = process.argv.slice(1);
    let manifest;
    try {
      manifest = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
      console.error(`error: ${file} is not valid JSON: ${error.message}`);
      process.exit(2);
    }
    const value = manifest?.[component];
    if (typeof value !== "string" || !/^v0\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) {
      console.error(`error: ${file} does not pin ${component} to a v0.x.y release tag`);
      process.exit(2);
    }
    process.stdout.write(value);
  ' "$manifest" "$1"
}

# A pinned tag that does not exist is a release problem, not something to paper
# over by falling back to a branch: an adopter would silently run unreleased code.
require_remote_tag() {
  component=$1
  version=$2
  remote="https://github.com/$owner/$component.git"
  if [ -z "$(git ls-remote --tags "$remote" "refs/tags/$version" 2>/dev/null)" ]; then
    cat >&2 <<EOF
error: $owner/$component has no tag $version

  onboarding/versions.json pins $component to $version, but that tag does not
  exist on the remote. Publish the compatible release set first; see
  docs/release-tags.md. This installer will not fall back to a branch, because
  that would install unreleased code behind a pinned manifest.
EOF
    return 1
  fi
  return 0
}

installed_version() {
  command -v "$1" >/dev/null 2>&1 || return 1
  "$1" --version 2>/dev/null | head -1 || return 1
}

echo "Kaizen toolchain manifest: $manifest"
echo "Source owner: $owner"
echo

missing_tags=0
for component in kaizen-loop builder-agent verifier; do
  version=$(read_version "$component")
  printf '  %-14s %s\n' "$component" "$version"
  require_remote_tag "$component" "$version" || missing_tags=$((missing_tags + 1))
done
echo

if [ "$missing_tags" -gt 0 ]; then
  echo "error: $missing_tags pinned component tag(s) do not exist; nothing was installed." >&2
  exit 1
fi

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run: no changes made."
  exit 0
fi

install_component() {
  component=$1
  version=$2
  spec="github:$owner/$component#$version"

  if [ "$force" -eq 0 ] && [ -n "${3:-}" ]; then
    current=$(installed_version "$3" || true)
    # Compare whole version strings. A substring match would read an installed
    # 10.1.0 or 20.1.0 as satisfying a pinned v0.1.0 and skip a real update.
    current_trimmed=$(printf '%s' "$current" | tr -d '[:space:]')
    if [ "$current_trimmed" = "${version#v}" ] || [ "$current_trimmed" = "$version" ]; then
      echo "  $component already at $version; skipping"
      return 0
    fi
  fi

  echo "  installing $component $version"
  npm install -g "$spec" >&2
}

for component in kaizen-loop builder-agent; do
  version=$(read_version "$component")
  case "$component" in
    kaizen-loop) probe=kaizen ;;
    builder-agent) probe=builder-agent ;;
  esac
  install_component "$component" "$version" "$probe"
done

# verifier is a private pnpm workspace: its root package has no bin and is not
# installable with `npm install -g github:`. Build it from a pinned checkout and
# link the CLI that actually carries the bin.
verifier_version=$(read_version verifier)
verifier_home=${KAIZEN_HOME:-"$HOME/.kaizen"}/toolchain/verifier
if [ "$force" -eq 0 ] && [ -f "$verifier_home/.installed-version" ] &&
   [ "$(cat "$verifier_home/.installed-version")" = "$verifier_version" ] &&
   command -v verifier >/dev/null 2>&1; then
  echo "  verifier already at $verifier_version; skipping"
else
  echo "  installing verifier $verifier_version from source"
  command -v pnpm >/dev/null 2>&1 || {
    echo "error: verifier requires pnpm; install it with 'npm install -g pnpm'" >&2
    exit 2
  }
  mkdir -p "$(dirname "$verifier_home")"

  # $verifier_home is shared by every run on this machine, and re-running is the
  # documented update path, so two runs for different repositories can land
  # here together and corrupt one checkout. Serialize with a directory lock.
  verifier_lock="$verifier_home.lock"
  lock_attempts=0
  until mkdir "$verifier_lock" 2>/dev/null; do
    lock_pid=''
    [ -f "$verifier_lock/pid" ] && lock_pid=$(cat "$verifier_lock/pid" 2>/dev/null)
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      echo "  removing a stale verifier install lock from pid $lock_pid" >&2
      rm -rf "$verifier_lock"
      continue
    fi
    lock_attempts=$((lock_attempts + 1))
    if [ "$lock_attempts" -gt 60 ]; then
      echo "error: another verifier install has held $verifier_lock for too long" >&2
      exit 1
    fi
    echo "  waiting for another verifier install to finish..." >&2
    sleep 5
  done
  printf '%s\n' "$$" > "$verifier_lock/pid"
  # shellcheck disable=SC2064
  trap "rm -rf '$verifier_lock'" EXIT INT TERM HUP
  if [ ! -d "$verifier_home/.git" ]; then
    git clone --depth 1 --branch "$verifier_version" \
      "https://github.com/$owner/verifier.git" "$verifier_home" >&2
  else
    git -C "$verifier_home" fetch --depth 1 origin "refs/tags/$verifier_version:refs/tags/$verifier_version" >&2
    git -C "$verifier_home" checkout --detach "$verifier_version" >&2
  fi
  (
    cd "$verifier_home"
    pnpm install --frozen-lockfile
    pnpm build
    cd packages/core
    npm link
  ) >&2
  printf '%s\n' "$verifier_version" > "$verifier_home/.installed-version"
  rm -rf "$verifier_lock"
  trap - EXIT INT TERM HUP
fi

echo
echo "Kaizen toolchain installed. Verify with: kaizen doctor"
