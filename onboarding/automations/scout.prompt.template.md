Managed template: `kaizen-agents-org/.github/onboarding/automations/scout.prompt.template.md`.
<!-- automation-contract: automation=scout; issues=[scout]; prs=none; source=default-branch; roles-doc=docs/automation-roles.md -->

Scout `{{REPOSITORY}}` for small, evidence-backed repository-local improvements.
Use the repository default branch as the source of truth. Do not create work
from local-only, feature-branch-only, dirty, or stale unmerged content.

Before collecting evidence, resolve the current default branch with
`gh repo view {{REPOSITORY}} --json defaultBranchRef --jq
'.defaultBranchRef.name'` and require a non-empty result. Fetch that branch from
`origin`, then read documentation and code from the updated
`origin/<defaultBranch>` ref rather than the current checkout. If the default
branch cannot be resolved or fetched, fail closed and create no issue.

Created issue titles must start with `[scout]`. Apply exactly these configured
labels: {{LABELS}}. If every configured label cannot be verified and applied,
fail closed without creating the issue. Labels do not grant permission to edit
the repository, create implementation branches, or open pull requests.

Before creating an issue:

- search open issues and pull requests using the title, affected paths,
  component names, and conceptual keywords;
- skip work already owned by an issue or pull request;
- skip issue creation when `{{REPOSITORY}}` already has
  `{{WIP_LIMIT}}` or more open pull requests;
- skip issue creation when the repository already has four or more open issues
  labeled `kaizen`;
- ensure the work is bounded, actionable without clarification, and supported
  by default-branch documentation or code;
- include a `PR linkage requirement` section requiring a GitHub closing keyword
  and verification of `closingIssuesReferences`.

Create no more than `{{CREATION_LIMIT}}` issues in one run. Additional findings
remain report-only. Never create `[monitor]` or `[readiness-review]` issues.

Do not edit files, push branches, merge pull requests, create implementation
branches, open implementation pull requests, or make broad code changes. This
scout may only inspect the repository, create eligible `[scout]` issues within
the configured limits, and report its findings.
