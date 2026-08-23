#!/bin/sh
# Fixture tests for check-toolchain-update.sh.
#
# curl and gh are stubbed, so the suite makes no network calls and creates no
# issues.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checker="$script_dir/check-toolchain-update.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $1"; }

write_manifest() {
  cat > "$1" <<EOF
{
  "kaizen-loop": "$2",
  "builder-agent": "$3",
  "verifier": "$4"
}
EOF
}

# $1 = upstream manifest served by the curl stub, $2 = existing open issue number
make_bin() {
  bin="$work/bin-$3"
  mkdir -p "$bin"
  cat > "$bin/curl" <<EOF
#!/bin/sh
out=''
prev=''
for arg in "\$@"; do
  [ "\$prev" = "-o" ] && out=\$arg
  prev=\$arg
done
[ -n "\$out" ] && cat "$1" > "\$out"
exit 0
EOF
  cat > "$bin/gh" <<EOF
#!/bin/sh
printf 'gh %s\n' "\$*" >> "\$KAIZEN_TEST_GH_LOG"
case "\$*" in
  *"issue list"*) printf '%s\n' "$2" ;;
esac
exit 0
EOF
  chmod +x "$bin/curl" "$bin/gh"
  printf '%s' "$bin"
}

# 1. Identical manifests report no update and create nothing.
local_manifest="$work/local-same.json"
upstream="$work/upstream-same.json"
write_manifest "$local_manifest" v0.1.0 v0.1.0 v0.1.0
write_manifest "$upstream" v0.1.0 v0.1.0 v0.1.0
bin=$(make_bin "$upstream" "" same)
log="$work/gh-same.log"; : > "$log"
if KAIZEN_TEST_GH_LOG="$log" PATH="$bin:$PATH" sh "$checker" \
     --repo example/repo --manifest "$local_manifest" >"$work/out1" 2>&1; then
  grep -q "matches the upstream pinned set" "$work/out1" \
    && pass "an unchanged manifest reports no update" \
    || fail "unchanged manifest gave the wrong message"
  grep -q "issue create" "$log" && fail "an issue was created with no update" \
    || pass "no issue is created without an update"
else
  fail "the checker failed on identical manifests: $(cat "$work/out1")"
fi

# 2. A newer upstream set is reported per component.
local_manifest="$work/local-old.json"
upstream="$work/upstream-new.json"
write_manifest "$local_manifest" v0.1.0 v0.1.0 v0.1.0
write_manifest "$upstream" v0.2.0 v0.1.0 v0.3.1
bin=$(make_bin "$upstream" "" new)
log="$work/gh-new.log"; : > "$log"
if KAIZEN_TEST_GH_LOG="$log" PATH="$bin:$PATH" sh "$checker" \
     --repo example/repo --manifest "$local_manifest" >"$work/out2" 2>&1; then
  if grep -q "kaizen-loop: v0.1.0 -> v0.2.0" "$work/out2" &&
     grep -q "verifier: v0.1.0 -> v0.3.1" "$work/out2"; then
    pass "each changed component is reported"
  else
    fail "changed components were not reported: $(cat "$work/out2")"
  fi
  grep -q "builder-agent:" "$work/out2" \
    && fail "an unchanged component was reported as changed" \
    || pass "unchanged components are omitted"
  grep -q "issue create" "$log" \
    && pass "an update opens a notification issue" \
    || fail "no issue was created for an available update"
else
  fail "the checker failed on a newer upstream set: $(cat "$work/out2")"
fi

# 3. An already-open notification is not duplicated.
bin=$(make_bin "$upstream" "42" dup)
log="$work/gh-dup.log"; : > "$log"
if KAIZEN_TEST_GH_LOG="$log" PATH="$bin:$PATH" sh "$checker" \
     --repo example/repo --manifest "$local_manifest" >"$work/out3" 2>&1; then
  grep -q "already open" "$work/out3" \
    && pass "an existing notification suppresses a duplicate" \
    || fail "duplicate suppression message was missing"
  grep -q "issue create" "$log" \
    && fail "a duplicate issue was created" \
    || pass "no duplicate issue is created"
else
  fail "the checker failed with an existing issue: $(cat "$work/out3")"
fi

# 4. --dry-run reports without touching GitHub.
bin=$(make_bin "$upstream" "" dry)
log="$work/gh-dry.log"; : > "$log"
if KAIZEN_TEST_GH_LOG="$log" PATH="$bin:$PATH" sh "$checker" \
     --repo example/repo --manifest "$local_manifest" --dry-run >"$work/out4" 2>&1; then
  grep -q "Dry run" "$work/out4" && [ ! -s "$log" ] \
    && pass "dry run reports without calling gh" \
    || fail "dry run touched gh or reported wrongly"
else
  fail "dry run failed: $(cat "$work/out4")"
fi

# 5. A manifest pinning a branch is rejected rather than compared.
local_manifest="$work/local-bad.json"
write_manifest "$local_manifest" main v0.1.0 v0.1.0
bin=$(make_bin "$upstream" "" bad)
log="$work/gh-bad.log"; : > "$log"
KAIZEN_TEST_GH_LOG="$log" PATH="$bin:$PATH" sh "$checker" \
  --repo example/repo --manifest "$local_manifest" >"$work/out5" 2>&1 && status=0 || status=$?
if [ "${status:-0}" -eq 2 ] && grep -q "does not pin kaizen-loop" "$work/out5"; then
  pass "a manifest pinning a branch is rejected"
else
  fail "branch-pinned manifest was not rejected (status ${status:-0})"
fi

# 6. --repo is required.
if sh "$checker" --dry-run >"$work/out6" 2>&1; then
  fail "the checker ran without --repo"
else
  grep -q -- "--repo is required" "$work/out6" \
    && pass "--repo is required" \
    || fail "missing --repo gave the wrong message"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "toolchain-update fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All toolchain-update fixtures passed."
