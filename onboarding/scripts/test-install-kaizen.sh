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
  *clone*)
    # Stand in for the verifier checkout so the build path has a directory to
    # enter, the same as a real clone would leave behind.
    target=''
    for arg in "\$@"; do target=\$arg; done
    [ -n "\$target" ] && mkdir -p "\$target/packages/core" && mkdir -p "\$target/.git"
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

# 6. A real (non-dry-run) install runs the expected commands. Without this, a
#    regression that validates tags and then installs nothing passes every
#    other fixture in this file.
manifest="$work/install.json"
write_manifest "$manifest" v0.1.0 v0.1.0 v0.1.0
bin=$(make_stub_bin "v0.1.0" install)
# Report a version that cannot satisfy the pin, so a real kaizen on the host
# PATH cannot make this fixture look like an already-current install.
for absent in kaizen builder-agent verifier; do
  cat > "$bin/$absent" <<'EOF'
#!/bin/sh
printf 'not-installed\n'
EOF
  chmod +x "$bin/$absent"
done
log="$work/npm-install.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" KAIZEN_HOME="$work/home" PATH="$bin:$PATH" \
     sh "$installer" --manifest "$manifest" >"$work/out6" 2>&1; then
  # Every component is built from a pinned checkout: `npm ci && npm run build`
  # for the npm components, `pnpm install --frozen-lockfile && pnpm build` for
  # the workspace one, then `npm link`.
  if [ "$(grep -c '^npm ci$' "$log")" -eq 2 ] &&
     [ "$(grep -c '^npm run build$' "$log")" -eq 2 ] &&
     [ "$(grep -c '^npm link$' "$log")" -eq 3 ]; then
    pass "every component is built from its pinned checkout and linked"
  else
    fail "expected build commands did not run (log: $(tr '\n' '|' < "$log"))"
  fi
  if grep -q "pnpm install --frozen-lockfile" "$log" && grep -q "pnpm build" "$log"; then
    pass "the workspace component uses its own package manager"
  else
    fail "verifier build path did not run"
  fi
  grep -q "install -g github:kaizen-agents-org/verifier" "$log" \
    && fail "verifier was installed with npm install -g, which cannot work" \
    || pass "verifier is not installed through npm install -g"
else
  fail "a real install failed: $(cat "$work/out6")"
fi

# 7. A stale stamp does not satisfy the pin. The skip decision reads the
#    recorded version of each pinned checkout, so a checkout left at an older
#    release must be rebuilt rather than silently kept.
staleroot="$work/home-stale"
mkdir -p "$staleroot/toolchain/kaizen-loop"
printf 'v0.0.9\n' > "$staleroot/toolchain/kaizen-loop/.installed-version"
log="$work/npm-stale.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" KAIZEN_HOME="$staleroot" PATH="$bin:$PATH" \
     sh "$installer" --manifest "$manifest" >"$work/out7" 2>&1; then
  if grep -q "installing kaizen-loop v0.1.0 from source" "$work/out7"; then
    pass "a checkout stamped with an older release is reinstalled"
  else
    fail "a stale stamp was treated as already current"
  fi
  if [ "$(cat "$staleroot/toolchain/kaizen-loop/.installed-version")" = "v0.1.0" ]; then
    pass "the stamp is updated to the pinned version"
  else
    fail "the stamp was not updated after reinstall"
  fi
else
  fail "install over a stale stamp failed: $(cat "$work/out7")"
fi

# 8. A current stamp is skipped, which is what makes re-running cheap and makes
#    "re-run to update" viable as the documented update path.
log="$work/npm-match.log"
: > "$log"
if KAIZEN_TEST_NPM_LOG="$log" KAIZEN_HOME="$staleroot" PATH="$bin:$PATH" \
     sh "$installer" --manifest "$manifest" >"$work/out8" 2>&1; then
  if grep -q "kaizen-loop already at v0.1.0; skipping" "$work/out8"; then
    pass "an already-current component is skipped on re-run"
  else
    fail "an already-current component was reinstalled"
  fi
  if [ -s "$log" ]; then
    fail "a fully current re-run still invoked a package manager"
  else
    pass "a fully current re-run runs no build commands"
  fi
else
  fail "re-run with current stamps failed: $(cat "$work/out8")"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "install-kaizen fixtures failed with $failures failure(s)." >&2
  exit 1
fi
echo "All install-kaizen fixtures passed."
