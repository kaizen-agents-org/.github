#!/bin/sh
# Remove the Kaizen harness from one onboarded repository.
#
# Split by who owns the artifact. Local machine state and scheduled execution
# are ours to remove. Committed files and GitHub state are the adopter's: they
# live in their git history and their repository settings, so this script
# reports them with the exact commands and lets them decide.
#
# Toolchain checkouts are shared by every onboarded repository on the machine,
# so removing them is opt-in rather than implied by uninstalling one project.
set -eu

project=''
assume_yes=0
dry_run=0
remove_toolchain=0

usage() {
  cat >&2 <<'USAGE'
Usage: uninstall-kaizen.sh [--project SLUG] [options]

Run from inside the onboarded repository, or name it with --project.

  --project SLUG      Registry slug to remove. Defaults to the repository in
                      the current directory.
  --dry-run           Print everything that would happen and change nothing.
  --yes               Do not prompt before removing local state.
  --remove-toolchain  Also remove the shared toolchain checkouts and their
                      global links. This affects every onboarded repository on
                      this machine, not just this one.
  --help              Show this message.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || { echo "error: --project requires a value" >&2; exit 2; }; project=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --yes) assume_yes=1; shift ;;
    --remove-toolchain) remove_toolchain=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

command -v node >/dev/null 2>&1 || { echo "error: node must be installed and on PATH" >&2; exit 2; }

kaizen_home=${KAIZEN_HOME:-"$HOME/.kaizen"}
registry="$kaizen_home/registry.json"

# Resolve the slug from the current repository when one was not named, so the
# common case is `cd my-product && uninstall-kaizen.sh`.
if [ -z "$project" ]; then
  command -v git >/dev/null 2>&1 || { echo "error: git must be installed, or pass --project" >&2; exit 2; }
  remote_url=$(git remote get-url origin 2>/dev/null) || {
    echo "error: run from inside the onboarded repository, or pass --project SLUG" >&2
    exit 2
  }
  slug_repo=$(printf '%s' "$remote_url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
  case "$slug_repo" in
    */*) : ;;
    *) echo "error: origin is not a GitHub remote: $remote_url" >&2; exit 2 ;;
  esac
  project=$(printf '%s' "$slug_repo" | tr '/' '-')
fi

say() { printf '%s\n' "$1"; }
plan() { printf '  %s %s\n' "$1" "$2"; }

confirm() {
  [ "$assume_yes" -eq 1 ] && return 0
  if [ ! -t 0 ]; then
    echo "error: $1 requires a terminal; re-run with --yes" >&2
    exit 2
  fi
  printf '%s [y/N] ' "$1"
  read -r reply || reply=''
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Read a field for this project out of the registry, empty when absent.
registry_field() {
  [ -f "$registry" ] || return 0
  REGISTRY="$registry" SLUG="$project" FIELD="$1" node -e '
    const fs = require("node:fs");
    try {
      const data = JSON.parse(fs.readFileSync(process.env.REGISTRY, "utf8"));
      const entry = (data.projects ?? {})[process.env.SLUG];
      if (entry && typeof entry[process.env.FIELD] === "string") {
        process.stdout.write(entry[process.env.FIELD]);
      }
    } catch {}
  ' 2>/dev/null || true
}

registered=$(registry_field repo)
repository_path=$(registry_field localPath)
workspace=$(registry_field workspacePath)
[ -n "$workspace" ] || workspace="$kaizen_home/workspaces/$project"

say "Uninstalling Kaizen for project: $project"
[ -n "$registered" ] && say "Repository:                    $registered"
say "Kaizen home:                   $kaizen_home"
say ""

if [ ! -f "$registry" ] && [ ! -d "$workspace" ]; then
  say "No local Kaizen state found for this project."
  say "Nothing to remove; the repository-side notes below still apply."
  say ""
fi

say "Will remove:"
plan "scheduled jobs" "for $project (launchd or cron)"
[ -f "$registry" ] && plan "registry entry" "$project in $registry"
[ -d "$workspace" ] && plan "workspace" "$workspace"
if [ "$remove_toolchain" -eq 1 ]; then
  plan "toolchain checkouts" "$kaizen_home/toolchain (shared by ALL projects)"
  plan "global links" "kaizen-loop, @kaizen-agents/builder-agent, @verifier/core"
fi
say ""

if [ "$dry_run" -eq 1 ]; then
  say "Dry run: nothing was changed."
  say ""
fi

if [ "$dry_run" -eq 0 ]; then
  if [ "$remove_toolchain" -eq 1 ]; then
    say "--remove-toolchain affects every onboarded repository on this machine."
  fi
  confirm "Remove the local state listed above?" || {
    say "Stopped. Nothing was changed."
    exit 1
  }

  # Reuse the CLI rather than reimplementing plist and crontab handling; it
  # already knows both providers and how to stop a run in progress.
  # Stop execution before discarding the state that identifies it. If the jobs
  # cannot be removed, tearing down the registry entry and workspace would
  # leave automation running against a project nothing knows about any more,
  # and report success while doing it.
  if ! command -v kaizen >/dev/null 2>&1; then
    cat >&2 <<EOF
error: kaizen is not on PATH, so scheduled jobs cannot be removed.

  Stopping before touching local state. Removing the registry entry and
  workspace now would leave launchd or cron jobs running for a project that no
  longer exists locally, behind a successful-looking uninstall.

  Put the toolchain back on PATH and re-run, or stop the jobs first:

    kaizen scheduler disable --project $project
EOF
    exit 1
  fi
  if kaizen scheduler disable --project "$project" >/dev/null 2>&1; then
    say "  removed scheduled jobs"
  else
    say "  no scheduled jobs to remove (or none registered)"
  fi

  if [ -f "$registry" ]; then
    REGISTRY="$registry" SLUG="$project" node -e '
      const fs = require("node:fs");
      const file = process.env.REGISTRY;
      const data = JSON.parse(fs.readFileSync(file, "utf8"));
      if (data.projects && Object.prototype.hasOwnProperty.call(data.projects, process.env.SLUG)) {
        delete data.projects[process.env.SLUG];
        fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
        console.log("  removed the registry entry");
      } else {
        console.log("  no registry entry for this project");
      }
    '
  fi

  if [ -d "$workspace" ]; then
    # Only remove a workspace that sits under this KAIZEN_HOME. A registry can
    # point anywhere, and deleting an arbitrary path because a JSON file named
    # it would be far worse than leaving one behind.
    #
    # Compare canonical paths. A textual prefix check passes for
    # "$kaizen_home/workspaces/../../elsewhere", which resolves outside the home
    # and would then be deleted.
    canonical_workspace=$(cd "$workspace" 2>/dev/null && pwd -P || true)
    canonical_home=$(cd "$kaizen_home" 2>/dev/null && pwd -P || true)
    inside=0
    if [ -n "$canonical_workspace" ] && [ -n "$canonical_home" ]; then
      case "$canonical_workspace" in
        "$canonical_home"/*) inside=1 ;;
      esac
    fi
    if [ "$inside" -eq 1 ]; then
      rm -rf "$canonical_workspace"
      say "  removed the workspace"
    else
      say "  warning: workspace resolves outside $kaizen_home; left in place:" >&2
      say "  warning:   ${canonical_workspace:-$workspace}" >&2
    fi
  fi

  if [ "$remove_toolchain" -eq 1 ]; then
    toolchain_root=$(cd "$kaizen_home/toolchain" 2>/dev/null && pwd -P || true)
    for pkg in kaizen-loop @kaizen-agents/builder-agent @verifier/core; do
      link="$(npm prefix -g 2>/dev/null)/lib/node_modules/$pkg"
      [ -L "$link" ] || continue
      # Only unlink what points into this toolchain. Someone who relinked a
      # package to their own checkout after onboarding should keep that link;
      # the name alone does not make it ours.
      target=$(cd "$link" 2>/dev/null && pwd -P || true)
      case "${target:-}" in
        "$toolchain_root"/*)
          rm -f "$link"
          say "  removed the global link for $pkg"
          ;;
        *)
          say "  kept the global link for $pkg; it points outside this toolchain"
          ;;
      esac
    done
    if [ -n "$toolchain_root" ]; then
      rm -rf "$toolchain_root"
      say "  removed the toolchain checkouts"
    fi
  fi
  say ""
fi

cat <<EOF
Left in place, because they are yours to remove:

  Committed files. They are in your git history, so removing them should be a
  commit you author and review. Run these from the selected repository checkout:

    cd -- "${repository_path:-/path/to/the/selected/repository}"
    rm -f .kaizen/onboarding-observations.json .kaizen/onboarding-observations.json.labels
    git rm -r .kaizen .github/ISSUE_TEMPLATE/kaizen.yml

  Vendored skills, if onboarding added them. Remove only the files the manifest
  records, since your repository may have had its own skills/ beforehand:

    node -e "const m=require('./skills/skills-manifest.json');\\
      console.log(Object.keys(m.files).join(' '))" | xargs git rm
    git rm skills/skills-manifest.json

  Smoke artifacts, which are the JSON files the smoke pass wrote:

    git rm docs/smoke-runs/*.json   # review the directory first

  Repository labels. Deleting a label strips it from every issue that ever
  carried it, including closed ones, so this is deliberate rather than implied:

    gh label list --search kaizen        # review first
    gh label delete kaizen --yes         # repeat per label you want gone

  Branch protection. Removing it is an administrative change to how the
  repository accepts changes, and you may want to keep it:

    gh api repos/${registered:-<owner>/<repo>}/branches/main/protection   # review
    # then adjust or delete it in the repository settings

  Issues and pull requests the loop opened. They are project history; close
  them if you want, but nothing here touches them.
EOF

[ "$dry_run" -eq 1 ] && exit 0
say ""
say "Kaizen no longer runs for $project."
