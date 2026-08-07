#!/bin/sh
# Adopt the Kaizen harness in the repository you run this from.
#
# Re-running is the supported update path. Every step detects work that is
# already done and skips it, so the same command onboards a fresh repository
# and follows a newer pinned toolchain.
#
# Three points ask for confirmation, because each one is a decision the adopter
# owns rather than a mechanical step:
#   1. the verification commands  - they define what "verified" means here
#   2. branch protection          - it uses repository admin rights
#   3. the smoke run              - it opens a real issue and pull request
set -eu

profile=''
assume_yes=0
skip_protection=0
skip_smoke=0
branch=''
check_name=''
manifest=''
refresh_manifest=0
upstream_ref=${KAIZEN_ONBOARDING_REF:-main}
upstream_manifest_url=''

usage() {
  cat >&2 <<'USAGE'
Usage: onboard.sh [options]

Run from inside the repository you want to onboard.

  --profile NAME       Onboarding profile (pilot-node, pilot-python, pilot-go,
                       pilot-rust, standard). Required with --yes.
  --yes                Non-interactive: accept detected commands and run every
                       step without prompting. Requires --profile.
  --branch NAME        Default branch for protection (default: origin's HEAD).
  --check NAME         Required status-check context for protection.
  --manifest FILE      Version manifest (default: onboarding/versions.json).
  --refresh-manifest   Fetch the upstream pinned set before installing, so a
                       re-run follows a newer release instead of reinstalling
                       the set already recorded locally.
  --ref REF            Upstream ref to refresh the manifest from (default: main).
  --skip-protection    Do not apply branch protection.
  --skip-smoke         Do not run the smoke pass. The onboarding contract is
                       not satisfied without a smoke artifact.
  --help               Show this message.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) [ "$#" -ge 2 ] || { echo "error: --profile requires a value" >&2; exit 2; }; profile=$2; shift 2 ;;
    --branch) [ "$#" -ge 2 ] || { echo "error: --branch requires a value" >&2; exit 2; }; branch=$2; shift 2 ;;
    --check) [ "$#" -ge 2 ] || { echo "error: --check requires a value" >&2; exit 2; }; check_name=$2; shift 2 ;;
    --manifest) [ "$#" -ge 2 ] || { echo "error: --manifest requires a value" >&2; exit 2; }; manifest=$2; shift 2 ;;
    --refresh-manifest) refresh_manifest=1; shift ;;
    --ref) [ "$#" -ge 2 ] || { echo "error: --ref requires a value" >&2; exit 2; }; upstream_ref=$2; shift 2 ;;
    --upstream-manifest-url) [ "$#" -ge 2 ] || { echo "error: --upstream-manifest-url requires a value" >&2; exit 2; }; upstream_manifest_url=$2; shift 2 ;;
    --yes) assume_yes=1; shift ;;
    --skip-protection) skip_protection=1; shift ;;
    --skip-smoke) skip_smoke=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$assume_yes" -eq 1 ] && [ -z "$profile" ]; then
  echo "error: --yes requires --profile, so an unattended run cannot pick a throughput policy by itself" >&2
  exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -n "$manifest" ] || manifest="$script_dir/versions.json"

# This script is not self-bootstrapping: it needs versions.json, profiles/, and
# its sibling scripts. Piping it from curl would resolve script_dir into the
# target repository and fail confusingly on the first missing file, so say so
# once, up front.
for required_asset in "$script_dir/versions.json" "$script_dir/profiles" "$script_dir/scripts"; do
  [ -e "$required_asset" ] && continue
  cat >&2 <<EOF
error: onboarding assets are missing next to this script

  Expected: $required_asset

  Run onboard.sh from a checkout of kaizen-agents-org/.github, pointed at the
  repository you are onboarding:

    git clone https://github.com/kaizen-agents-org/.github kaizen-onboarding
    cd /path/to/your-repository
    sh /path/to/kaizen-onboarding/onboarding/onboard.sh

  Piping this script from curl does not work; it cannot fetch its own assets.
EOF
  exit 2
done

step() {
  echo
  echo "== $1"
}

# Ask a yes/no question. Under --yes every answer is yes; with no terminal
# attached the run stops rather than guessing.
confirm() {
  prompt=$1
  if [ "$assume_yes" -eq 1 ]; then
    echo "$prompt [auto-confirmed by --yes]"
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "error: $prompt requires a terminal; re-run with --yes to accept non-interactively" >&2
    exit 2
  fi
  printf '%s [y/N] ' "$prompt"
  read -r reply || reply=''
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

command -v git >/dev/null 2>&1 || { echo "error: git must be installed" >&2; exit 2; }
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "error: run onboard.sh from inside the repository you want to onboard" >&2
  exit 2
}
cd "$repo_root"

remote_url=$(git remote get-url origin 2>/dev/null) || {
  echo "error: this repository has no origin remote" >&2
  exit 2
}
slug=$(printf '%s' "$remote_url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
case "$slug" in
  */*) : ;;
  *) echo "error: origin is not a GitHub remote: $remote_url" >&2; exit 2 ;;
esac

echo "Onboarding repository: $slug"
echo "Checkout:              $repo_root"
echo "Manifest:              $manifest"

# ---------------------------------------------------------------- 1. toolchain
step "1/8 Install or update the pinned toolchain"
# Without this, a re-run reinstalls whatever the local manifest already pins, so
# an adopter told that a newer set exists could never actually reach it.
if [ "$refresh_manifest" -eq 1 ]; then
  [ -n "$upstream_manifest_url" ] || upstream_manifest_url="https://raw.githubusercontent.com/kaizen-agents-org/.github/$upstream_ref/onboarding/versions.json"
  command -v curl >/dev/null 2>&1 || { echo "error: --refresh-manifest requires curl" >&2; exit 2; }
  echo "Refreshing the pinned set from $upstream_manifest_url"
  refreshed=$(mktemp)
  if ! curl -fsSL --connect-timeout 10 --max-time 60 "$upstream_manifest_url" -o "$refreshed"; then
    rm -f "$refreshed"
    echo "error: could not read the upstream manifest: $upstream_manifest_url" >&2
    exit 1
  fi
  # Validate before overwriting: a truncated or malformed download must not
  # replace a working manifest.
  if ! MANIFEST="$refreshed" node -e '
    const fs = require("node:fs");
    const manifest = JSON.parse(fs.readFileSync(process.env.MANIFEST, "utf8"));
    for (const component of ["kaizen-loop", "builder-agent", "verifier"]) {
      const value = manifest?.[component];
      if (typeof value !== "string" || !/^v0\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) {
        throw new Error(`upstream manifest does not pin ${component} to a v0.x.y tag`);
      }
    }
  ' 2>/dev/null; then
    rm -f "$refreshed"
    echo "error: the upstream manifest is not a valid pinned set; keeping the local one" >&2
    exit 1
  fi
  if cmp -s "$refreshed" "$manifest"; then
    echo "Already on the upstream pinned set."
    rm -f "$refreshed"
  else
    cat "$refreshed" > "$manifest"
    rm -f "$refreshed"
    echo "Updated $manifest to the upstream pinned set. Commit it with the rest of the run."
  fi
fi
sh "$script_dir/scripts/install-kaizen.sh" --manifest "$manifest"

# ------------------------------------------------------- 2. detect and confirm
step "2/8 Propose setup and verification commands"
if [ -f .kaizen/config.yml ]; then
  echo ".kaizen/config.yml already exists; keeping its commands."
  echo "Edit it directly to change what verification runs."
else
  if [ -z "$profile" ]; then
    echo "Available profiles:"
    for candidate in "$script_dir"/profiles/*.yml; do
      [ -e "$candidate" ] || continue
      name=$(basename "$candidate" .yml)
      echo "  - $name"
    done
    if [ ! -t 0 ]; then
      echo "error: no --profile given and no terminal to ask on" >&2
      exit 2
    fi
    printf 'Profile: '
    read -r profile || profile=''
    [ -n "$profile" ] || { echo "error: a profile is required" >&2; exit 2; }
  fi
  echo "Using profile: $profile"
  echo
  echo "kaizen init will propose setup and verification commands from the"
  echo "manifests in this repository. You approve them in the next step, once"
  echo "they exist and can actually be read."
fi

# ------------------------------------------------------------------- 3. init
step "3/8 Initialize Kaizen in this repository"
if [ -f .kaizen/config.yml ]; then
  echo "Configuration already present; skipping kaizen init."
else
  kaizen init --profile "$profile"
  echo
  # The approval that matters is this one, not the one before generation: these
  # are the commands the smoke run and every later run will execute, and they
  # did not exist until now.
  echo "Generated verification commands for this repository:"
  if command -v node >/dev/null 2>&1; then
    CONFIG=.kaizen/config.yml node -e '
      const fs = require("node:fs");
      const text = fs.readFileSync(process.env.CONFIG, "utf8");
      const lines = text.split("\n");
      const start = lines.findIndex((line) => /^commands:/.test(line));
      if (start === -1) { console.log("  (none found; review .kaizen/config.yml)"); process.exit(0); }
      for (const line of lines.slice(start, start + 12)) {
        if (line && !/^\s/.test(line) && !/^commands:/.test(line)) break;
        console.log(`  ${line}`);
      }
    ' 2>/dev/null || sed -n '/^commands:/,/^[a-z]/p' .kaizen/config.yml
  else
    sed -n '/^commands:/,/^[a-z]/p' .kaizen/config.yml
  fi
  echo
  echo "These decide what counts as a verified change here. Edit"
  echo ".kaizen/config.yml in another terminal now if they are wrong."
  confirm "Accept these verification commands?" || {
    echo "Stopped. Edit .kaizen/config.yml and re-run this command; the"
    echo "generated configuration is kept, so the re-run picks it up."
    exit 1
  }
fi

# ------------------------------------------------------------- 4. protection
step "4/8 Apply branch protection"
# Resolve the branch even when protection application is skipped: the final
# observation must inspect the repository's actual default branch rather than
# silently assuming main.
[ -n "$branch" ] || branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || branch=''
if [ -z "$branch" ] && [ "$skip_protection" -eq 1 ] && command -v gh >/dev/null 2>&1; then
  if ! branch=$(gh api "repos/$slug" --jq '.default_branch' 2>/dev/null); then
    echo "error: could not resolve the repository default branch" >&2
    exit 1
  fi
  if [ -z "$branch" ]; then
    echo "error: GitHub returned no repository default branch" >&2
    exit 1
  fi
fi
[ -n "$branch" ] || branch=main
if [ "$skip_protection" -eq 1 ]; then
  echo "Skipped by --skip-protection."
else
  if [ -z "$check_name" ]; then
    if [ "$assume_yes" -eq 1 ]; then
      echo "error: --check is required with --yes so protection names a real status check" >&2
      exit 2
    fi
    printf 'Required status-check context (e.g. test): '
    read -r check_name || check_name=''
    [ -n "$check_name" ] || { echo "error: a status-check name is required" >&2; exit 2; }
  fi
  echo "This uses repository administrator rights on $slug ($branch)."
  if confirm "Apply the standard branch protection to $slug@$branch?"; then
    sh "$script_dir/scripts/apply-branch-protection.sh" \
      --repo "$slug" --branch "$branch" --check "$check_name"
  else
    echo "Skipped branch protection. The onboarding contract will report it as missing."
  fi
fi

# -------------------------------------------------------------- 5. scheduler
step "5/8 Register the scheduled runs"
# kaizen init writes the job definitions into .kaizen/config.yml but does not
# register them with launchd or cron, so without this the loop would never run
# on its own.
kaizen scheduler sync || {
  echo "error: could not register the scheduled jobs; fix the problem above and re-run" >&2
  exit 1
}

# ----------------------------------------------------------------- 6. doctor
step "6/8 Check the local setup"
kaizen doctor --repair || {
  echo "error: kaizen doctor reported problems; fix them and re-run onboard.sh" >&2
  exit 1
}

# ------------------------------------------------------------------ 7. smoke
step "7/8 Run the acceptance smoke pass"
if [ "$skip_smoke" -eq 1 ]; then
  echo "Skipped by --skip-smoke."
elif ls docs/smoke-runs/*.json >/dev/null 2>&1; then
  echo "A smoke artifact already exists under docs/smoke-runs/; skipping."
  echo "Delete it and re-run to force a fresh smoke pass."
else
  echo "The smoke pass creates a real sandbox issue and pull request on $slug."
  if confirm "Run the smoke pass now?"; then
    kaizen smoke --yes
  else
    echo "Skipped the smoke pass. The onboarding contract needs an artifact to pass."
  fi
fi

# --------------------------------------------------------------- 8. contract
step "8/8 Check the onboarding contract"
observations=.kaizen/onboarding-observations.json
# Always recapture. Keeping an earlier snapshot means a maintainer who fixes the
# labels or protection it reported as missing would see the same failure
# forever, which contradicts the resume-and-re-run path this script promises.
# The snapshot is read-only GitHub state, so re-reading it costs two API calls.
if command -v gh >/dev/null 2>&1; then
  echo "Capturing repository observations..."
  mkdir -p .kaizen
  if ! gh api "repos/$slug/labels?per_page=100" --jq '[.[].name]' > "$observations.labels" 2>/dev/null; then
    echo "warning: could not read labels; capture $observations by hand" >&2
    rm -f "$observations.labels"
  else
    # An unprotected branch is the normal state for a repository being
    # onboarded, and `gh api` reports it by writing a 404 body to *stdout* and
    # exiting non-zero. Discarding only stderr would concatenate that body with
    # the fallback and produce JSON that cannot be parsed, so capture stdout
    # separately and fall back only when the call actually failed.
    if protection_json=$(gh api "repos/$slug/branches/${branch:-main}/protection" 2>/dev/null); then
      :
    elif PROTECTION_JSON="$protection_json" node -e '
      let response;
      try {
        response = JSON.parse(process.env.PROTECTION_JSON);
      } catch {
        process.exit(1);
      }
      process.exit(
        String(response.status) === "404" && response.message === "Branch not protected" ? 0 : 1
      );
    '; then
      protection_json='{}'
    else
      echo "error: could not read branch protection; check GitHub authentication, permissions, and API availability" >&2
      exit 1
    fi
    LABELS_FILE="$observations.labels" PROTECTION_JSON="$protection_json" node -e '
      const fs = require("node:fs");
      const labels = JSON.parse(fs.readFileSync(process.env.LABELS_FILE, "utf8"));
      let protection;
      try {
        protection = JSON.parse(process.env.PROTECTION_JSON);
      } catch {
        console.error("error: branch protection API returned malformed JSON");
        process.exit(1);
      }
      if (protection === null || typeof protection !== "object" || Array.isArray(protection)) {
        console.error("error: branch protection API returned an invalid payload");
        process.exit(1);
      }
      const checks = protection.required_status_checks ?? {};
      process.stdout.write(JSON.stringify({
        labels,
        branchProtection: {
          requiredStatusChecks: {
            strict: checks.strict === true,
            contexts: Array.isArray(checks.contexts) ? checks.contexts : []
          },
          requiredConversationResolution:
            protection.required_conversation_resolution?.enabled === true,
          enforceAdmins: protection.enforce_admins?.enabled === true
        }
      }, null, 2) + "\n");
    ' > "$observations"
    rm -f "$observations.labels"
  fi
elif [ -f "$observations" ]; then
  echo "warning: gh is unavailable, so $observations was not refreshed." >&2
  echo "warning: the contract below is judged against a possibly stale snapshot." >&2
fi

contract_status=0
# The checker validates vendored skills against the pinned toolchain, so it
# needs the manifest this run installed from. It only demands a skill bundle
# manifest once the target actually has skills/skills-manifest.json; pass one
# when the installed toolchain exports it so that path is satisfied rather than
# failing the moment skills vendoring lands.
set -- "$repo_root" --toolchain-manifest "$manifest"
if [ -f "$repo_root/skills/skills-manifest.json" ]; then
  bundle_manifest=${KAIZEN_SKILL_BUNDLE_MANIFEST:-}
  if [ -z "$bundle_manifest" ]; then
    kaizen_bin=$(command -v kaizen 2>/dev/null || true)
    if [ -n "$kaizen_bin" ]; then
      kaizen_root=$(CDPATH= cd -- "$(dirname -- "$(dirname -- "$(readlink -f "$kaizen_bin" 2>/dev/null || printf '%s' "$kaizen_bin")")")" && pwd)
      [ -f "$kaizen_root/skills/skills-manifest.json" ] && bundle_manifest="$kaizen_root/skills/skills-manifest.json"
    fi
  fi
  if [ -n "$bundle_manifest" ] && [ -f "$bundle_manifest" ]; then
    set -- "$@" --skill-bundle-manifest "$bundle_manifest"
  else
    echo "warning: this repository vendors skills but no pinned skill bundle manifest was found." >&2
    echo "warning: set KAIZEN_SKILL_BUNDLE_MANIFEST to the manifest exported by the installed toolchain." >&2
  fi
fi
sh "$script_dir/scripts/check-onboarding-contract.sh" "$@" || contract_status=$?

echo
if [ "$contract_status" -eq 0 ]; then
  cat <<EOF
Onboarding complete for $slug.

Next:
  1. Commit .kaizen/config.yml, .github/ISSUE_TEMPLATE/kaizen.yml, and the
     smoke artifact under docs/smoke-runs/.
  2. Open a Kaizen issue and let the scheduled run pick it up, or run
     'kaizen fix <issue>' to process one now.

Re-run this same command to follow a newer pinned toolchain.
EOF
else
  cat <<EOF
Onboarding is not complete yet: the contract check above lists what is missing,
each with a remediation line. Fix those and re-run this same command; finished
steps are skipped.
EOF
  exit "$contract_status"
fi
