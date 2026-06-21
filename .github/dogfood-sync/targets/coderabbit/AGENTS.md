# Repository Instructions

## Kaizen Issue-to-PR MVP

- Keep the MVP PR-first: create ready-for-review pull requests, not draft PRs, unless explicitly requested.
- Every implementation PR must include a GitHub closing keyword in the PR body, for example `Closes #123`.
- Use the vendored skills under `skills/` for issue-linked PRs, Kaizen bug routing, and PR guardian follow-up.
- After opening a PR, run the `pr-guardian` workflow and keep going until the PR is mergeable or a real blocker is reported.

## Review Guidelines

- Treat invalid `.coderabbit.yaml` syntax or unsupported CodeRabbit settings as
  P1 findings.
- Verify that review settings stay consistent with CodeRabbit documentation and
  this repository's README.
- Keep review automation focused on actionable correctness, security, and
  release-risk findings.
