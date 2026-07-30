#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
template="${script_dir}/../automations/scout.prompt.template.md"

repo=""
evidence=""
output=""
labels="kaizen"
wip_limit=4
creation_limit=2
confirmation=""
dry_run=false
labels_seen=false
wip_seen=false
creation_seen=false

usage() {
  cat >&2 <<'USAGE'
usage: enable-scout.sh --repo owner/repo --readiness-evidence FILE --output FILE
                       [--labels label1,label2] [--wip-limit N]
                       [--creation-limit N] [--confirm owner/repo] [--dry-run]

Renders and installs an opt-in repository scout prompt. Applying requires
--confirm to exactly match --repo. --dry-run validates all prerequisites and
prints the rendered prompt without writing the output file.
USAGE
}

fail() {
  echo "error: $*" >&2
  usage
  exit 1
}

require_value() {
  [[ -n "${2:-}" && "${2:-}" != --* ]] || fail "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ -z "${repo}" ]] || fail "--repo may be supplied only once"
      require_value "$1" "${2:-}"
      repo="$2"
      shift 2
      ;;
    --readiness-evidence)
      [[ -z "${evidence}" ]] || fail "--readiness-evidence may be supplied only once"
      require_value "$1" "${2:-}"
      evidence="$2"
      shift 2
      ;;
    --output)
      [[ -z "${output}" ]] || fail "--output may be supplied only once"
      require_value "$1" "${2:-}"
      output="$2"
      shift 2
      ;;
    --labels)
      [[ "${labels_seen}" == false ]] || fail "--labels may be supplied only once"
      require_value "$1" "${2:-}"
      labels="$2"
      labels_seen=true
      shift 2
      ;;
    --wip-limit)
      [[ "${wip_seen}" == false ]] || fail "--wip-limit may be supplied only once"
      require_value "$1" "${2:-}"
      wip_limit="$2"
      wip_seen=true
      shift 2
      ;;
    --creation-limit)
      [[ "${creation_seen}" == false ]] || fail "--creation-limit may be supplied only once"
      require_value "$1" "${2:-}"
      creation_limit="$2"
      creation_seen=true
      shift 2
      ;;
    --confirm)
      [[ -z "${confirmation}" ]] || fail "--confirm may be supplied only once"
      require_value "$1" "${2:-}"
      confirmation="$2"
      shift 2
      ;;
    --dry-run)
      [[ "${dry_run}" == false ]] || fail "--dry-run may be supplied only once"
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "${repo}" ]] || fail "--repo is required"
[[ -n "${evidence}" ]] || fail "--readiness-evidence is required"
[[ -n "${output}" ]] || fail "--output is required"
[[ "${repo}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]] \
  || fail "--repo must be an explicit owner/repo"
repo_owner="${repo%%/*}"
repo_owner_lower="$(printf '%s' "${repo_owner}" | tr '[:upper:]' '[:lower:]')"
repo_lower="$(printf '%s' "${repo}" | tr '[:upper:]' '[:lower:]')"
case "${repo_lower}" in
  kaizen-agents-org/.github|kaizen-agents-org/builder-agent|kaizen-agents-org/kaizen-loop|kaizen-agents-org/verifier)
    fail "--repo is already covered by the fixed organization-wide scout"
    ;;
esac
if [[ "${labels_seen}" == false && "${repo_owner_lower}" == "kaizen-agents-org" ]]; then
  labels="kaizen,kaizen:authorized,kaizen:ready"
fi
[[ "${wip_limit}" =~ ^[1-4]$ ]] \
  || fail "--wip-limit must be an integer from 1 through 4"
[[ "${creation_limit}" =~ ^[1-2]$ ]] \
  || fail "--creation-limit must be an integer from 1 through 2"
[[ -f "${template}" ]] || fail "scout template is missing: ${template}"
[[ -f "${evidence}" ]] || fail "readiness evidence is missing: ${evidence}"
[[ -n "${labels}" && "${labels}" != *, && "${labels}" != ,* && "${labels}" != *,,* ]] \
  || fail "--labels must be a comma-separated list without empty entries"

IFS=',' read -r -a label_values <<< "${labels}"
kaizen_label_present=false
authorized_label_present=false
ready_label_present=false
for label in "${label_values[@]}"; do
  [[ "${label}" =~ ^[A-Za-z0-9][A-Za-z0-9:._\ -]*$ ]] \
    || fail "invalid label: ${label}"
  [[ "${label}" != "kaizen" ]] || kaizen_label_present=true
  [[ "${label}" != "kaizen:authorized" ]] || authorized_label_present=true
  [[ "${label}" != "kaizen:ready" ]] || ready_label_present=true
done
[[ "${kaizen_label_present}" == true ]] \
  || fail "--labels must include the mandatory kaizen intake label"
if [[ "${repo_owner_lower}" == "kaizen-agents-org" ]]; then
  [[ "${authorized_label_present}" == true ]] \
    || fail "--labels for kaizen-agents-org repositories must include kaizen:authorized"
  [[ "${ready_label_present}" == true ]] \
    || fail "--labels for kaizen-agents-org repositories must include kaizen:ready"
fi

rendered="$(node --input-type=module - "${template}" "${evidence}" "${repo}" \
  "${labels}" "${wip_limit}" "${creation_limit}" <<'NODE'
import fs from 'node:fs';

const [templateFile, evidenceFile, repository, labels, wipText, creationText] =
  process.argv.slice(2);
const wipLimit = Number(wipText);
let readiness;
try {
  readiness = JSON.parse(fs.readFileSync(evidenceFile, 'utf8'));
} catch (error) {
  throw new Error(`readiness evidence is not valid JSON: ${error.message}`);
}
if (!readiness || typeof readiness !== 'object' || Array.isArray(readiness)) {
  throw new Error('readiness evidence root must be an object');
}
if (readiness.version !== 1 || readiness.repository !== repository) {
  throw new Error('readiness evidence version/repository does not match the requested target');
}
const metrics = readiness.metrics;
if (!metrics || !/^\d{4}-W\d{2}$/.test(metrics.isoWeek) ||
    !Number.isInteger(metrics.processed) || metrics.processed <= 0 ||
    !Number.isInteger(metrics.prsCreated) || metrics.prsCreated <= 0 ||
    metrics.prsCreated > metrics.processed ||
    !Number.isInteger(metrics.openPullRequests) || metrics.openPullRequests < 0) {
  throw new Error('readiness evidence must contain a weekly window with positive, consistent throughput metrics');
}
if (metrics.openPullRequests >= wipLimit) {
  throw new Error(`open pull requests (${metrics.openPullRequests}) meet or exceed the WIP limit (${wipLimit})`);
}
if (!readiness.readiness || readiness.readiness.scoutEligible !== true ||
    !/^\d{4}-\d{2}-\d{2}$/.test(readiness.readiness.reviewedAt)) {
  throw new Error('readiness evidence must contain a dated explicit scoutEligible approval');
}
const reviewDate = new Date(`${readiness.readiness.reviewedAt}T00:00:00Z`);
const today = new Date();
today.setUTCHours(0, 0, 0, 0);
const ageDays = Math.floor((today - reviewDate) / 86_400_000);
if (!Number.isFinite(reviewDate.getTime()) ||
    reviewDate.toISOString().slice(0, 10) !== readiness.readiness.reviewedAt ||
    ageDays < 0 || ageDays > 14) {
  throw new Error('readiness approval must be no more than 14 days old and not future-dated');
}
function isoWeek(date) {
  const value = new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate()
  ));
  value.setUTCDate(value.getUTCDate() + 4 - (value.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(value.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((value - yearStart) / 86_400_000) + 1) / 7);
  return `${value.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}
const previousWeek = new Date(reviewDate);
previousWeek.setUTCDate(previousWeek.getUTCDate() - 7);
if (![isoWeek(reviewDate), isoWeek(previousWeek)].includes(metrics.isoWeek)) {
  throw new Error('weekly metrics must cover the readiness review week or the immediately preceding week');
}

const renderedLabels = labels.split(',').map((label) => `\`${label}\``).join(', ');
const replacements = new Map([
  ['{{REPOSITORY}}', repository],
  ['{{LABELS}}', renderedLabels],
  ['{{WIP_LIMIT}}', String(wipLimit)],
  ['{{CREATION_LIMIT}}', creationText]
]);
let prompt = fs.readFileSync(templateFile, 'utf8');
for (const [placeholder, value] of replacements) {
  if (!prompt.includes(placeholder)) {
    throw new Error(`template is missing ${placeholder}`);
  }
  prompt = prompt.replaceAll(placeholder, value);
}
if (/\{\{[A-Z0-9_]+\}\}/.test(prompt)) {
  throw new Error('template contains an unresolved placeholder');
}
process.stdout.write(prompt);
NODE
)" || fail "scout prerequisites or template rendering failed"

printf 'Target repository: %s\n' "${repo}"
printf 'Readiness evidence: %s\n' "${evidence}"
printf 'Output: %s\n' "${output}"
printf 'Rendered scout prompt:\n%s\n' "${rendered}"

[[ ! -e "${output}" && ! -L "${output}" ]] \
  || fail "output already exists; remove it explicitly before reinstalling: ${output}"
[[ -d "$(dirname -- "${output}")" ]] \
  || fail "output directory does not exist: $(dirname -- "${output}")"

if [[ "${dry_run}" == true ]]; then
  echo "Dry run: scout remains disabled and no file was written."
  exit 0
fi

[[ "${confirmation}" == "${repo}" ]] \
  || fail "--confirm must exactly match --repo before scout enablement"

(umask 077; set -o noclobber; printf '%s\n' "${rendered}" > "${output}") \
  || fail "output appeared during enablement and was not overwritten: ${output}"
printf 'Scout prompt enabled for %s at %s.\n' "${repo}" "${output}"
