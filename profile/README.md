# Kaizen Agents

Experimental autonomous software development workflows built around **Build -> Verify -> Improve**.

Kaizen Agents is an early-stage organization for exploring continuous improvement loops in software development. The system separates implementation, verification, and orchestration into independent components so each responsibility can evolve without blurring the quality gate.

This work is experimental and in progress. Interfaces, policies, and repository boundaries may change as the workflow matures.

## Core Idea

```mermaid
flowchart LR
    A["Build"] --> B["Verify"]
    B --> C["Improve"]
    C --> A
```

- **Build**: a builder agent implements an approved task in an isolated workspace.
- **Verify**: mechanical checks and an independent verifier evaluate the output.
- **Improve**: feedback loops back into the builder until the change is acceptable or needs human input.

## Core Repositories

| Repository | Responsibility | Status |
| --- | --- | --- |
| `kaizen-loop` | Orchestrates issues, workspaces, agents, verification, risk decisions, commits, and pull requests. | Early-stage |
| `builder-agent` | Implements approved tasks and runs an internal self-review loop before external verification. | Experimental |
| `verifier` | Independently evaluates spec fit, architecture, implementation, tests, maintainability, and risk. | Work in progress |

## Workflow

```mermaid
flowchart TB
    A["GitHub Issue / Linear Task"] --> B["kaizen-loop"]
    B --> C["Create isolated workspace"]
    C --> D["Builder Agent"]

    D --> E["Mechanical Verification<br/>lint / typecheck / test / build"]
    E -->|failed| F["Return logs to Builder"]
    F --> D

    E -->|passed| G["Independent Verifier"]
    G --> H{"Gate passed?"}

    H -->|no| I["Return must_fix / should_fix feedback"]
    I --> D

    H -->|yes| J["Risk / Policy Decision"]
    J -->|low risk and allowed| K["Direct Commit"]
    J -->|review required| L["Pull Request"]

    K --> M["Done"]
    L --> M
```

## Builder Improvement Loop

```mermaid
flowchart TB
    A["GitHub Issue / Linear Task"] --> B["Builder Agent"]

    subgraph Builder["Builder Agent"]
        C["Understand spec"]
        D["Design"]
        E["Implement"]
        F["Self-review"]
        G{"Self-review<br/>threshold met?"}

        C --> D --> E --> F --> G
        G -->|no| C
    end

    B --> C
    G -->|yes| H["Mechanical Verification<br/>test / lint / build"]

    H -->|failed| I["Fix with error logs"]
    I --> C

    H -->|passed| J["Verifier"]
    J --> K{"Gate passed?"}

    K -->|no| L["Generate improvement feedback"]
    L --> C

    K -->|yes| M["Risk Analysis"]
    M -->|low risk| N["Direct Commit"]
    M -->|high risk| O["Create PR"]

    N --> P["Done"]
    O --> P
```

## Responsibility Separation

```mermaid
flowchart LR
    subgraph Builder["builder-agent"]
        A["Spec analysis"]
        B["Architecture"]
        C["Implementation"]
        D["Self-review"]
        E{"Score >= threshold?"}
        A --> B --> C --> D --> E
    end

    subgraph Checks["mechanical verification"]
        F["Lint"]
        G["Typecheck"]
        H["Test"]
        I["Build"]
        F --> G --> H --> I
    end

    subgraph Verifier["verifier"]
        J["Spec review"]
        K["Architecture review"]
        L["Implementation review"]
        M["Test review"]
        N["Gate verdict"]
        J --> K --> L --> M --> N
    end

    subgraph Policy["kaizen-loop policy"]
        O{"Approved?"}
        P["Commit / PR"]
    end

    E -->|no| A
    E -->|yes| F
    I --> J
    N --> O
    O -->|no| A
    O -->|yes| P
```

Builders build. Verifiers verify. Kaizen Loop coordinates.

Builder self-review is useful, but it is not trusted as the final quality gate. The final gate combines:

1. Builder self-review
2. Mechanical verification
3. Independent verifier review
4. Human review or repository policy

## Gate Decision Model

```mermaid
flowchart TB
    A["Verifier Result"] --> B{"Blocking issues?"}
    B -->|yes| C["Rejected<br/>return must_fix"]
    B -->|no| D{"Required scores met?"}

    D -->|no| E["Rejected<br/>improve weak areas"]
    D -->|yes| F{"Confidence sufficient?"}

    F -->|no| G["PR-only<br/>human review required"]
    F -->|yes| H["Approved<br/>continue to risk decision"]
```

## Design Principles

- Separate implementation from evaluation.
- Treat self-review as useful but insufficient.
- Prefer objective verification where possible.
- Keep approval gates explicit.
- Preserve user changes.
- Keep implementation scope constrained.
- Make every loop observable.

## Current Status

Kaizen Agents is early-stage, experimental, and actively changing. The current focus is defining the responsibility boundaries and feedback loops before treating the system as production-ready automation.

## Planned Direction

- `builder-agent` skill and CLI workflows
- `verifier` CLI and structured gate reports
- `kaizen-loop` orchestration over GitHub Issues
- Isolated workspace and branch management
- PR creation and merge-readiness workflows
- Policy-based low-risk direct commits

For deeper workflow details, see [Architecture Notes](https://github.com/kaizen-agents-org/.github/blob/main/docs/architecture.md).
