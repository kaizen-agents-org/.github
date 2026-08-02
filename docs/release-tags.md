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
- `install-kaizen.sh` installs all three components from the published tags and
  the installed `kaizen`, `builder-agent`, and `verifier` commands run.

  **Never verify with `npm install -g "github:owner/repo#tag"`.** For a git
  dependency npm installs devDependencies, runs `prepare`, and packs the
  *result*, discarding build output committed in the tag. A component that
  ships a built `dist/` installs that way with an empty `dist/` and a dangling
  `bin`, and the command appears to work only because an older copy is still on
  `PATH`. The installer therefore clones each pinned tag, builds it, and links
  it — one path for all three components.
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

   The installer clones each pinned tag under `$KAIZEN_HOME/toolchain/`, builds
   it, and links its CLI. If any pinned tag is missing it stops without
   installing anything, which is the intended failure.

   Confirm the commands resolve into those checkouts rather than an older copy
   still on `PATH`, which is how a broken install can look healthy:

   ```sh
   readlink "$(npm prefix -g)/lib/node_modules/kaizen-loop"
   ```

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
