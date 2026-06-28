# Codex Automations

This directory stores GitHub-managed source prompts for local Codex automations used by the Kaizen Agents organization.

The Codex app stores runtime automation copies under `$CODEX_HOME/automations`. Those local runtime files are not the source of truth. When changing an automation prompt:

1. Update the prompt source in this directory.
2. Sync the local Codex automation from the updated source.
3. Mention the prompt source path in any coordination report or PR that changes automation behavior.

## Managed Prompts

| Automation | Source prompt | Runtime automation |
| --- | --- | --- |
| Kaizen Agents org monitor | [kaizen-agents-org-monitor.prompt.md](./kaizen-agents-org-monitor.prompt.md) | `$CODEX_HOME/automations/kaizen-agents-org-monitor/automation.toml` |
| Kaizen Agents repo improvement scout | [kaizen-agents-repo-improvement-scout.prompt.md](./kaizen-agents-repo-improvement-scout.prompt.md) | `$CODEX_HOME/automations/kaizen-agents-repo-improvement-scout/automation.toml` |
| Kaizen Agents weekly readiness review | [kaizen-agents-weekly-readiness-review.prompt.md](./kaizen-agents-weekly-readiness-review.prompt.md) | `$CODEX_HOME/automations/kaizen-agents-weekly-readiness-review/automation.toml` |
| Kaizen Agents readiness issue creator | [kaizen-agents-readiness-issue-creator.prompt.md](./kaizen-agents-readiness-issue-creator.prompt.md) | `$CODEX_HOME/automations/kaizen-agents-readiness-issue-creator/automation.toml` |
