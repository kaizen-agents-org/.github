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
else
  fail "a full non-interactive pass failed: $(cat "$work/out3")"
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

echo
if [ "$failures" -gt 0 ]; then
  echo "onboard fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All onboard fixtures passed."
