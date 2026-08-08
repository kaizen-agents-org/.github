#!/bin/sh
# Fixture tests for uninstall-kaizen.sh.
#
# kaizen and npm are stubbed on PATH, and every KAIZEN_HOME is a scratch
# directory, so the suite never touches a real installation or scheduler.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
uninstaller="$script_dir/uninstall-kaizen.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $1"; }

bin="$work/bin"
mkdir -p "$bin"
cat > "$bin/kaizen" <<'EOF'
#!/bin/sh
printf 'kaizen %s\n' "$*" >> "$KAIZEN_TEST_LOG"
EOF
cat > "$bin/npm" <<'EOF'
#!/bin/sh
case "$*" in
  "prefix -g") printf '%s\n' "${KAIZEN_TEST_NPM_PREFIX:-/nonexistent}" ;;
esac
EOF
chmod +x "$bin/kaizen" "$bin/npm"

# A KAIZEN_HOME holding one registered project, its workspace, and the shared
# toolchain that other projects would also depend on.
seed_home() {
  home="$work/$1"
  rm -rf "$home"
  mkdir -p "$home/workspaces/example-org-demo" "$home/toolchain/kaizen-loop"
  printf 'marker\n' > "$home/workspaces/example-org-demo/marker"
  SEED_HOME="$home" node -e '
    const fs = require("node:fs");
    const home = process.env.SEED_HOME;
    fs.writeFileSync(`${home}/registry.json`, JSON.stringify({
      version: 1,
      projects: {
        "example-org-demo": {
          repo: "example-org/demo",
          localPath: "/tmp/demo",
          workspacePath: `${home}/workspaces/example-org-demo`,
          schedule: "02:00",
          enabled: true
        },
        "other-org-keep": {
          repo: "other-org/keep",
          localPath: "/tmp/keep",
          workspacePath: `${home}/workspaces/other-org-keep`
        }
      }
    }, null, 2) + "\n");
  '
  printf '%s' "$home"
}

has_project() {
  REGISTRY="$1/registry.json" SLUG="$2" node -e '
    const fs = require("node:fs");
    const d = JSON.parse(fs.readFileSync(process.env.REGISTRY, "utf8"));
    process.exit(Object.prototype.hasOwnProperty.call(d.projects ?? {}, process.env.SLUG) ? 0 : 1);
  ' 2>/dev/null
}

# 1. --dry-run reports the plan and changes nothing.
home=$(seed_home home-dry)
KAIZEN_TEST_LOG="$work/log-dry"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo --dry-run >"$work/out1" 2>&1; then
  grep -q "Dry run: nothing was changed" "$work/out1" \
    && pass "dry run says it changed nothing" \
    || fail "dry run did not report cleanly"
  if has_project "$home" example-org-demo && [ -d "$home/workspaces/example-org-demo" ]; then
    pass "dry run leaves the registry entry and workspace in place"
  else
    fail "dry run removed local state"
  fi
  [ -s "$KAIZEN_TEST_LOG" ] \
    && fail "dry run invoked kaizen" \
    || pass "dry run does not touch the scheduler"
else
  fail "dry run failed: $(cat "$work/out1")"
fi

# 2. A real run removes this project's local state and stops its scheduled jobs.
home=$(seed_home home-real)
KAIZEN_TEST_LOG="$work/log-real"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo --yes >"$work/out2" 2>&1; then
  has_project "$home" example-org-demo \
    && fail "the registry entry survived" \
    || pass "the registry entry is removed"
  [ -d "$home/workspaces/example-org-demo" ] \
    && fail "the workspace survived" \
    || pass "the workspace is removed"
  grep -q "scheduler disable --project example-org-demo" "$KAIZEN_TEST_LOG" \
    && pass "scheduled jobs are stopped through the CLI" \
    || fail "scheduler disable was not invoked (log: $(tr '\n' '|' < "$KAIZEN_TEST_LOG"))"
else
  fail "a real run failed: $(cat "$work/out2")"
fi

# 3. Uninstalling one project must not disturb another. This is the property
#    that makes the shared KAIZEN_HOME safe to use for several repositories.
if has_project "$home" other-org-keep; then
  pass "another project's registry entry is untouched"
else
  fail "uninstalling one project removed another's registry entry"
fi

# 4. The shared toolchain survives unless it is explicitly opted into, so
#    uninstalling one repository does not break every other one on the machine.
if [ -d "$home/toolchain/kaizen-loop" ]; then
  pass "the shared toolchain survives a normal uninstall"
else
  fail "a normal uninstall removed the shared toolchain"
fi

# 5. --remove-toolchain removes the checkouts and the global links.
home=$(seed_home home-toolchain)
prefix="$work/npmprefix"
mkdir -p "$prefix/lib/node_modules/@kaizen-agents" "$prefix/lib/node_modules/@verifier"
mkdir -p "$home/toolchain/kaizen-loop" "$home/toolchain/verifier/packages/core"
ln -s "$home/toolchain/kaizen-loop" "$prefix/lib/node_modules/kaizen-loop"
ln -s "$home/toolchain/verifier/packages/core" "$prefix/lib/node_modules/@verifier/core"
KAIZEN_TEST_LOG="$work/log-tc"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" KAIZEN_TEST_NPM_PREFIX="$prefix" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo --yes --remove-toolchain >"$work/out5" 2>&1; then
  [ -d "$home/toolchain" ] \
    && fail "--remove-toolchain left the checkouts behind" \
    || pass "--remove-toolchain removes the toolchain checkouts"
  if [ -L "$prefix/lib/node_modules/kaizen-loop" ] ||
     [ -L "$prefix/lib/node_modules/@verifier/core" ]; then
    fail "--remove-toolchain left a global link behind"
  else
    pass "--remove-toolchain removes the global links"
  fi
else
  fail "--remove-toolchain run failed: $(cat "$work/out5")"
fi

# 6. A workspace path outside KAIZEN_HOME is reported, never deleted. A registry
#    can name any path, and deleting one because a JSON file said so would be
#    far worse than leaving it behind.
home=$(seed_home home-outside)
mkdir -p "$work/precious"
printf 'do not delete\n' > "$work/precious/important.txt"
OUTSIDE_HOME="$home" OUTSIDE_PATH="$work/precious" node -e '
  const fs = require("node:fs");
  const file = `${process.env.OUTSIDE_HOME}/registry.json`;
  const d = JSON.parse(fs.readFileSync(file, "utf8"));
  d.projects["example-org-demo"].workspacePath = process.env.OUTSIDE_PATH;
  fs.writeFileSync(file, JSON.stringify(d, null, 2) + "\n");
'
KAIZEN_TEST_LOG="$work/log-outside"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo --yes >"$work/out6" 2>&1; then
  if [ -f "$work/precious/important.txt" ]; then
    pass "a workspace outside KAIZEN_HOME is preserved"
  else
    fail "a workspace outside KAIZEN_HOME was deleted"
  fi
  grep -q "resolves outside" "$work/out6" \
    && pass "the preserved workspace is reported" \
    || fail "preserving the outside workspace was silent"
else
  fail "run with an outside workspace failed: $(cat "$work/out6")"
fi

# 7. Re-running after removal succeeds, so a partial or repeated uninstall is
#    not a dead end.
KAIZEN_TEST_LOG="$work/log-again"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo --yes >"$work/out7" 2>&1; then
  pass "re-running after removal succeeds"
else
  fail "re-running after removal failed: $(cat "$work/out7")"
fi

# 8. Repository-side artifacts are always reported, never removed.
grep -q "git rm -r .kaizen" "$work/out7" \
  && pass "committed files are reported with the command to remove them" \
  || fail "the committed-file note is missing"
grep -q "rm -f .kaizen/onboarding-observations.json" "$work/out7" \
  && pass "ignored observations are reported with an explicit removal command" \
  || fail "the ignored-observation removal command is missing"
grep -q "gh label delete" "$work/out7" \
  && pass "labels are reported rather than deleted" \
  || fail "the label note is missing"

# 9. Without a terminal and without --yes, a destructive run refuses rather
#    than assuming consent.
home=$(seed_home home-noyes)
KAIZEN_TEST_LOG="$work/log-noyes"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo </dev/null >"$work/out9" 2>&1; then
  fail "a non-interactive run removed state without --yes"
else
  grep -q "requires a terminal" "$work/out9" \
    && pass "a non-interactive run without --yes is refused" \
    || fail "non-interactive refusal gave the wrong message"
  has_project "$home" example-org-demo \
    && pass "the refused run changed nothing" \
    || fail "the refused run still removed the registry entry"
fi

# 10. A slug containing .. must not escape KAIZEN_HOME. A textual prefix check
#     passes for "$home/workspaces/../../victim", which resolves outside the
#     home and would then be deleted.
home=$(seed_home home-traversal)
mkdir -p "$work/victim"
printf 'must survive\n' > "$work/victim/data.txt"
victim_name=$(basename "$work/victim")
KAIZEN_TEST_LOG="$work/log-trav"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
KAIZEN_HOME="$home" PATH="$bin:$PATH" \
  sh "$uninstaller" --project "../../$victim_name" --yes >"$work/out10" 2>&1 || true
if [ -f "$work/victim/data.txt" ]; then
  pass "a slug with .. cannot delete a directory outside KAIZEN_HOME"
else
  fail "path traversal via --project deleted an outside directory"
fi
grep -q "resolves outside" "$work/out10" \
  && pass "the escaped path is reported" \
  || fail "the traversal attempt was silent"

# 11. Without kaizen on PATH the scheduled jobs cannot be stopped, so the run
#     must abort rather than delete the state that identifies them and report
#     success while automation keeps firing.
home=$(seed_home home-nokaizen)
nokaizen="$work/bin-nokaizen"
mkdir -p "$nokaizen"
cp "$bin/npm" "$nokaizen/npm"
# node is a hard prerequisite checked before anything else, so keep it
# reachable; this fixture is about kaizen being absent, not node.
ln -sf "$(command -v node)" "$nokaizen/node"
KAIZEN_TEST_LOG="$work/log-nok"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" PATH="$nokaizen:/usr/bin:/bin" \
     sh "$uninstaller" --project example-org-demo --yes >"$work/out11" 2>&1; then
  fail "the uninstall reported success without stopping scheduled jobs"
else
  grep -q "kaizen is not on PATH" "$work/out11" \
    && pass "a missing kaizen aborts the uninstall" \
    || fail "the abort message was missing"
  if has_project "$home" example-org-demo && [ -d "$home/workspaces/example-org-demo" ]; then
    pass "the aborted run left local state intact"
  else
    fail "the aborted run still discarded local state"
  fi
fi

# 12. --remove-toolchain must not unlink a package someone relinked to their
#     own checkout after onboarding; the package name alone does not make the
#     link ours.
home=$(seed_home home-foreign)
prefix2="$work/npmprefix-foreign"
mkdir -p "$prefix2/lib/node_modules" "$work/their-own-checkout"
ln -s "$work/their-own-checkout" "$prefix2/lib/node_modules/kaizen-loop"
KAIZEN_TEST_LOG="$work/log-foreign"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if KAIZEN_HOME="$home" KAIZEN_TEST_NPM_PREFIX="$prefix2" PATH="$bin:$PATH" \
     sh "$uninstaller" --project example-org-demo --yes --remove-toolchain >"$work/out12" 2>&1; then
  if [ -L "$prefix2/lib/node_modules/kaizen-loop" ]; then
    pass "a global link pointing outside this toolchain is kept"
  else
    fail "--remove-toolchain unlinked a package it does not own"
  fi
  grep -q "points outside this toolchain" "$work/out12" \
    && pass "keeping the foreign link is reported" \
    || fail "keeping the foreign link was silent"
else
  fail "--remove-toolchain with a foreign link failed: $(cat "$work/out12")"
fi

# 13. The reported cleanup commands must not tell an adopter to delete
#     directories wholesale; a repository can have had its own skills/ before
#     onboarding vendored into it.
if grep -q "git rm -r skills" "$work/out12"; then
  fail "the notes still recommend removing the whole skills directory"
else
  pass "vendored skills are derived from the manifest, not removed wholesale"
fi
grep -q "skills-manifest.json" "$work/out12" \
  && pass "the notes point at the manifest for the vendored file list" \
  || fail "the manifest-derived removal command is missing"

echo
if [ "$failures" -gt 0 ]; then
  echo "uninstall-kaizen fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All uninstall-kaizen fixtures passed."
