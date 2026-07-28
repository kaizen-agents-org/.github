# Onboarding contract checker

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
must be listed and match its lowercase SHA-256 digest:

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
must match `toolchain`. Use `--toolchain-manifest FILE` to check a different
version manifest.

## Exit behavior and tests

Exit `0` means the contract passed. Exit `1` means one or more mismatches were
reported with remediation text. Exit `2` means the invocation or target path
was invalid.

Run the positive fixture and focused negative fixtures with:

```sh
onboarding/scripts/test-onboarding-contract.sh
```
