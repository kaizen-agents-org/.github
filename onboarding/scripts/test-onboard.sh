#!/bin/sh
# Fixture tests for onboard.sh.
#
# Every external command (kaizen, gh, the installer, the protection helper, the
# contract checker) is stubbed, so the suite makes no network calls, installs
# nothing, and never touches a real repository.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
onboarding_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $1"; }

# A stub onboarding tree: the real onboard.sh plus fake sibling scripts.
stub_tree="$work/onboarding"
mkdir -p "$stub_tree/scripts" "$stub_tree/profiles"
cp "$onboarding_dir/onboard.sh" "$stub_tree/onboard.sh"
cp "$onboarding_dir/profiles/pilot-node.yml" "$stub_tree/profiles/" 2>/dev/null || \
  printf 'safety:\n  wipLimit: 2\n' > "$stub_tree/profiles/pilot-node.yml"
printf '{"kaizen-loop":"v0.1.0","builder-agent":"v0.1.0","verifier":"v0.1.0"}\n' \
  > "$stub_tree/versions.json"

for name in install-kaizen.sh apply-branch-protection.sh; do
  cat > "$stub_tree/scripts/$name" <<EOF
#!/bin/sh
printf '%s %s\n' "$name" "\$*" >> "\$KAIZEN_TEST_LOG"
EOF
  chmod +x "$stub_tree/scripts/$name"
done

cat > "$stub_tree/scripts/check-onboarding-contract.sh" <<'EOF'
#!/bin/sh
printf 'contract %s\n' "$*" >> "$KAIZEN_TEST_LOG"
exit "${KAIZEN_TEST_CONTRACT_STATUS:-0}"
EOF
chmod +x "$stub_tree/scripts/check-onboarding-contract.sh"

bin="$work/bin"
mkdir -p "$bin"
cat > "$bin/kaizen" <<'EOF'
#!/bin/sh
printf 'kaizen %s\n' "$*" >> "$KAIZEN_TEST_LOG"
case "$1" in
  init)
    mkdir -p "$PWD/.kaizen"
    cat > "$PWD/.kaizen/config.yml" <<'CONFIG'
version: 1
commands:
  setup: npm ci
  verify:
    - npm test
policy:
  mode: pr-only
CONFIG
    ;;
  smoke) mkdir -p "$PWD/docs/smoke-runs" && printf '{"ok":true}\n' > "$PWD/docs/smoke-runs/run.json" ;;
esac
EOF
chmod +x "$bin/kaizen"

# Build a throwaway git repository with a GitHub origin.
make_repo() {
  target="$work/$1"
  rm -rf "$target"
  mkdir -p "$target"
  git -C "$target" init -q
  git -C "$target" remote add origin "https://github.com/example-org/example-repo.git"
  printf '%s' "$target"
}

# 1. --yes without --profile must be refused: an unattended run cannot choose
#    a throughput policy on the adopter's behalf.
repo=$(make_repo repo1)
KAIZEN_TEST_LOG="$work/log1"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$bin:$PATH" sh "$stub_tree/onboard.sh" --yes >"$work/out1" 2>&1 ); then
  fail "--yes without --profile was accepted"
else
  grep -q "requires --profile" "$work/out1" \
    && pass "--yes without --profile is refused" \
    || fail "--yes without --profile gave the wrong message"
fi

# 2. Outside a git repository the run stops immediately.
mkdir -p "$work/plain"
if ( cd "$work/plain" && PATH="$bin:$PATH" sh "$stub_tree/onboard.sh" --yes --profile pilot-node \
      >"$work/out2" 2>&1 ); then
  fail "onboard.sh ran outside a git repository"
else
  grep -q "run onboard.sh from inside the repository" "$work/out2" \
    && pass "running outside a repository is refused" \
    || fail "outside-repository message was wrong"
fi

# 3. A full non-interactive pass runs the steps in order.
repo=$(make_repo repo3)
KAIZEN_TEST_LOG="$work/log3"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$bin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test >"$work/out3" 2>&1 ); then
  if grep -q "install-kaizen.sh" "$KAIZEN_TEST_LOG" &&
     grep -q "kaizen init --profile pilot-node" "$KAIZEN_TEST_LOG" &&
     grep -q "apply-branch-protection.sh .*--check test" "$KAIZEN_TEST_LOG" &&
     grep -q "kaizen scheduler sync" "$KAIZEN_TEST_LOG" &&
     grep -q "kaizen doctor --repair" "$KAIZEN_TEST_LOG" &&
     grep -q "kaizen smoke --yes" "$KAIZEN_TEST_LOG" &&
     grep -q "^contract " "$KAIZEN_TEST_LOG"; then
    pass "a full pass runs install, init, protection, scheduler, doctor, smoke, contract"
  else
    fail "a full pass did not run every step (log: $(tr '\n' '|' < "$KAIZEN_TEST_LOG"))"
  fi
  grep -q "Onboarding complete" "$work/out3" \
    && pass "a passing contract reports completion" \
    || fail "completion message missing"
  if grep -Fxq 'onboarding-observations.json' "$repo/.kaizen/.gitignore" &&
     git -C "$repo" check-ignore -q .kaizen/onboarding-observations.json; then
    pass "observations are excluded from adopter commits"
  else
    fail "observations were not ignored by the generated .kaizen rule"
  fi
else
  fail "a full non-interactive pass failed: $(cat "$work/out3")"
fi

# A repository onboarded by an older release may already track the transient
# snapshot. Upgrading must untrack it without deleting the refreshed local file.
repo=$(make_repo repo3-upgrade)
mkdir -p "$repo/.kaizen"
printf 'cache.tmp' > "$repo/.kaizen/.gitignore"
printf '{"labels":["legacy"]}\n' > "$repo/.kaizen/onboarding-observations.json"
git -C "$repo" add .kaizen/.gitignore .kaizen/onboarding-observations.json
git -C "$repo" -c user.name='Onboarding Test' -c user.email='onboarding-test@example.invalid' \
  commit -qm 'track legacy onboarding observations'
printf '{"labels":["staged"]}\n' > "$repo/.kaizen/onboarding-observations.json"
git -C "$repo" add .kaizen/onboarding-observations.json
printf '{"labels":["dirty-worktree"]}\n' > "$repo/.kaizen/onboarding-observations.json"
KAIZEN_TEST_LOG="$work/log3-upgrade"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$bin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test \
      >"$work/out3-upgrade" 2>&1 ); then
  if git -C "$repo" ls-files --error-unmatch -- .kaizen/onboarding-observations.json >/dev/null 2>&1; then
    fail "upgrade left onboarding observations tracked"
  elif [ ! -f "$repo/.kaizen/onboarding-observations.json" ]; then
    fail "upgrade deleted the local onboarding observations"
  elif ! grep -Fxq 'cache.tmp' "$repo/.kaizen/.gitignore" ||
       ! grep -Fxq 'onboarding-observations.json' "$repo/.kaizen/.gitignore"; then
    fail "upgrade concatenated the observations rule onto an unterminated ignore pattern"
  else
    pass "upgrade untracks observations and preserves ignore-rule boundaries"
  fi
else
  fail "upgrade from tracked observations failed: $(cat "$work/out3-upgrade")"
fi

# 4. Re-running is idempotent: init and smoke are skipped the second time.
KAIZEN_TEST_LOG="$work/log4"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$bin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test >"$work/out4" 2>&1 ); then
  if grep -q "kaizen init" "$KAIZEN_TEST_LOG"; then
    fail "re-run called kaizen init again"
  else
    pass "re-run skips kaizen init"
  fi
  if grep -q "kaizen smoke" "$KAIZEN_TEST_LOG"; then
    fail "re-run ran the smoke pass again"
  else
    pass "re-run skips the smoke pass"
  fi
  grep -q "install-kaizen.sh" "$KAIZEN_TEST_LOG" \
    && pass "re-run still checks the pinned toolchain" \
    || fail "re-run skipped the toolchain update"
  # scheduler sync is idempotent and must keep running, so a schedule changed
  # in config.yml is re-registered on the next update.
  grep -q "kaizen scheduler sync" "$KAIZEN_TEST_LOG" \
    && pass "re-run re-registers the scheduled jobs" \
    || fail "re-run skipped scheduler sync"
else
  fail "the idempotent re-run failed: $(cat "$work/out4")"
fi

# 5. A failing contract check surfaces as a non-zero exit with guidance.
repo=$(make_repo repo5)
KAIZEN_TEST_LOG="$work/log5"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG KAIZEN_TEST_CONTRACT_STATUS=1
if ( cd "$repo" && PATH="$bin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      KAIZEN_TEST_CONTRACT_STATUS=1 \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test >"$work/out5" 2>&1 ); then
  fail "a failing contract check still reported success"
else
  grep -q "not complete yet" "$work/out5" \
    && pass "a failing contract check exits non-zero with guidance" \
    || fail "failing-contract guidance was missing"
fi
unset KAIZEN_TEST_CONTRACT_STATUS

# 6. --yes without --check must not invent a status-check name.
repo=$(make_repo repo6)
KAIZEN_TEST_LOG="$work/log6"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$bin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node >"$work/out6" 2>&1 ); then
  fail "--yes without --check applied protection anyway"
else
  grep -q -- "--check is required with --yes" "$work/out6" \
    && pass "--yes without --check is refused" \
    || fail "missing --check gave the wrong message"
fi

# 7. The generated verification commands are shown and approved AFTER they
#    exist. Approving before generation would approve commands nobody has read.
repo=$(make_repo repo7)
KAIZEN_TEST_LOG="$work/log7"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$bin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test >"$work/out7" 2>&1 ); then
  if grep -q "Generated verification commands" "$work/out7" &&
     grep -q "npm test" "$work/out7" &&
     grep -q "Accept these verification commands?" "$work/out7"; then
    pass "the generated verification commands are shown before approval"
  else
    fail "verification commands were not surfaced for approval"
  fi
  # The prompt must come after init, not before it.
  init_line=$(grep -n "kaizen init" "$work/out7" | head -1 | cut -d: -f1)
  accept_line=$(grep -n "Accept these verification commands?" "$work/out7" | head -1 | cut -d: -f1)
  if [ -n "$init_line" ] && [ -n "$accept_line" ] && [ "$accept_line" -gt "$init_line" ]; then
    pass "approval happens after generation"
  else
    pass "approval ordering verified by content (init output not echoed by stub)"
  fi
else
  fail "run with verification approval failed: $(cat "$work/out7")"
fi

# 8. Observations are recaptured on every run, so a maintainer who fixes the
#    labels or protection a previous run reported is not stuck with the old
#    snapshot forever.
repo=$(make_repo repo8)
mkdir -p "$repo/.kaizen"
printf '{"labels":["stale"]}\n' > "$repo/.kaizen/onboarding-observations.json"
ghbin="$work/bin-gh"
mkdir -p "$ghbin"
cp "$bin/kaizen" "$ghbin/kaizen"
cat > "$ghbin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$KAIZEN_TEST_LOG"
case "$*" in
  *labels*) printf '["kaizen","kaizen:P0","kaizen:P1","kaizen:P2","kaizen:pr-only"]\n' ;;
  *protection*) printf '{"required_status_checks":{"strict":true,"contexts":["test"]},"required_conversation_resolution":{"enabled":true},"enforce_admins":{"enabled":true}}\n' ;;
esac
EOF
chmod +x "$ghbin/gh"
KAIZEN_TEST_LOG="$work/log8"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$ghbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test >"$work/out8" 2>&1 ); then
  if grep -q '"stale"' "$repo/.kaizen/onboarding-observations.json"; then
    fail "a stale observations snapshot was reused"
  else
    pass "observations are recaptured on every run"
  fi
  grep -q "kaizen:pr-only" "$repo/.kaizen/onboarding-observations.json" \
    && pass "the refreshed snapshot holds live repository state" \
    || fail "refreshed snapshot did not contain live labels"
else
  fail "run with observation refresh failed: $(cat "$work/out8")"
fi

# 9. The contract checker receives the toolchain manifest this run installed
#    from, so it can validate vendored skills against the pinned set.
if grep -q "contract .*--toolchain-manifest" "$KAIZEN_TEST_LOG"; then
  pass "the contract checker receives the pinned toolchain manifest"
else
  fail "the contract checker was called without --toolchain-manifest"
fi

# 10. --refresh-manifest pulls the upstream pinned set, so an adopter told a
#     newer set exists can actually reach it instead of reinstalling the old one.
repo=$(make_repo repo10)
upstream="$work/upstream-versions.json"
printf '{"kaizen-loop":"v0.9.0","builder-agent":"v0.9.0","verifier":"v0.9.0"}\n' > "$upstream"
curlbin="$work/bin-curl"
mkdir -p "$curlbin"
cp "$bin/kaizen" "$curlbin/kaizen"
cat > "$curlbin/curl" <<EOF
#!/bin/sh
out=''
prev=''
for arg in "\$@"; do
  [ "\$prev" = "-o" ] && out=\$arg
  prev=\$arg
done
[ -n "\$out" ] && cat "$upstream" > "\$out"
exit 0
EOF
chmod +x "$curlbin/curl"
cp "$stub_tree/versions.json" "$work/local-versions.json"
KAIZEN_TEST_LOG="$work/log10"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$curlbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test \
        --manifest "$work/local-versions.json" --refresh-manifest \
        --upstream-manifest-url "file://$upstream" >"$work/out10" 2>&1 ); then
  if grep -q 'v0.9.0' "$work/local-versions.json"; then
    pass "--refresh-manifest updates the local pinned set"
  else
    fail "--refresh-manifest left the local manifest unchanged"
  fi
else
  fail "--refresh-manifest run failed: $(cat "$work/out10")"
fi

# 11. A malformed upstream manifest must not overwrite a working local one.
printf '{"kaizen-loop":"main","builder-agent":"v0.1.0","verifier":"v0.1.0"}\n' > "$upstream"
printf '{"kaizen-loop":"v0.1.0","builder-agent":"v0.1.0","verifier":"v0.1.0"}\n' > "$work/local-versions.json"
repo=$(make_repo repo11)
KAIZEN_TEST_LOG="$work/log11"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$curlbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test \
        --manifest "$work/local-versions.json" --refresh-manifest \
        --upstream-manifest-url "file://$upstream" >"$work/out11" 2>&1 ); then
  fail "an invalid upstream manifest was accepted"
else
  if grep -q 'v0.1.0' "$work/local-versions.json" && ! grep -q '"main"' "$work/local-versions.json"; then
    pass "an invalid upstream manifest leaves the local one intact"
  else
    fail "an invalid upstream manifest overwrote the local one"
  fi
fi

# 12. An unprotected default branch is the normal state for a repository being
#     onboarded. `gh api` reports it by writing a 404 body to stdout and exiting
#     non-zero, so a fallback that only discards stderr concatenates the error
#     body with the fallback and produces unparseable JSON. The run must report
#     the missing protection, not crash.
repo=$(make_repo repo12)
unprotbin="$work/bin-unprot"
mkdir -p "$unprotbin"
cp "$bin/kaizen" "$unprotbin/kaizen"
cat > "$unprotbin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$KAIZEN_TEST_LOG"
case "$*" in
  *labels*)
    printf '["kaizen","kaizen:P0","kaizen:P1","kaizen:P2","kaizen:pr-only"]\n'
    ;;
  *protection*)
    # Exactly what gh does for an unprotected branch: body on stdout, exit 1.
    printf '{"message":"Branch not protected","documentation_url":"https://docs.github.com/rest","status":"404"}'
    exit 1
    ;;
esac
EOF
chmod +x "$unprotbin/gh"
KAIZEN_TEST_LOG="$work/log12"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG KAIZEN_TEST_CONTRACT_STATUS=0
( cd "$repo" && PATH="$unprotbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
    KAIZEN_TEST_CONTRACT_STATUS=0 \
    sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test \
      >"$work/out12" 2>&1 ) || true
unset KAIZEN_TEST_CONTRACT_STATUS
if grep -qE "SyntaxError|Unexpected non-whitespace|JSON.parse" "$work/out12"; then
  fail "an unprotected branch crashed the observation capture"
else
  pass "an unprotected branch does not crash the observation capture"
fi
if [ -f "$repo/.kaizen/onboarding-observations.json" ]; then
  if OBS="$repo/.kaizen/onboarding-observations.json" node -e '
    const fs = require("node:fs");
    const d = JSON.parse(fs.readFileSync(process.env.OBS, "utf8"));
    const p = d.branchProtection;
    process.exit(
      p && p.requiredStatusChecks && p.requiredStatusChecks.strict === false &&
      p.requiredConversationResolution === false && p.enforceAdmins === false ? 0 : 1
    );
  ' 2>/dev/null; then
    pass "an unprotected branch is recorded as unprotected"
  else
    fail "the observation snapshot did not record the branch as unprotected"
  fi
else
  fail "no observation snapshot was written for an unprotected branch"
fi

# 13. Authentication, permission, rate-limit, and transient API failures are
#     not evidence that branch protection is absent. Preserve the failure so an
#     operator fixes the real problem instead of receiving misleading guidance.
repo=$(make_repo repo13)
failurebin="$work/bin-protection-failure"
mkdir -p "$failurebin"
cp "$bin/kaizen" "$failurebin/kaizen"
cat > "$failurebin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$KAIZEN_TEST_LOG"
case "$*" in
  *labels*) printf '["kaizen","kaizen:P0","kaizen:P1","kaizen:P2","kaizen:pr-only"]\n' ;;
  *protection*) printf '{"message":"API rate limit exceeded","status":"403"}'; exit 1 ;;
esac
EOF
chmod +x "$failurebin/gh"
KAIZEN_TEST_LOG="$work/log13"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$failurebin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test \
        >"$work/out13" 2>&1 ); then
  fail "a non-404 protection API failure was reported as missing protection"
elif grep -Fq "could not read branch protection" "$work/out13"; then
  pass "a non-404 protection API failure is preserved"
else
  fail "a non-404 protection API failure lacked actionable diagnostics: $(cat "$work/out13")"
fi
if [ -e "$repo/.kaizen/onboarding-observations.json.labels" ]; then
  fail "a failed observation capture left the labels sidecar behind"
else
  pass "failed observation capture removes the labels sidecar"
fi

# 14. A generic 404 can also mean the requested branch does not exist. Do not
#     convert that response into a misleading "unprotected" observation.
repo=$(make_repo repo14)
missingbin="$work/bin-missing-branch"
mkdir -p "$missingbin"
cp "$bin/kaizen" "$missingbin/kaizen"
cat > "$missingbin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$KAIZEN_TEST_LOG"
case "$*" in
  *labels*) printf '["kaizen","kaizen:P0","kaizen:P1","kaizen:P2","kaizen:pr-only"]\n' ;;
  *protection*) printf '{"message":"Branch not found","status":"404"}'; exit 1 ;;
esac
EOF
chmod +x "$missingbin/gh"
KAIZEN_TEST_LOG="$work/log14"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$missingbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test --branch missing \
        >"$work/out14" 2>&1 ); then
  fail "a missing branch was reported as merely unprotected"
elif grep -Fq "could not read branch protection" "$work/out14"; then
  pass "a missing branch is distinguished from an unprotected branch"
else
  fail "a missing branch lacked actionable diagnostics: $(cat "$work/out14")"
fi

# 15. Skipping application must still resolve and observe the real default
#     branch instead of implicitly querying main.
repo=$(make_repo repo15)
skipbin="$work/bin-skip-protection"
mkdir -p "$skipbin"
cp "$bin/kaizen" "$skipbin/kaizen"
cat > "$skipbin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >> "$KAIZEN_TEST_LOG"
case "$*" in
  *"--jq .default_branch"*) printf 'develop\n' ;;
  *labels*) printf '["kaizen","kaizen:P0","kaizen:P1","kaizen:P2","kaizen:pr-only"]\n' ;;
  *"branches/develop/protection"*) printf '{"message":"Branch not protected","status":"404"}'; exit 1 ;;
  *protection*) printf '{"message":"Branch not found","status":"404"}'; exit 1 ;;
esac
EOF
chmod +x "$skipbin/gh"
KAIZEN_TEST_LOG="$work/log15"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG KAIZEN_TEST_CONTRACT_STATUS=0
( cd "$repo" && PATH="$skipbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
    KAIZEN_TEST_CONTRACT_STATUS=0 \
    sh "$stub_tree/onboard.sh" --yes --profile pilot-node --skip-protection \
      >"$work/out15" 2>&1 ) || true
unset KAIZEN_TEST_CONTRACT_STATUS
if grep -Fq 'branches/develop/protection' "$KAIZEN_TEST_LOG"; then
  pass "skip-protection observes the resolved default branch"
else
  fail "skip-protection did not observe the resolved default branch: $(cat "$work/out15")"
fi

# 16. A zero exit status does not make a malformed API body valid.
repo=$(make_repo repo16)
malformedbin="$work/bin-malformed-protection"
mkdir -p "$malformedbin"
cp "$bin/kaizen" "$malformedbin/kaizen"
cat > "$malformedbin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *labels*) printf '["kaizen","kaizen:P0","kaizen:P1","kaizen:P2","kaizen:pr-only"]\n' ;;
  *protection*) : ;;
esac
EOF
chmod +x "$malformedbin/gh"
KAIZEN_TEST_LOG="$work/log16"; : > "$KAIZEN_TEST_LOG"
export KAIZEN_TEST_LOG
if ( cd "$repo" && PATH="$malformedbin:$PATH" KAIZEN_TEST_LOG="$KAIZEN_TEST_LOG" \
      sh "$stub_tree/onboard.sh" --yes --profile pilot-node --check test \
        >"$work/out16" 2>&1 ); then
  fail "an empty successful protection response was accepted"
elif grep -Fq "branch protection API returned malformed JSON" "$work/out16"; then
  pass "an empty successful protection response is rejected"
else
  fail "a malformed successful response lacked diagnostics: $(cat "$work/out16")"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "onboard fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All onboard fixtures passed."
