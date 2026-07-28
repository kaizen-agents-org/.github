#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checker="${script_dir}/check-onboarding-contract.sh"
fixture_base="${KAIZEN_TEST_TMPDIR:-/tmp}"
fixture_root="$(mktemp -d "${fixture_base%/}/onboarding-contract.XXXXXX")"
trap 'rm -rf "${fixture_root}"' EXIT

make_fixture() {
  local target="$1"
  mkdir -p \
    "${target}/.github/ISSUE_TEMPLATE" \
    "${target}/.kaizen" \
    "${target}/docs/smoke-runs" \
    "${target}/onboarding" \
    "${target}/skills/example"
  cat > "${target}/.kaizen/config.yml" <<'YAML'
version: 1
safety:
  wipLimit: 5
verifier:
  enabled: true
policy:
  mode: pr-only
  protectedPaths:
    - ".github/**"
    - "**/.env*"
    - "**/secrets/**"
    - "**/*migration*/**"
    - ".kaizen/**"
  forbiddenPaths:
    - "**/.git/**"
YAML
  cat > "${target}/.kaizen/onboarding-observations.json" <<'JSON'
{
  "labels": ["kaizen", "kaizen:P0", "kaizen:P1", "kaizen:P2", "kaizen:pr-only"],
  "branchProtection": {
    "requiredStatusChecks": {"strict": true, "contexts": ["test"]},
    "requiredConversationResolution": true,
    "enforceAdmins": true
  }
}
JSON
  printf 'name: Kaizen\n' > "${target}/.github/ISSUE_TEMPLATE/kaizen.yml"
  printf '{"ok":true}\n' > "${target}/docs/smoke-runs/smoke.json"
  printf 'example skill\n' > "${target}/skills/example/SKILL.md"
  cat > "${target}/onboarding/versions.json" <<'JSON'
{"kaizen-loop":"v0.1.0","builder-agent":"v0.1.0","verifier":"v0.1.0"}
JSON
  local digest
  digest="$(sha256_file "${target}/skills/example/SKILL.md")"
  cat > "${target}/skills/skills-manifest.json" <<JSON
{
  "version": 1,
  "toolchain": {"kaizen-loop":"v0.1.0","builder-agent":"v0.1.0","verifier":"v0.1.0"},
  "files": {"skills/example/SKILL.md":"${digest}"}
}
JSON
}

sha256_file() {
  node -e 'const fs=require("fs"),crypto=require("crypto"); process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
}

fixture_digest() {
  node -e '
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const root = process.argv[1];
const hash = crypto.createHash("sha256");
function visit(directory) {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true}).sort((a, b) => a.name.localeCompare(b.name))) {
    const absolute = path.join(directory, entry.name);
    const relative = path.relative(root, absolute);
    hash.update(`${entry.isDirectory() ? "d" : entry.isFile() ? "f" : "o"}:${relative}\0`);
    if (entry.isDirectory()) visit(absolute);
    else if (entry.isFile()) hash.update(fs.readFileSync(absolute));
    else if (entry.isSymbolicLink()) hash.update(fs.readlinkSync(absolute));
  }
}
visit(root);
process.stdout.write(hash.digest("hex"));
' "$1"
}

expect_failure() {
  local name="$1"
  local expected="$2"
  local target="${fixture_root}/${name}"
  shift 2
  make_fixture "${target}"
  "$@" "${target}"
  if "${checker}" "${target}" >"${target}.out" 2>&1; then
    echo "FAIL: negative fixture passed: ${name}" >&2
    exit 1
  fi
  if ! grep -Fq "${expected}" "${target}.out"; then
    echo "FAIL: ${name} did not report expected remediation context: ${expected}" >&2
    cat "${target}.out" >&2
    exit 1
  fi
}

mutate_invalid_schema() {
  printf 'version: nope\n' > "$1/.kaizen/config.yml"
}

mutate_policy_mode() {
  sed -i.bak 's/mode: pr-only/mode: hybrid/' "$1/.kaizen/config.yml"
  rm "$1/.kaizen/config.yml.bak"
}

mutate_wip_limit() {
  sed -i.bak 's/wipLimit: 5/wipLimit: 6/' "$1/.kaizen/config.yml"
  rm "$1/.kaizen/config.yml.bak"
}

mutate_verifier() {
  sed -i.bak 's/enabled: true/enabled: false/' "$1/.kaizen/config.yml"
  rm "$1/.kaizen/config.yml.bak"
}

mutate_protected_path() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=fs.readFileSync(p,"utf8");fs.writeFileSync(p,v.replace("    - \".kaizen/**\"\n",""))' \
    "$1/.kaizen/config.yml"
  cat > "$1/.kaizen/profile-overlay.yml" <<'YAML'
policy:
  protectedPaths:
    - ".kaizen/**"
YAML
}

mutate_forbidden_path() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=fs.readFileSync(p,"utf8");fs.writeFileSync(p,v.replace("    - \"**/.git/**\"","    - \"**/.ssh/**\""))' \
    "$1/.kaizen/config.yml"
}

mutate_label() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.labels=v.labels.filter(x=>x!=="kaizen:P2");fs.writeFileSync(p,JSON.stringify(v))' \
    "$1/.kaizen/onboarding-observations.json"
}

mutate_template() {
  rm "$1/.github/ISSUE_TEMPLATE/kaizen.yml"
}

mutate_status_checks() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.branchProtection.requiredStatusChecks.contexts=[];fs.writeFileSync(p,JSON.stringify(v))' \
    "$1/.kaizen/onboarding-observations.json"
}

mutate_conversation_resolution() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.branchProtection.requiredConversationResolution=false;fs.writeFileSync(p,JSON.stringify(v))' \
    "$1/.kaizen/onboarding-observations.json"
}

mutate_admin_enforcement() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.branchProtection.enforceAdmins=false;fs.writeFileSync(p,JSON.stringify(v))' \
    "$1/.kaizen/onboarding-observations.json"
}

mutate_smoke() {
  rm "$1/docs/smoke-runs/smoke.json"
}

mutate_skill_digest() {
  printf 'drifted skill\n' > "$1/skills/example/SKILL.md"
}

mutate_skill_symlink() {
  local external_skill="${fixture_root}/external-skill.md"
  printf 'example skill\n' > "${external_skill}"
  rm "$1/skills/example/SKILL.md"
  ln -s "${external_skill}" "$1/skills/example/SKILL.md"
}

mutate_toolchain() {
  node -e 'const fs=require("fs"),p=process.argv[1],v=JSON.parse(fs.readFileSync(p));v.toolchain.verifier="v9.9.9";fs.writeFileSync(p,JSON.stringify(v))' \
    "$1/skills/skills-manifest.json"
}

positive="${fixture_root}/positive"
make_fixture "${positive}"
mkdir -p "${fixture_root}/bin"
cat > "${fixture_root}/bin/gh" <<'SH'
#!/usr/bin/env bash
touch "${GH_INVOCATION_MARKER}"
exit 99
SH
chmod +x "${fixture_root}/bin/gh"
before_digest="$(fixture_digest "${positive}")"
GH_INVOCATION_MARKER="${fixture_root}/gh-invoked" \
  PATH="${fixture_root}/bin:${PATH}" \
  "${checker}" "${positive}"
after_digest="$(fixture_digest "${positive}")"
if [[ "${before_digest}" != "${after_digest}" ]]; then
  echo "FAIL: checker mutated the target repository" >&2
  exit 1
fi
if [[ -e "${fixture_root}/gh-invoked" ]]; then
  echo "FAIL: checker invoked gh instead of using the observation snapshot" >&2
  exit 1
fi

expect_failure invalid-schema 'not schema-valid' mutate_invalid_schema
expect_failure policy-mode 'policy.mode must be pr-only' mutate_policy_mode
expect_failure wip-limit 'safety.wipLimit must be an integer no greater than 5' mutate_wip_limit
expect_failure verifier-disabled 'verifier.enabled must be true' mutate_verifier
expect_failure protected-floor 'profile overlays cannot replace this check' mutate_protected_path
expect_failure forbidden-git 'policy.forbiddenPaths is missing **/.git/**' mutate_forbidden_path
expect_failure missing-label 'required repository label is not observed: kaizen:P2' mutate_label
expect_failure missing-template 'required Kaizen issue template is missing or empty' mutate_template
expect_failure status-checks 'branch protection must require at least one strict status check' mutate_status_checks
expect_failure conversation-resolution 'branch protection must require conversation resolution' mutate_conversation_resolution
expect_failure admin-enforcement 'branch protection must enforce rules for administrators' mutate_admin_enforcement
expect_failure missing-smoke 'no smoke artifact JSON file was found' mutate_smoke
expect_failure skill-drift 'vendored skill does not match its manifest digest' mutate_skill_digest
expect_failure skill-symlink 'skills manifest path is not a regular file' mutate_skill_symlink
expect_failure toolchain-drift 'skills manifest toolchain mismatch for verifier' mutate_toolchain

echo "PASS onboarding security policy and admin-enforcement fixture tests passed"
