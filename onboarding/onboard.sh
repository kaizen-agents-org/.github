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
  echo "manifests in this repository. Review them in .kaizen/config.yml before"
  echo "committing: they decide what counts as a verified change here."
  confirm "Generate .kaizen/config.yml with profile '$profile'?" || {
    echo "Stopped before writing any configuration."
    exit 1
  }
fi

# ------------------------------------------------------------------- 3. init
step "3/8 Initialize Kaizen in this repository"
if [ -f .kaizen/config.yml ]; then
  echo "Configuration already present; skipping kaizen init."
else
  kaizen init --profile "$profile"
  echo
  echo "Review the generated commands now:"
  echo "  \$EDITOR .kaizen/config.yml"
fi

# ------------------------------------------------------------- 4. protection
step "4/8 Apply branch protection"
if [ "$skip_protection" -eq 1 ]; then
  echo "Skipped by --skip-protection."
else
  [ -n "$branch" ] || branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || branch=''
  [ -n "$branch" ] || branch=main
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
if [ ! -f "$observations" ] && command -v gh >/dev/null 2>&1; then
  echo "Capturing repository observations..."
  mkdir -p .kaizen
  if ! gh api "repos/$slug/labels?per_page=100" --jq '[.[].name]' > "$observations.labels" 2>/dev/null; then
    echo "warning: could not read labels; capture $observations by hand" >&2
    rm -f "$observations.labels"
  else
    protection_json=$(gh api "repos/$slug/branches/${branch:-main}/protection" 2>/dev/null || printf '{}')
    LABELS_FILE="$observations.labels" PROTECTION_JSON="$protection_json" node -e '
      const fs = require("node:fs");
      const labels = JSON.parse(fs.readFileSync(process.env.LABELS_FILE, "utf8"));
      const protection = JSON.parse(process.env.PROTECTION_JSON);
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
fi

contract_status=0
sh "$script_dir/scripts/check-onboarding-contract.sh" "$repo_root" || contract_status=$?

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
