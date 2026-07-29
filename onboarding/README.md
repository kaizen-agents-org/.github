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

## Check the onboarding contract

`onboarding/scripts/check-onboarding-contract.sh` is the read-only acceptance
gate for a repository adopting the Kaizen harness. It reads a target checkout
and a previously captured observation snapshot; it does not call GitHub, change
repository settings, or repair mismatches.

## Usage

```sh
onboarding/scripts/check-onboarding-contract.sh \
  --observations /path/to/onboarding-observations.json \
  /path/to/target-repository
```

When `--observations` is omitted, the checker reads
`.kaizen/onboarding-observations.json` from the target. The snapshot has this
format:

```json
{
  "labels": ["kaizen", "kaizen:P0", "kaizen:P1", "kaizen:P2", "kaizen:pr-only"],
  "branchProtection": {
    "requiredStatusChecks": {
      "strict": true,
      "contexts": ["test"]
    },
    "requiredConversationResolution": true,
    "enforceAdmins": true
  }
}
```

The caller is responsible for capturing this read-only GitHub state immediately
before the check. Keeping collection outside the checker makes fixture runs
network-independent and prevents the acceptance gate from mutating labels or
branch protection.

The checker resolves `kaizen` from `PATH` and imports that installation's
`dist/config/config.js`, so `.kaizen/config.yml` is validated by the exact
schema in the installed toolchain. `KAIZEN_LOOP_ROOT` may instead point to a
built `kaizen-loop` checkout. A missing toolchain is a contract failure with an
installation remediation.

The target must also contain:

- `policy.mode: pr-only`, `safety.wipLimit <= 5`, and an enabled verifier;
- every organization safety-floor protected path and the `**/.git/**`
  forbidden path in the final `.kaizen/config.yml`;
- the required labels shown above and a non-empty
  `.github/ISSUE_TEMPLATE/kaizen.yml`;
- at least one strict required status check, conversation resolution, and
  administrator enforcement in the observations;
- at least one valid JSON smoke artifact under `docs/smoke-runs/`.

Profile files are not merged by this checker. It deliberately checks the final
`.kaizen/config.yml`, so an overlay cannot hide a removed safety-floor entry.

## Skills manifest

If `skills/skills-manifest.json` is present, every regular file under `skills/`
must be listed and match its lowercase SHA-256 digest. Symlinks and other
special entries are rejected so a vendored path cannot resolve outside the
target repository. The checker also requires `--skill-bundle-manifest FILE`,
an authoritative digest manifest exported by the installed pinned toolchain,
so changing a vendored file and its target-controlled digest together is still
detected:

```json
{
  "version": 1,
  "toolchain": {
    "kaizen-loop": "v0.1.0",
    "builder-agent": "v0.1.0",
    "verifier": "v0.1.0"
  },
  "files": {
    "skills/example/SKILL.md": "<64 lowercase hex characters>"
  }
}
```

When `onboarding/versions.json` exists in the target, its component versions
must contain exactly `kaizen-loop`, `builder-agent`, and `verifier` using
`v0.x.y` release tags, and must match both the target and pinned bundle
`toolchain` objects. Use `--toolchain-manifest FILE` to check a different
version manifest. The pinned bundle manifest uses the same `version`,
`toolchain`, and `files` shape shown above and must come from outside the target
repository.

## Exit behavior and tests

Exit `0` means the contract passed. Exit `1` means one or more mismatches were
reported with remediation text. Exit `2` means the invocation or target path
was invalid.

Run the positive fixture and focused negative fixtures with:

```sh
onboarding/scripts/test-onboarding-contract.sh
```

The fixture suite also verifies that the checker leaves the target unchanged
and consumes the observation snapshot without invoking `gh`.
