# Kaizen Agents MVP Plan

This plan defines the shortest path to make `kaizen-agents-org` usable as an end-to-end workflow.

The first usable milestone is not full autonomy. The first milestone is:

> Process one GitHub Issue, let `builder-agent` produce a change, let `kaizen-loop` run checks and create a PR, and let `verifier` return an independent gate result.

## Current State

- **`kaizen-loop`** already has the strongest implementation base. It is a TypeScript CLI with commands such as `kaizen run`, `kaizen fix`, `kaizen doctor`, `kaizen report`, verification retries, agent selection, and PR-oriented workflow pieces.
- **`builder-agent`** has local skill and prompt files, but those files still need to be committed and reviewed as the first usable builder package.
- **`verifier`** is still close to initial state locally. Its first useful version should be a small independent gate that returns structured results.
- **`.github`** contains the Organization profile and architecture docs that describe the intended responsibility boundaries.

## Phase 0: Repository Baseline

Goal: make the repository set understandable and stable enough to coordinate.

1. Merge the Organization profile and architecture documentation.
2. Turn the local `builder-agent` skill, prompts, and docs into a reviewed PR.
3. Confirm source-of-truth locations for `kaizen-loop` and `verifier`, including local paths and GitHub remotes.
4. Confirm branch and PR conventions across all repositories.
5. Keep the initial scope explicit: build, verify, and open a PR; do not claim production-ready automation.

Done when:

- The Organization profile explains the system clearly.
- Each core repository has a README that states its responsibility.
- Local checkouts and GitHub remotes are aligned.

## Phase 1: Minimal Vertical Slice

Goal: connect the three components with the smallest working contract.

### builder-agent

Start as a Codex-compatible skill rather than a CLI.

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

- `approved`, `rejected`, or `pr_only`
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
- create a PR for review-required changes

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
7. Treat the first passing result as review-required and create a PR.
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
5. Define `needs-human`, `pr_only`, and direct-commit behavior.
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
2. Create a PR for the local `builder-agent` skill and prompts.
3. Create the first minimal verifier contract and implementation.
4. Wire `kaizen-loop` to call the builder and verifier through the initial contract.
5. Run one end-to-end smoke test and capture the result.
