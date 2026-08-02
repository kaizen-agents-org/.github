# Kaizen Toolchain Release Tags

The onboarding kit installs `kaizen-loop`, `builder-agent`, and `verifier`
from pinned GitHub tags until the components are published through a package or
image registry. The pinned set lives in
[`onboarding/versions.json`](../onboarding/versions.json).

## Versioning

- Use semver tags with a leading `v`, starting at `v0.1.0`.
- Patch releases (`v0.x.y`) are compatible bug fixes for an existing minor
  toolchain line.
- Minor releases (`v0.x.0`) may change component contracts, but only when the
  full three-component set is verified and `onboarding/versions.json` is bumped
  in the same release PR.
- Do not publish a component tag that is not intended to be usable by the
  manifest. If a bad tag is pushed, leave it in place and publish a fixed patch
  tag instead.

## Compatible Set

A compatible set is one tag for each component:

```json
{
  "kaizen-loop": "v0.1.0",
  "builder-agent": "v0.1.0",
  "verifier": "v0.1.0"
}
```

Before accepting a set in `onboarding/versions.json` as released, verify all of the
following against the exact commits to be tagged:

- `kaizen-loop`, `builder-agent`, and `verifier` each build and test on Node
  20 or newer.
- `npm install -g "github:kaizen-agents-org/<repo>#<tag>"` succeeds for
  `kaizen-loop` and `builder-agent` after the tags exist, and the installed
  `kaizen` and `builder-agent` commands run. Both commit their `dist/` output
  and guard it with `npm run check:dist`, so a GitHub install needs no build
  step; confirm that check passes at the commit being tagged.
- `verifier` installs through `install-kaizen.sh`, not through
  `npm install -g github:`. Its root package is a private pnpm workspace with
  no `bin`, and the CLI lives in `packages/core`, so the installer clones the
  pinned tag, runs `pnpm install --frozen-lockfile && pnpm build`, and links
  `packages/core`. Verify that path instead for this component.
- A clean-machine install from `onboarding/versions.json` can run
  `kaizen doctor` successfully.
- A Kaizen smoke run passes with the pinned set.

The first onboarding manifest reserves `v0.1.0` for all three components. Treat
that manifest as a release candidate until the matching component tags exist and
the install checks above are recorded in the release PR.

## Release Checklist

Run this checklist for each compatible set.

1. Choose the target commits on `main` for `kaizen-loop`, `builder-agent`, and
   `verifier`.
2. Verify each component locally from the target commit using its repository
   test, typecheck, build, and package checks.
3. Run a cross-component Kaizen smoke using those exact checkouts.
4. Create annotated tags in the component repositories:

   ```sh
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

5. From a clean environment, verify the install path the onboarding kit
   actually uses. Bump `onboarding/versions.json` to the new tags first, then
   let the installer resolve them:

   ```sh
   onboarding/scripts/install-kaizen.sh
   kaizen doctor
   builder-agent --version
   verifier --version
   ```

   The installer takes `kaizen-loop` and `builder-agent` from
   `npm install -g github:`, and builds `verifier` from its pinned tag (see the
   note above). Do not verify with three bare `npm install -g github:` commands:
   that path cannot work for `verifier`. If any pinned tag is missing the
   installer stops without installing anything, which is the intended failure.

6. Update `onboarding/versions.json` in this repository to the verified set.
7. Open a ready-for-review PR that includes the manifest bump and the
   verification evidence. Include the source issue closing keyword in the PR
   body.

## Component Repository Notes

Each component repository should keep a short `docs/release-tags.md` or
equivalent checklist that points back to this file and records any
repo-specific build-on-install caveats. The component-local checklist should
not redefine compatibility; this repository's `onboarding/versions.json` is
the compatibility source of truth for the onboarding kit.
