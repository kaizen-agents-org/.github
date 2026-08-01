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
  init) mkdir -p "$PWD/.kaizen" && printf 'version: 1\n' > "$PWD/.kaizen/config.yml" ;;
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

echo
if [ "$failures" -gt 0 ]; then
  echo "onboard fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All onboard fixtures passed."
