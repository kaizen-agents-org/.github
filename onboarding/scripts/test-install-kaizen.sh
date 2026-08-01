#!/bin/sh
# Fixture tests for install-kaizen.sh.
#
# git and npm are stubbed on PATH so the suite never reaches the network and
# never installs anything globally.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
installer="$script_dir/install-kaizen.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "ok: $1"
}

# $1 = space-separated tags that "exist" on the remote
make_stub_bin() {
  existing_tags=$1
  bin="$work/bin-$2"
  mkdir -p "$bin"
  cat > "$bin/git" <<EOF
#!/bin/sh
case "\$*" in
  *"ls-remote --tags"*)
    for tag in $existing_tags; do
      case "\$*" in
        *"refs/tags/\$tag"*) printf 'deadbeef\trefs/tags/%s\n' "\$tag" ;;
      esac
    done
    ;;
esac
exit 0
EOF
  cat > "$bin/npm" <<'EOF'
#!/bin/sh
printf 'npm %s\n' "$*" >> "$KAIZEN_TEST_NPM_LOG"
EOF
  cat > "$bin/pnpm" <<'EOF'
#!/bin/sh
printf 'pnpm %s\n' "$*" >> "$KAIZEN_TEST_NPM_LOG"
EOF
  chmod +x "$bin/git" "$bin/npm" "$bin/pnpm"
  printf '%s' "$bin"
}

write_manifest() {
  cat > "$1" <<EOF
{
  "kaizen-loop": "$2",
  "builder-agent": "$3",
  "verifier": "$4"
}
EOF
}

# 1. Missing tags must stop the install before anything is written.
manifest="$work/missing.json"
write_manifest "$manifest" v0.1.0 v0.1.0 v0.1.0
bin=$(make_stub_bin "" missing)
log="$work/npm-missing.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" PATH="$bin:$PATH" sh "$installer" --manifest "$manifest" >"$work/out1" 2>&1; then
  fail "installer succeeded even though no pinned tag exists"
else
  if grep -q "no tag v0.1.0" "$work/out1" && grep -q "nothing was installed" "$work/out1"; then
    pass "missing pinned tags stop the install with remediation"
  else
    fail "missing-tag output lacked remediation text"
  fi
  if [ -s "$log" ]; then
    fail "installer invoked npm despite missing tags"
  else
    pass "no package manager ran when tags were missing"
  fi
fi

# 2. A manifest that does not pin a v0.x.y tag is rejected.
manifest="$work/bad.json"
write_manifest "$manifest" main v0.1.0 v0.1.0
bin=$(make_stub_bin "main v0.1.0" bad)
log="$work/npm-bad.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" PATH="$bin:$PATH" sh "$installer" --manifest "$manifest" >"$work/out2" 2>&1; then
  fail "installer accepted a manifest pinning a branch name"
else
  if grep -q "does not pin kaizen-loop to a v0.x.y release tag" "$work/out2"; then
    pass "a branch name in the manifest is rejected"
  else
    fail "branch-name rejection message was missing"
  fi
fi

# 3. Malformed JSON is reported as such.
manifest="$work/broken.json"
printf '{ not json' > "$manifest"
bin=$(make_stub_bin "v0.1.0" broken)
log="$work/npm-broken.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" PATH="$bin:$PATH" sh "$installer" --manifest "$manifest" >"$work/out3" 2>&1; then
  fail "installer accepted malformed JSON"
else
  if grep -q "is not valid JSON" "$work/out3"; then
    pass "malformed manifest JSON is reported"
  else
    fail "malformed JSON message was missing"
  fi
fi

# 4. A missing manifest exits with the usage code.
bin=$(make_stub_bin "v0.1.0" absent)
log="$work/npm-absent.log"
: > "$log"
KAIZEN_TEST_NPM_LOG="$log" PATH="$bin:$PATH" sh "$installer" --manifest "$work/does-not-exist.json" >"$work/out4" 2>&1 && status=0 || status=$?
if [ "${status:-0}" -eq 2 ] && grep -q "version manifest not found" "$work/out4"; then
  pass "a missing manifest exits 2"
else
  fail "missing manifest did not exit 2 with the expected message"
fi

# 5. When every tag exists, --dry-run reports them and still installs nothing.
manifest="$work/good.json"
write_manifest "$manifest" v0.1.0 v0.1.0 v0.1.0
bin=$(make_stub_bin "v0.1.0" good)
log="$work/npm-good.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" PATH="$bin:$PATH" sh "$installer" --manifest "$manifest" --dry-run >"$work/out5" 2>&1; then
  if grep -q "Dry run: no changes made" "$work/out5"; then
    pass "dry run reports the resolved set"
  else
    fail "dry run did not report cleanly"
  fi
  if [ -s "$log" ]; then
    fail "dry run invoked a package manager"
  else
    pass "dry run installed nothing"
  fi
else
  fail "dry run failed even though every pinned tag exists"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "install-kaizen fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All install-kaizen fixtures passed."
