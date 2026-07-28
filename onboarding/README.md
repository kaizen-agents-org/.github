# Kaizen Onboarding

The onboarding directory contains organization-owned assets for adopting the
Kaizen workflow. Administrative repository changes are explicit operations:
`kaizen init` does not invoke the branch-protection helper.

## Apply the standard branch protection

An administrator must name the repository, branch, and CI check explicitly:

```sh
onboarding/scripts/apply-branch-protection.sh \
  --repo owner/repository \
  --branch main \
  --check "test"
```

Add `--dry-run` to print the resolved target and exact request body without
calling GitHub:

```sh
onboarding/scripts/apply-branch-protection.sh \
  --repo owner/repository \
  --branch main \
  --check "test" \
  --dry-run
```

The preset requires the named status check with strict checking, requires all
review conversations to be resolved, and enforces the rules for administrators.
It deliberately sets required pull-request reviews and push restrictions to
`null`; repositories that need additional rules should record an exception and
apply a repository-specific policy instead of this preset.

### Requirements and permissions

- `jq` and `git` must be installed; applying the policy also requires `gh`
  (`--dry-run` does not).
- `gh` must be authenticated as a repository administrator or owner.
- Fine-grained tokens and GitHub App tokens need repository
  `Administration: write` permission.
- GitHub authorization failures stop the command without reporting a successful
  application; the helper does not retry with broader credentials.
- The named branch and status-check context must already be known. The helper
  does not infer defaults, discover checks, or expand wildcard branch names.

Running the command again with the same inputs sends the same `PUT` payload, so
reapplication converges on the same policy. The command prints the target and
payload before making the request.

### Backup and rollback

Before applying the policy, capture the current settings:

```sh
gh api \
  -H "Accept: application/vnd.github+json" \
  repos/owner/repository/branches/main/protection \
  > branch-protection.before.json
```

The response is evidence for rollback, not a request body that can be passed
directly back to the update endpoint. To roll back, reconstruct the previous
settings from that snapshot and apply them in the GitHub branch settings UI or
with a reviewed `PUT` request. If the branch previously had no protection,
removing all protection is a separate destructive action:

```sh
gh api --method DELETE \
  repos/owner/repository/branches/main/protection
```

Review the target and obtain explicit administrator approval before running
that rollback command.
