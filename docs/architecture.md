# Kaizen Agents Architecture Notes

These notes describe the intended workflow model behind Kaizen Agents. They are a design reference, not a production guarantee. The system is early-stage and the exact commands, policies, and schemas may change.

## System Model

Kaizen Agents is built around a simple separation:

- **`kaizen-loop` coordinates** task intake, workspace setup, loop control, verification calls, risk decisions, commits, and pull requests.
- **`builder-agent` builds** by understanding requirements, designing a solution, implementing changes, adding tests, and running self-review.
- **`verifier` verifies** by independently evaluating the result and producing a gate verdict.

```mermaid
flowchart TB
    ORG["kaizen-agents-org"]

    ORG --> KL["kaizen-loop<br/>orchestration"]
    ORG --> BA["builder-agent<br/>build + self-improve"]
    ORG --> VF["verifier<br/>independent gate"]

    BA --> KL
    VF --> KL
```

## End-to-End Flow

The main loop starts from a GitHub Issue or task, creates an isolated workspace, delegates implementation, verifies the result, and then chooses whether to create a pull request, commit directly, or stop for human input.

```mermaid
flowchart TB
    A["GitHub Issue<br/>kaizen label"] --> B["kaizen run"]
    B --> C["Preflight<br/>auth / config / locks"]
    C --> D["Issue selection"]
    D --> E["Create isolated workspace<br/>and branch"]
    E --> F["Builder Agent<br/>Claude / Codex implementation"]

    F --> G["Mechanical verification<br/>test / lint / build"]

    G -->|failed| H{"Retry budget<br/>remaining?"}
    H -->|yes| F
    H -->|no| I["Failure comment<br/>needs human"]

    G -->|passed| J["Verifier<br/>spec / design / implementation / tests"]
    J --> K{"Gate passed?"}

    K -->|yes| L["Risk decision"]
    L -->|low risk| M["Direct commit to main<br/>close issue"]
    L -->|high risk| N["Create PR<br/>human review"]

    K -->|no| O["Generate improvement feedback<br/>must_fix / should_fix"]
    O --> P{"Fix target"}
    P -->|design issue| Q["Revise design"]
    P -->|unclear requirement| R["Clarify issue / requirement"]
    P -->|test gap| S["Add tests"]
    P -->|implementation issue| T["Revise implementation"]

    Q --> F
    R --> F
    S --> F
    T --> F

    I --> U["Done"]
    M --> U
    N --> U
```

## Builder-Centered Improvement Loop

This view focuses on the builder's feedback cycle. The builder receives a task, loops internally until self-review passes, then receives external feedback from mechanical verification and the independent verifier.

```mermaid
flowchart TB
    A["GitHub Issue / Linear Task"] --> B["Builder Agent"]

    subgraph Builder["Builder Agent"]
        C["Spec understanding"]
        D["Design"]
        E["Implementation"]
        F["Self-review"]
        G{"Self-review<br/>threshold met?"}

        C --> D --> E --> F --> G
        G -->|no| C
    end

    B --> C
    G -->|yes| H["Mechanical verification<br/>test / lint / build"]

    H -->|failed| I["Retry with error logs"]
    I --> C

    H -->|passed| J["Verifier"]
    J --> K{"Gate passed?"}

    K -->|no| L["Generate improvement feedback"]
    L --> C

    K -->|yes| M["Risk analysis"]
    M -->|low risk| N["Direct commit"]
    M -->|high risk| O["Create PR"]

    N --> P["Done"]
    O --> P
```

## Responsibility Boundaries

Each component has a narrow job. The builder can self-review, but the verifier remains independent and does not implement changes.

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
    Output["Commit / PR"]

    BA5 -->|Yes| MV1
    MV4 -->|Failed| BA1
    MV4 -->|Passed| VF1
    VF5 --> Gate
    Gate -->|No| BA1
    Gate -->|Yes| Output
```

## Builder Internal Loop

The builder owns implementation quality before the external verification stages run.

```mermaid
flowchart TB
    A["Understand requirements"] --> B["Design solution"]
    B --> C["Implement change"]
    C --> D["Add or update tests"]
    D --> E["Self-review"]
    E --> F{"Score >= threshold<br/>and must_fix = 0?"}
    F -->|no| A
    F -->|yes| G["Submit to mechanical verification"]
```

Self-review should produce structured output, such as:

- `score`
- `must_fix`
- `should_fix`
- `confidence`
- notes on residual risk

This output is useful for improvement, but it is not the final gate.

## Gate Decision Model

The verifier evaluates the result after builder self-review and mechanical verification. It should not implement changes.

```mermaid
flowchart TB
    A["Verifier evaluation result"] --> B{"blocking_issues present?"}

    B -->|yes| C["Rejected<br/>return must_fix"]
    B -->|no| D{"Required scores met?"}

    D -->|no| E["Rejected<br/>improve weak areas"]
    D -->|yes| F{"Confidence sufficient?"}

    F -->|no| G["PR-only<br/>human review required"]
    F -->|yes| H["Approved<br/>continue to risk decision"]
```

## Artifact Flow

Each loop should leave behind enough structured information to make the next decision observable.

```mermaid
flowchart TB
    A["Task / Issue"] --> B["Implementation plan"]
    B --> C["Code changes"]
    C --> D["Builder self-review report"]
    D --> E["Mechanical verification logs"]
    E --> F["Verifier report"]

    F --> G{"Gate verdict"}
    G -->|rejected| H["must_fix / should_fix feedback"]
    H --> B

    G -->|approved| I["Risk classification"]
    I --> J["Pull request or direct commit"]
```

## Final Quality Gate

The final quality gate is deliberately layered:

1. Builder self-review
2. Mechanical verification
3. Independent verifier review
4. Human review or repository policy

This prevents the builder from being the only judge of its own output while still using self-review as an improvement mechanism.

## Open Design Areas

- Exact verifier scoring schema
- Retry budget and stopping rules
- Direct-commit policy for low-risk changes
- Human escalation rules
- PR body format and review handoff
- Persistent logs and observability model
