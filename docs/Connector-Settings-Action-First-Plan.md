# Connector Settings Action-First Plan

Date: 2026-03-11
Status: proposed follow-up after MCP7 guided setup

## Goal

Refactor `Settings > Connectors` so the screen answers three user questions in order:

1. Is this client set up?
2. What should I do next?
3. If it failed, how do I fix it?

The screen should stop behaving like an information dump. Every visible element must either:

- trigger setup
- trigger verification
- help fix a failure
- open the exact config the user must edit

## Primary User Jobs

### 1. Install / Set Up

The user arrives because they want Backtick available in `Claude Code` or `Codex`.

Primary action:

- `Copy Add Command`

Supporting actions:

- `Open Config`
- `Copy Config Snippet`
- `Open Docs`

### 2. Verify

The user already added Backtick and now wants to confirm the local server works.

Primary action:

- `Run Test`

Supporting actions:

- `Copy Launch Command`
- `Open Config`

### 3. Fix

The user hit a failure and needs a concrete next step.

Failure handling must be cause-specific:

- `CLI not found` -> install client / open docs
- `Backtick missing from config` -> copy add command / open config
- `Launch command unavailable` -> show build/setup path
- `Server test failed` -> show last failure detail and rerun
- `Claude automation allowlist missing` -> copy allowlist example

### 4. Manual Setup / Troubleshooting

This is not default content. It only exists as a fallback path for users who need to edit files manually or inspect error detail.

## Information Hierarchy

### Default Surface

The first visible content should be:

- Backtick MCP server status
- Claude Code setup status
- Codex setup status
- one primary action per card

The default surface should not show:

- raw repository path
- raw CLI path
- long prose
- full config snippets
- diagnostic detail that does not change the next action

### Secondary Surface

Replace generic `Advanced` with intent-based disclosures:

- `Manual Setup`
- `Troubleshooting`
- `Automation` for Claude-specific allowlist friction

## State Model

Server state:

- `Needs build`
- `Available`
- `Testing`
- `Local server OK`
- `Local test failed`

Client state:

- `CLI not found`
- `Needs setup`
- `Set up in project`
- `Set up in home`
- `Set up in both`
- `Needs attention`

These states must stay separate. A server test pass must not label a client as generically `Connected`.

## Card Layout

Each connector card should contain:

- client name
- setup chip
- verification chip
- one-line summary
- one primary CTA
- at most two secondary actions

Suggested CTA priority:

- `Needs setup` -> `Copy Add Command`
- `Set up but not verified` -> `Run Test`
- `Needs attention` -> `Show Fix`
- `CLI not found` -> `Open Docs`
- `Local server OK` -> no loud CTA, keep `Open Config` or `Run Test`

## Content Rules

Good labels:

- `Needs setup`
- `Run Test`
- `Open Config`
- `Copy Add Command`
- `Manual Setup`
- `Troubleshooting`
- `Automation`

Bad labels:

- `Config file present, Backtick missing`
- `Backtick is configured, but the latest local server test failed...`
- generic `Advanced`

## Keep / Remove Audit

Keep on the default surface:

- setup status
- verification status
- primary action
- short summary

Move behind disclosure:

- project config path
- home config path
- full snippet
- launch command
- last test detail
- automation example

Remove from the default surface:

- repository path
- raw CLI path when the CLI is already detected
- explanatory prose that does not unlock an action

## Implementation Targets

Primary implementation files:

- `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`
- `PromptCue/UI/Settings/PromptCueSettingsView.swift`
- `PromptCueTests/MCPConnectorSettingsModelTests.swift`

Follow-up docs to align after implementation:

- `docs/Implementation-Plan.md`
- `docs/Master-Board.md`

## Test Plan

Automated:

- `Needs setup` prefers `Copy Add Command`
- `CLI not found` has no misleading setup CTA
- `Configured but not verified` prefers `Run Test`
- `Failure states` surface fix detail, not only error text
- `Claude automation` exposes allowlist example only when relevant

Manual:

- default surface shows next action without opening disclosures
- `Manual Setup` contains config editing actions only
- `Troubleshooting` contains failure detail only
- success state becomes visually quiet

## Acceptance Criteria

The screen passes if a user can answer these immediately:

- `Am I set up?`
- `What should I click now?`
- `If this failed, where do I fix it?`

The screen fails if users must read long descriptions or inspect raw paths before they know what to do next.
