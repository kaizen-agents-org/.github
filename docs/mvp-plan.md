# Kaizen Agents MVP Plan

This plan defines the shortest path to make `kaizen-agents-org` usable as an end-to-end workflow.

## Product Goal

The goal is a system where registering an issue leads to a high-quality pull request that solves the issue. A human maintainer reviews and merges that PR, and the merge is what resolves the original problem.

That means the MVP should optimize for:

- selecting the right issue
- producing a focused, reviewable implementation
- verifying the change before PR creation
- explaining the solution and residual risk in the PR
- keeping the human maintainer in control of the merge

The first usable milestone is not full autonomy. The first milestone is:

> Process one GitHub Issue, let `builder-agent` produce a change, let `kaizen-loop` run checks and create a PR, and let `verifier` return an independent gate result.

See [Issue-to-PR MVP](./issue-to-pr-mvp.md) for the organization-level contract that should be installed into each target repository.

## Current State

- **`kaizen-loop`** already has the strongest implementation base. It is a TypeScript CLI with commands such as `kaizen run`, `kaizen fix`, `kaizen doctor`, `kaizen report`, verification retries, agent selection, and PR-oriented workflow pieces.
- **`builder-agent`** has a shipped MVP CLI, local skill, schemas, tests, and a Kaizen integration payload for the build phase.
- **`verifier`** has a shipped MVP CLI that returns `open_pr`, `open_pr_with_warning`, `block_pr`, or `needs_context`. The fuller staged verifier remains future work.
- **`.github`** contains the Organization profile and architecture docs that describe the intended responsibility boundaries.

## Phase 0: Repository Baseline

Goal: make the repository set understandable and stable enough to coordinate.

1. Merge the Organization profile and architecture documentation.
2. Keep the shipped `builder-agent` skill, prompts, CLI, and docs aligned.
3. Confirm source-of-truth locations for `kaizen-loop` and `verifier`, including local paths and GitHub remotes.
4. Confirm branch and PR conventions across all repositories.
5. Keep the initial scope explicit: build, verify, and open a PR; do not claim production-ready automation.

Done when:

- The Organization profile explains the system clearly.
- Each core repository has a README that states its responsibility.
- Local checkouts and GitHub remotes are aligned.

## Phase 1: Minimal Vertical Slice

Goal: connect the three components with the smallest working contract.

The vertical slice should not make the components inseparable. Each component should expose a usable standalone path first, then `kaizen-loop` should compose those paths through explicit contracts.

### builder-agent

The MVP includes both a Codex-compatible skill and a small CLI.

Inputs:

- task or issue description
- optional goal
- optional constraints
- review threshold
- maximum iteration count

Outputs:

- code changes in the current workspace
- structured self-review report
- final build result

Required behavior:

- understand the task
- inspect the repository
- create a small implementation plan
- implement the change
- add or update tests where appropriate
- self-review
- loop until the threshold is met or progress is blocked

### verifier

Start as a minimal skill or CLI that evaluates a completed change without editing it.

Inputs:

- task description
- diff or changed files
- mechanical verification logs
- builder self-review report

Outputs:

- `open_pr`, `open_pr_with_warning`, `block_pr`, or `needs_context`
- `must_fix`
- `should_fix`
- `confidence`
- `risk`

Required behavior:

- review spec fit
- review architecture
- review implementation
- review tests
- review maintainability and risk
- produce a structured gate verdict

### kaizen-loop

Use the existing CLI as the orchestrator.

Required behavior:

- select a GitHub Issue or task
- create an isolated workspace and branch
- invoke `builder-agent`
- run mechanical verification
- invoke `verifier`
- loop on feedback when needed
- create a regular ready-for-review PR by default

Done when:

- A single issue can move through builder, checks, verifier, and PR creation.
- Failure cases produce useful logs or comments.
- The verifier decision is visible in the workflow output.

## Phase 2: End-to-End Smoke Test

Goal: prove that the vertical slice works in a controlled repo.

1. Create or choose a small test repository.
2. Create a GitHub Issue with a `kaizen` label.
3. Run `kaizen run --dry-run` to verify task selection and planned actions.
4. Run `kaizen run` to execute the builder.
5. Run lint, typecheck, test, and build through the configured mechanical verification.
6. Run the verifier on the resulting change.
7. Treat the first passing result as review-required and create a ready-for-review PR.
8. Record the output as an example workflow.

Done when:

- One issue produces one PR.
- The PR body includes the task, checks, builder self-review, verifier result, and known risk.
- The workflow can be repeated on another small issue.

## Phase 3: Gate Contracts

Goal: make the quality gates predictable.

1. Define the builder self-review schema.
2. Define the verifier result schema.
3. Define `must_fix`, `should_fix`, `confidence`, and `risk` semantics.
4. Define retry budget and stopping rules.
5. Define `needs_context`, `open_pr_with_warning`, and later opt-in direct-commit behavior.
6. Add `kaizen doctor` checks for builder and verifier setup.

Done when:

- `kaizen-loop` can validate builder and verifier outputs.
- Bad or incomplete outputs fail clearly.
- Gate decisions are stable enough for tests.

## Phase 4: Operational Readiness

Goal: make the system usable by someone who did not build it.

1. Add quickstart documentation.
2. Add a sample issue and expected PR output.
3. Add examples or fixtures for a smoke-test repo.
4. Add CI for `kaizen-loop` tests, typecheck, and build.
5. Add regression checks for builder and verifier prompt/schema behavior.
6. Keep cross-repo monitoring active for responsibility drift, open PRs, and docs mismatch.

Done when:

- A new contributor can run the smoke test from docs.
- CI covers the main orchestrator.
- The builder and verifier contracts are documented and exercised.

## Immediate Next Actions

1. Review and merge the Organization documentation PR.
2. Keep the `builder-agent` MVP contract stable as `kaizen-loop` integration matures.
3. Expand verifier behavior beyond the minimal verdict CLI while preserving the MVP status vocabulary.
4. Harden `kaizen-loop` feedback loops for `block_pr` and `needs_context`.
5. Run repeated end-to-end smoke tests and capture the results.

## Implementation Order

The current implementation priority is:

1. Harden `kaizen-loop` integration with the shipped `builder-agent` and `verifier` MVP CLIs.
2. Improve builder artifacts and verifier feedback quality.
3. Expand the verifier toward staged review.
4. Strengthen PR guardian and CI follow-up behavior.
5. Product Kaizen Skill.

The Product Kaizen Skill is intentionally later because it answers what to build. The current system is focused on how to build a requested change with higher quality.
