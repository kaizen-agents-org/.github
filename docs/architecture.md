# Kaizen Agents Architecture Notes

These notes describe the intended workflow model behind Kaizen Agents. They are a design reference for an early-stage, experimental system, not a production guarantee.

The central principle is simple:

> Builders build. Verifiers verify. Kaizen Loop coordinates.

## Product Goal

The target user experience is:

1. A user registers an issue.
2. `kaizen-loop` selects the issue and creates an isolated workspace.
3. `builder-agent` produces a focused implementation.
4. Mechanical verification and `verifier` evaluate the result.
5. The system opens a high-quality pull request with enough context for review.
6. A human maintainer reviews and merges the PR.
7. The original issue is resolved by that merge.

The system optimizes for high-quality, reviewable PRs rather than unreviewed autonomy. Human merge remains the normal completion point for meaningful changes.

## Repository Map

```mermaid
flowchart TB
    ORG["kaizen-agents-org"]

    ORG --> KL["kaizen-loop<br/>orchestration"]
    ORG --> BA["builder-agent<br/>build + self-improve"]
    ORG --> VF["verifier<br/>independent quality gate"]

    KL --> BA
    KL --> VF
```

| Repository | Primary responsibility | Does not own |
| --- | --- | --- |
| `kaizen-loop` | Orchestration, workspace lifecycle, loop control, policy decisions, branch pushes, and PR creation. | Implementing code changes or judging quality directly. |
| `builder-agent` | Requirement understanding, design, implementation, tests, and self-review. | Final approval. |
| `verifier` | Independent review, scoring, risk assessment, and gate verdicts. | Editing the implementation. |

## Standalone And Integrated Use

The three projects should compose into one workflow, but each should also remain useful by itself.

```mermaid
flowchart TB
    subgraph Standalone["Standalone usage"]
        A["builder-agent<br/>implement a requested change"]
        B["verifier<br/>evaluate an existing diff"]
        C["kaizen-loop<br/>coordinate issue workflows through adapters"]
    end

    subgraph Integrated["Integrated workflow"]
        D["Issue"] --> E["kaizen-loop"]
        E --> F["builder-agent"]
        F --> G["Mechanical verification"]
        G --> H["verifier"]
        H --> I["Pull Request"]
    end
```

This means integration boundaries should be explicit. `kaizen-loop` can call the builder and verifier, but the builder and verifier should not require `kaizen-loop` to be valuable.

## Current MVP Snapshot

The architecture above is now partially implemented as a usable MVP slice. `kaizen-loop` Phase 2 support can coordinate builder-agent-based fixes, isolated per-issue worktrees, configured mechanical verification, verifier review, ready-for-review PR creation, scheduler registration, opt-in queueing, operational commands, and `pr-guardian` follow-up.

`builder-agent` is available as a standalone MVP CLI and Codex-compatible skill. `verifier` is available as a minimal runnable `verifier check` CLI and can write Kaizen Loop verdict payloads through `KAIZEN_VERIFIER_RESULT_PATH`.

The remaining gap is no longer "no runnable builder/verifier path." The gap is hardening the MVP contracts, improving artifacts and evidence quality, and expanding `verifier` from the minimal verdict gate toward the fuller staged review model described below.

## Component Process Flows

Each repository owns a different part of the loop. The system is easier to reason about when those processes are described independently.

### kaizen-loop

`kaizen-loop` is the coordinator. It does not implement code or make the verifier's quality judgment itself; it connects the task source, workspace, agents, checks, and repository policy.

```mermaid
flowchart TB
    KL1["Read task source<br/>GitHub Issue / Linear Task"] --> KL2["Run preflight<br/>auth / config / locks"]
    KL2 --> KL3["Select task"]
    KL3 --> KL4["Create isolated workspace<br/>and branch"]
    KL4 --> KL5["Run builder-agent"]
    KL5 --> KL6["Run mechanical verification"]
    KL6 --> KL7{"Checks passed?"}

    KL7 -->|no| KL8["Return logs to builder<br/>or stop at retry limit"]
    KL8 --> KL5

    KL7 -->|yes| KL9["Run verifier"]
    KL9 --> KL10{"Gate passed?"}

    KL10 -->|no| KL11["Return verifier feedback<br/>must_fix / should_fix"]
    KL11 --> KL5

    KL10 -->|yes| KL12["Apply repository policy"]
    KL12 -->|MVP default| KL14["Create ready-for-review PR"]
    KL12 -->|explicit later opt-in| KL13["Direct commit and close task"]
```

### builder-agent

`builder-agent` owns implementation. It may self-review and improve its own output, but that self-review is an internal quality loop rather than the final gate.

```mermaid
flowchart TB
    BA1["Receive task context"] --> BA2["Understand requirements"]
    BA2 --> BA3["Design solution"]
    BA3 --> BA4["Implement change"]
    BA4 --> BA5["Add or update tests"]
    BA5 --> BA6["Self-review"]
    BA6 --> BA7{"Threshold met<br/>and must_fix = 0?"}

    BA7 -->|no| BA2
    BA7 -->|yes| BA8["Return code changes<br/>and self-review report"]

    BA9["Receive external feedback<br/>logs / verifier comments"] --> BA2
```

### verifier

`verifier` evaluates the completed change independently. It should produce structured output that can drive the next loop, but it should not edit the implementation.

```mermaid
flowchart TB
    VF1["Receive task, diff,<br/>checks, and builder report"] --> VF2["Review spec fit"]
    VF2 --> VF3["Review architecture"]
    VF3 --> VF4["Review implementation"]
    VF4 --> VF5["Review tests"]
    VF5 --> VF6["Review maintainability<br/>and risk"]
    VF6 --> VF7["Produce structured result<br/>scores / issues / confidence"]
    VF7 --> VF8{"Gate verdict"}

    VF8 -->|block_pr| VF9["Return must_fix<br/>and weak areas"]
    VF8 -->|needs_context| VF10["Require human clarification"]
    VF8 -->|open_pr / open_pr_with_warning| VF11["Continue to risk decision"]
```

## End-to-End Workflow

The main workflow starts from an approved task and continues until the change is opened as a PR or handed back to a human. Direct commit is a later repository-level opt-in, not the MVP default.

```mermaid
flowchart TB
    Task["GitHub Issue / Linear Task<br/>kaizen label"] --> Run["kaizen run"]
    Run --> Preflight["Preflight<br/>auth / config / locks"]
    Preflight --> Select["Select task"]
    Select --> Workspace["Create isolated workspace<br/>and branch"]
    Workspace --> Builder["Builder Agent<br/>implements change"]

    Builder --> Checks["Mechanical verification<br/>test / lint / build"]
    Checks -->|failed| Retry{"Retry budget<br/>remaining?"}
    Retry -->|yes| Builder
    Retry -->|no| Human["Leave failure comment<br/>needs human"]

    Checks -->|passed| Verifier["Verifier<br/>spec / design / implementation / tests"]
    Verifier --> Gate{"Gate passed?"}

    Gate -->|no| Feedback["Generate improvement feedback<br/>must_fix / should_fix"]
    Feedback --> Target{"Fix target"}
    Target -->|design issue| Design["Revise design"]
    Target -->|unclear requirement| Requirement["Clarify issue / requirement"]
    Target -->|test gap| Tests["Add tests"]
    Target -->|implementation issue| Implementation["Revise implementation"]

    Design --> Builder
    Requirement --> Builder
    Tests --> Builder
    Implementation --> Builder

    Gate -->|yes| Risk["Repository policy"]
    Risk -->|MVP default| PR["Create PR<br/>human review"]
    Risk -->|explicit later opt-in| Commit["Direct commit<br/>close task"]

    Human --> Done["Done"]
    Commit --> Done
    PR --> Done
```

## Responsibility Pipeline

This is the clearest view of the core responsibility boundary. The builder has an internal quality loop, mechanical verification catches objective failures, and the verifier makes an independent approval decision.

```mermaid
flowchart LR
    subgraph BuilderAgent["BuilderAgent"]
        BA1["Spec Analysis"]
        BA2["Architecture"]
        BA3["Implementation"]
        BA4["Self Review"]
        BA5{"Score >= Threshold?"}
        BA1 --> BA2 --> BA3 --> BA4 --> BA5
        BA5 -->|No| BA1
    end

    subgraph MechanicalVerification["Mechanical Verification"]
        MV1["Lint"]
        MV2["TypeCheck"]
        MV3["Test"]
        MV4["Build"]
        MV1 --> MV2 --> MV3 --> MV4
    end

    subgraph Verifier["Verifier"]
        VF1["Spec Review"]
        VF2["Architecture Review"]
        VF3["Code Review"]
        VF4["Test Review"]
        VF5["Risk Review"]
        VF1 --> VF2 --> VF3 --> VF4 --> VF5
    end

    Gate{"Approved?"}
    Output["Ready-for-review PR"]

    BA5 -->|Yes| MV1
    MV4 -->|Failed| BA1
    MV4 -->|Passed| VF1
    VF5 --> Gate
    Gate -->|No| BA1
    Gate -->|Yes| Output
```

## Builder Improvement Loop

The builder is allowed to self-review and improve its own work before external verification. That self-review is useful for iteration, but it is not trusted as the final gate.

```mermaid
flowchart TB
    Task["GitHub Issue / Linear Task"] --> Start["Builder Agent"]

    subgraph BuilderAgent["Builder Agent"]
        Spec["Spec understanding"]
        Design["Design"]
        Implement["Implementation"]
        SelfReview["Self-review"]
        Threshold{"Self-review<br/>threshold met?"}

        Spec --> Design --> Implement --> SelfReview --> Threshold
        Threshold -->|no| Spec
    end

    Start --> Spec
    Threshold -->|yes| Checks["Mechanical verification<br/>test / lint / build"]

    Checks -->|failed| Logs["Retry with error logs"]
    Logs --> Spec

    Checks -->|passed| Verifier["Verifier"]
    Verifier --> Gate{"Gate passed?"}

    Gate -->|no| Feedback["Generate improvement feedback"]
    Feedback --> Spec

    Gate -->|yes| Risk["Repository policy"]
    Risk -->|MVP default| PR["Create PR"]
    Risk -->|explicit later opt-in| Commit["Direct commit"]

    Commit --> Done["Done"]
    PR --> Done
```

Structured self-review output should include enough information to drive the next loop:

- `score`
- `must_fix`
- `should_fix`
- `confidence`
- residual risk notes

## Gate Decision Model

The verifier runs after builder self-review and mechanical verification. It evaluates the completed change without editing it.

```mermaid
flowchart TB
    Result["Verifier evaluation result"] --> Blocking{"blocking_issues present?"}

    Blocking -->|yes| MustFix["block_pr<br/>return must_fix"]
    Blocking -->|no| Scores{"Required scores met?"}

    Scores -->|no| Improve["block_pr<br/>improve weak areas"]
    Scores -->|yes| Confidence{"Confidence sufficient?"}

    Confidence -->|no| Warning["open_pr_with_warning<br/>show risk to reviewers"]
    Confidence -->|yes| OpenPR["open_pr<br/>continue to risk decision"]
```

The MVP gate has four meaningful outcomes:

- **`open_pr`**: no blocking or warning signal was found; continue to ready-for-review PR creation.
- **`open_pr_with_warning`**: no blocking issue is known, but non-blocking risk should be shown to reviewers.
- **`block_pr`**: the builder must address `must_fix` items or weak scoring areas before PR creation.
- **`needs_context`**: task or diff context is insufficient; stop for human clarification.

## Artifact Flow

Every loop should leave behind enough structured information to make the next decision observable.

```mermaid
flowchart TB
    Task["Task / Issue"] --> Plan["Implementation plan"]
    Plan --> Changes["Code changes"]
    Changes --> SelfReview["Builder self-review report"]
    SelfReview --> Logs["Mechanical verification logs"]
    Logs --> Report["Verifier report"]

    Report --> Verdict{"Gate verdict"}
    Verdict -->|block_pr| Feedback["must_fix / should_fix feedback"]
    Feedback --> Plan

    Verdict -->|open_pr / open_pr_with_warning| Risk["Repository policy"]
    Risk --> Output["Ready-for-review PR"]
```

## Documentation And Issue Intake

The organization documentation is part of the coordination contract. Automated monitor issues and cross-repository follow-up work should be grounded in the closest relevant source:

1. Organization Profile for public product framing and current project status.
2. Repository README for shared assets and local repository responsibilities.
3. Architecture Notes for component boundaries, workflow shape, and quality gates.
4. Issue-to-PR MVP for target repository runtime contracts.
5. Project-local README/docs for repository-specific commands and behavior.

If those sources do not support a proposed issue, the correct output is a documentation drift report or clarification request, not a speculative implementation issue. When an issue is created, include a concise `Documentation basis` section with the cited document paths or URLs and the reason they apply.

## Final Quality Gate

The final quality gate is deliberately layered:

1. Builder self-review
2. Mechanical verification
3. Independent verifier review
4. Human review or repository policy

This prevents the builder from being the only judge of its own output while still using self-review as an improvement mechanism.

## Current Design Questions

- Exact verifier scoring schema
- Retry budget and stopping rules
- Later opt-in direct-commit policy for low-risk changes
- Human escalation rules
- PR body format and review handoff
- Persistent logs and observability model
