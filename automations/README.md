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
