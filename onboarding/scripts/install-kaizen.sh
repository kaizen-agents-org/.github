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

toolchain_root=${KAIZEN_HOME:-"$HOME/.kaizen"}/toolchain

# Serialize installs of one component. Each checkout lives at a single path per
# machine and re-running is the documented update path, so scheduled jobs for
# different repositories can otherwise land here together and corrupt it.
acquire_lock() {
  lock_dir="$1.lock"
  attempts=0
  until mkdir "$lock_dir" 2>/dev/null; do
    lock_pid=''
    [ -f "$lock_dir/pid" ] && lock_pid=$(cat "$lock_dir/pid" 2>/dev/null)
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      echo "  removing a stale install lock from pid $lock_pid" >&2
      rm -rf "$lock_dir"
      continue
    fi
    attempts=$((attempts + 1))
    if [ "$attempts" -gt 60 ]; then
      echo "error: another install has held $lock_dir for too long" >&2
      exit 1
    fi
    echo "  waiting for another install to finish..." >&2
    sleep 5
  done
  printf '%s\n' "$$" > "$lock_dir/pid"
}

release_lock() {
  rm -rf "$1.lock"
}

# Check out a component at its pinned tag. Reset rather than checkout: these
# checkouts are disposable build output, and a build can leave tracked files
# modified, which would abort a plain checkout on the next update.
fetch_component() {
  home=$1
  component=$2
  version=$3
  if [ ! -d "$home/.git" ]; then
    rm -rf "$home"
    git clone --branch "$version" --depth 1 \
      "https://github.com/$owner/$component.git" "$home" >&2
  else
    git -C "$home" fetch --depth 1 origin \
      "+refs/tags/$version:refs/tags/$version" >&2
    git -C "$home" reset --hard "refs/tags/$version" >&2
    git -C "$home" clean -fd >&2
  fi
}

# Install one component from a pinned checkout.
#
# Deliberately not `npm install -g "github:owner/repo#tag"`. For a git
# dependency npm installs devDependencies, runs `prepare`, and packs the
# *result*, discarding build output committed in the tag. Components that ship
# a built dist/ therefore install with an empty dist/ and a dangling bin. All
# three components use this path so the install story is one story.
install_from_source() {
  component=$1
  version=$2
  probe=$3
  package_manager=$4
  link_dir=$5

  home="$toolchain_root/$component"
  stamp="$home/.installed-version"

  if [ "$force" -eq 0 ] && [ -f "$stamp" ] &&
     [ "$(cat "$stamp" 2>/dev/null)" = "$version" ] &&
     command -v "$probe" >/dev/null 2>&1; then
    echo "  $component already at $version; skipping"
    return 0
  fi

  command -v "$package_manager" >/dev/null 2>&1 || {
    echo "error: $component requires $package_manager; install it first" >&2
    exit 2
  }

  echo "  installing $component $version from source"
  mkdir -p "$toolchain_root"
  acquire_lock "$home"
  # shellcheck disable=SC2064
  trap "release_lock '$home'" EXIT INT TERM HUP

  fetch_component "$home" "$component" "$version"
  (
    cd "$home"
    case "$package_manager" in
      pnpm) pnpm install --frozen-lockfile && pnpm build ;;
      *) npm ci && npm run build ;;
    esac
    cd "$link_dir"
    # npm link leaves an existing global link to a different directory in
    # place, so a checkout linked by earlier tooling keeps winning and the
    # pinned build is silently unused. Remove any global link for this package
    # first; npm link recreates it pointing here.
    package_name=$(node -p "require('./package.json').name")
    global_link="$(npm prefix -g)/lib/node_modules/$package_name"
    if [ -L "$global_link" ]; then
      echo "  removing an existing global link for $package_name" >&2
      rm -f "$global_link"
    fi
    npm link
  ) >&2

  printf '%s\n' "$version" > "$stamp"
  release_lock "$home"
  trap - EXIT INT TERM HUP
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

install_from_source kaizen-loop "$(read_version kaizen-loop)" kaizen npm .
install_from_source builder-agent "$(read_version builder-agent)" builder-agent npm .

# verifier is a pnpm workspace whose root package has no bin, so the CLI is
# linked from packages/core rather than the repository root.
install_from_source verifier "$(read_version verifier)" verifier pnpm packages/core

echo
echo "Kaizen toolchain installed. Verify with: kaizen doctor"
