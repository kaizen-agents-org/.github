#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash scripts/test-pull-request-ci-contract.sh
bash scripts/test-automation-prompt-contract.sh
bash scripts/test-dogfood-selection-label-contract.sh
bash scripts/test-sync-daily-dogfood.sh
bash scripts/test-sync-daily-dogfood-pr-link.sh
bash scripts/test-sync-kaizen-shared-skills.sh
bash scripts/test-sync-kaizen-shared-skills-pr-link.sh
bash scripts/test-onboarding-versions-sandbox.sh
bash scripts/test-onboarding-branch-protection.sh
bash onboarding/scripts/test-onboard.sh
bash onboarding/scripts/test-onboarding-contract.sh
bash onboarding/scripts/test-install-kaizen.sh
bash onboarding/scripts/test-uninstall-kaizen.sh
bash onboarding/scripts/test-toolchain-update.sh
bash scripts/test-check-doc-links.sh
