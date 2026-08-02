# Onboarding profiles

A profile is a partial overlay on the `.kaizen/config.yml` that `kaizen init`
generates. It shapes **throughput and risk appetite** — how many issues a run
picks up, how many Kaizen pull requests may be open at once — for a repository
that has just adopted the harness.

Apply one with:

```sh
kaizen init --profile pilot-node
```

## What a profile may not do

Three settings are fixed by the organization safety floor and are rejected
outright if a profile sets them:

| Setting | Fixed value | Reason |
|---|---|---|
| `policy.mode` | `pr-only` | Every change is reviewed by a human before merge. |
| `verifier.enabled` | `true` | The verification gate is not optional. |
| `safety.operationMode` | `external` | Adopters are not org dogfood targets. |

Two more are corrected rather than rejected, because a profile can weaken them
by omission rather than intent: the safety-floor `policy.protectedPaths` and
`policy.forbiddenPaths` entries are restored, and `safety.wipLimit` is capped at
5. `kaizen init` prints a warning naming each correction it made.

Both layers exist on purpose. `kaizen init` enforces the floor when the config
is written, and the onboarding contract checker re-validates the *final*
`.kaizen/config.yml`, so hand-editing the file after init cannot smuggle a
weakened floor past acceptance either.

## What a profile deliberately omits

Verification commands. `kaizen init` proposes them from stack detection and the
operator confirms them. What counts as "verified" is the root of the trust
model, so a profile that has never seen the repository must not decide it.

## Choosing one

Start on `pilot-*` matching the repository's primary stack. The pilot profiles
allow one issue per run and one open pull request. Move to `standard.yml` only
once weekly metrics show stable throughput and the review bandwidth to match.

## Source of truth

This directory is authoritative. `kaizen-loop/profiles/` is a vendored copy so
`kaizen init` works without network access; CI fails if the two diverge.
