# Repository Instructions

## Kaizen Issue-to-PR MVP

- Keep the MVP PR-first: create ready-for-review pull requests, not draft PRs, unless explicitly requested.
- Every implementation PR must include a GitHub closing keyword in the PR body, for example `Closes #123`.
- Use the vendored skills under `skills/` for issue-linked PRs, Kaizen bug routing, and PR guardian follow-up.
- After opening a PR, run the `pr-guardian` workflow and keep going until the PR is mergeable or a real blocker is reported.

## Review Guidelines

- Treat invalid Renovate JSON or unsupported options as P1 findings.
- Keep shared defaults conservative; do not enable automerge unless explicitly
  requested.
- Verify that README setup instructions match Renovate's current GitHub App and
  onboarding behavior.
