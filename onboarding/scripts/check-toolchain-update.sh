#!/bin/sh
# Notice when a newer pinned toolchain set is published upstream.
#
# Adopters pull updates rather than receiving them: an organization that does
# not own the target repository cannot push a sync pull request into it. So this
# runs on the adopter's schedule, compares the installed set against upstream,
# and opens one issue when they differ. It never updates anything — applying an
# update stays a deliberate `onboard.sh` re-run by the owner.
set -eu

repo=''
local_manifest=''
upstream_ref=${KAIZEN_ONBOARDING_REF:-main}
upstream_url=''
dry_run=0

usage() {
  cat >&2 <<'USAGE'
Usage: check-toolchain-update.sh --repo <owner/repo> [options]

  --repo OWNER/REPO   Repository to notify when an update is available.
  --manifest FILE     Installed manifest (default: onboarding/versions.json
                      next to this script).
  --ref REF           Upstream ref to compare against (default: main).
  --upstream-url URL  Raw URL of the upstream manifest. Defaults to the
                      kaizen-agents-org/.github manifest at --ref.
  --dry-run           Report the comparison without creating an issue.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) [ "$#" -ge 2 ] || { echo "error: --repo requires a value" >&2; exit 2; }; repo=$2; shift 2 ;;
    --manifest) [ "$#" -ge 2 ] || { echo "error: --manifest requires a value" >&2; exit 2; }; local_manifest=$2; shift 2 ;;
    --ref) [ "$#" -ge 2 ] || { echo "error: --ref requires a value" >&2; exit 2; }; upstream_ref=$2; shift 2 ;;
    --upstream-url) [ "$#" -ge 2 ] || { echo "error: --upstream-url requires a value" >&2; exit 2; }; upstream_url=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$repo" ] || { echo "error: --repo is required" >&2; usage; exit 2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -n "$local_manifest" ] || local_manifest="$script_dir/../versions.json"
[ -f "$local_manifest" ] || { echo "error: manifest not found: $local_manifest" >&2; exit 2; }
[ -n "$upstream_url" ] || upstream_url="https://raw.githubusercontent.com/kaizen-agents-org/.github/$upstream_ref/onboarding/versions.json"

for required in node curl; do
  command -v "$required" >/dev/null 2>&1 || { echo "error: $required must be installed" >&2; exit 2; }
done

upstream_file=$(mktemp)
trap 'rm -f "$upstream_file"' EXIT
# Bounded: this runs unattended on a schedule, so a hung upstream must not
# occupy the job indefinitely.
if ! curl -fsSL --connect-timeout 10 --max-time 60 "$upstream_url" -o "$upstream_file"; then
  echo "error: could not read the upstream manifest: $upstream_url" >&2
  exit 1
fi

# Compare the two manifests. Exit 0 with no output when they agree; print a
# summary line per differing component when they do not.
summary=$(LOCAL="$local_manifest" UPSTREAM="$upstream_file" node -e '
  const fs = require("node:fs");
  const components = ["kaizen-loop", "builder-agent", "verifier"];
  const read = (file, label) => {
    let parsed;
    try {
      parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
      console.error(`error: ${label} manifest is not valid JSON: ${error.message}`);
      process.exit(2);
    }
    for (const component of components) {
      const value = parsed?.[component];
      if (typeof value !== "string" || !/^v0\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) {
        console.error(`error: ${label} manifest does not pin ${component} to a v0.x.y tag`);
        process.exit(2);
      }
    }
    return parsed;
  };
  const local = read(process.env.LOCAL, "installed");
  const upstream = read(process.env.UPSTREAM, "upstream");
  const changed = components.filter((c) => local[c] !== upstream[c]);
  if (changed.length === 0) process.exit(0);
  for (const component of changed) {
    process.stdout.write(`- ${component}: ${local[component]} -> ${upstream[component]}\n`);
  }
') || {
  status=$?
  [ "$status" -eq 2 ] && exit 2
  exit "$status"
}

if [ -z "$summary" ]; then
  echo "The installed Kaizen toolchain matches the upstream pinned set."
  exit 0
fi

echo "A newer pinned Kaizen toolchain set is available:"
echo "$summary"

# One open notification at a time. Re-notifying every week for the same set
# would train the owner to ignore it.
title="Kaizen toolchain update available"
if [ "$dry_run" -eq 1 ]; then
  echo
  echo "Dry run: would ensure an open issue titled \"$title\" on $repo."
  exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "error: gh must be installed to open the issue" >&2; exit 2; }

# Distinguish "query failed" from "no open notification". Swallowing the failure
# would let expired auth or rate limiting look like an empty result and open a
# duplicate issue on every scheduled run.
if ! existing=$(gh issue list --repo "$repo" --state open --search "\"$title\" in:title" \
  --json number,title --jq "[.[] | select(.title == \"$title\")] | .[0].number" 2>&1); then
  echo "error: could not check for an existing notification issue on $repo" >&2
  printf '%s\n' "$existing" >&2
  echo "error: refusing to open an issue that might duplicate one already there." >&2
  exit 1
fi

body=$(cat <<EOF
A newer pinned Kaizen toolchain set is available upstream.

$summary

To follow it, re-run the onboarding command from a checkout of this repository
with \`--refresh-manifest\`:

\`\`\`sh
onboarding/onboard.sh --profile <your-profile> --refresh-manifest
\`\`\`

\`--refresh-manifest\` is required. Without it the run reads the pinned set
already recorded in this repository and would reinstall the versions you have
now, not the ones above.

Re-running is otherwise the supported update path: steps that are already done
are skipped, the pinned components move to the set above, and the onboarding
contract is re-checked afterwards. Commit the updated
\`onboarding/versions.json\` along with anything else the run changes.

This issue was opened by the scheduled Kaizen toolchain update check. Nothing
has been changed in this repository.
EOF
)

if [ -n "$existing" ] && [ "$existing" != "null" ]; then
  echo "Issue #$existing is already open for a toolchain update; not opening another."
  exit 0
fi

gh issue create --repo "$repo" --title "$title" --body "$body"
