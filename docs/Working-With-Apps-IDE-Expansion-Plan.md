# Working With Apps IDE Expansion Plan

## Scope

This document is a focused docs-only plan for expanding `working with apps` beyond terminal targets to IDE targets.

This plan covers:

- IDE support tiers
- supported bundle identifiers
- source kinds
- fallback labeling rules when cwd or repo cannot be resolved
- chooser information architecture
- visual and hierarchy constraints for capture and stack

This plan does not change the existing terminal-first implementation contract in [Working-With-Apps-PR-Plan.md](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/docs/Working-With-Apps-PR-Plan.md).

## Goal

Prompt Cue should treat active developer tools as origin candidates, not just terminals.

The next slice should support:

- Antigravity
- Cursor
- Codex
- Xcode
- future VS Code
- future Windsurf

When Prompt Cue can resolve repo or cwd, it should continue to prefer repo-aware labeling.

When Prompt Cue cannot resolve repo or cwd, it must still provide a usable chooser row and card label using window-title fallback.

## Main UI Constraint

`working with apps` must remain an accessory feature.

Capture and stack must preserve the main visual standards already locked in [Working-With-Apps-PR-Plan.md](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/docs/Working-With-Apps-PR-Plan.md):

- capture keeps the existing `SearchFieldSurface` shell, centered layout, placeholder hierarchy, and quiet floating behavior
- stack keeps the existing `CardSurface(style: .notification)` card shell, action column, and padding rhythm
- app-origin UI stays below the main text hierarchy
- origin selection must read as accessory metadata, never as a second primary surface

This rule applies equally to:

- origin chooser entry points
- chooser rows
- card metadata
- fallback labels

## Source Kinds

Prompt Cue should explicitly distinguish source kinds in the model:

- `terminal`
- `ide`

The source kind is not just presentation metadata.

It controls:

- chooser grouping
- resolution strategy
- fallback heuristics
- ranking behavior
- future export or direct-send routing decisions

## Support Tiers

### Tier 0: Existing Terminal Baseline

Already in scope and must remain supported:

- Terminal
- iTerm2

These remain `sourceKind = terminal`.

### Tier 1: IDE Support In Initial Expansion

These are the first IDEs to support in the next implementation slice:

- Antigravity
- Cursor
- Codex
- Xcode

These should all resolve as `sourceKind = ide`.

Tier 1 requirement:

- if repo or cwd is available, use it
- if repo or cwd is not available, still surface a usable chooser row via window-title fallback

### Tier 2: Planned Next

These should be designed into the contract now even if implemented later:

- Visual Studio Code
- Windsurf

Tier 2 should use the same `ide` source kind and chooser grouping as Tier 1.

## Supported Bundle Identifiers

### Terminal Baseline

- `com.apple.Terminal`
- `com.googlecode.iterm2`

### Tier 1 IDEs

- `com.google.antigravity`
- `com.todesktop.230313mzl4w4u92` for Cursor
- `com.openai.codex`
- `com.apple.dt.Xcode`

### Tier 2 Planned

- `com.microsoft.VSCode`
- `com.exafunction.windsurf`

Note:

- the Tier 1 bundle identifiers above were resolved from installed apps in the current environment
- the Tier 2 bundle identifiers should be re-verified on the implementation machine before code is locked

## Resolution Strategy By Source Kind

### Terminal

Terminal resolution stays repo-first:

- session identifier if available
- tty
- cwd
- git repo root
- repo name
- branch

This remains the highest-confidence path.

### IDE

IDE resolution should use a separate path from terminal session discovery.

Preferred order:

1. direct workspace or project path if the app can expose it
2. current document path if the app can expose it
3. inferred repo root from an exposed path
4. inferred cwd-like workspace label from app-specific metadata
5. window title fallback

The key rule is that IDE support must not depend on terminal-only assumptions like tty or session identifiers.

## Fallback Rules

Fallback is required, not optional.

If Prompt Cue cannot resolve cwd or repo for an IDE target, it must still create a valid suggested target using these rules.

### Fallback Label Priority

Use the first available value from this order:

1. `repositoryName`
2. cwd leaf or workspace directory leaf
3. primary document or project leaf
4. sanitized window title
5. app name

### Fallback Secondary Label Priority

Use the first available value from this order:

1. branch
2. app name plus a shortened document or workspace detail
3. app name plus sanitized window title
4. app name only

### Fallback Confidence

Suggested confidence levels:

- `high` when repo root or cwd is resolved
- `medium` when a workspace or project path is resolved but repo is not
- `low` when Prompt Cue only has a window title or app name

### Window Title Sanitization

When Prompt Cue falls back to window title, it should normalize the title before display:

- trim whitespace
- drop empty titles
- strip duplicated app suffixes when obvious
- prefer the most workspace-like segment when titles are separator-based
- truncate to the same compact width rules already used by `workspaceLabel`

The fallback title is for labeling, not for pretending repo certainty.

## Chooser Information Architecture

The chooser should expand from terminal-only to mixed-source grouping without changing its visual role.

Top-level grouping:

- `Recent`
- `Open Terminals`
- `Open IDEs`

Rules:

- `Recent` contains the current automatic suggestion, regardless of source kind
- `Open Terminals` lists terminal targets only
- `Open IDEs` lists IDE targets only
- omit empty sections
- preserve current compact row styling and keyboard behavior

### Ranking

Within each section:

- automatic recent target first in `Recent`
- then active windows sorted by source-aware identity
- repo-aware rows ahead of title-only rows
- stable alphabetical fallback when confidence ties

### Row Content

Each row should show only compact identity:

- app icon
- primary workspace label
- secondary label

Do not add:

- raw cwd paths as primary content
- confidence badges in the main row
- long explanatory text

Debug detail can remain elsewhere if needed, but not in the core chooser hierarchy.

## Capture And Stack Hierarchy Rules

The accessory hierarchy must remain explicit.

### Capture

- the main text editor stays visually dominant
- screenshot accessory, if present, stays above origin controls in priority
- the app-origin chooser entry point stays secondary to both text and screenshot
- adding IDEs must not introduce a second shell, a separate command palette, or a heavy browser-like toolbar

### Stack

- card text remains first
- card actions remain fixed in the right-side action column
- app-origin metadata sits with other secondary metadata
- IDE rows must not make cards taller by default unless the metadata is actively expanded

## Data Model Direction

The current target model should expand cleanly for IDEs.

Expected additions or clarified semantics:

- `sourceKind`
- optional IDE-specific session identity if an app exposes one
- optional workspace path or project path when available
- fallback-labeled rows when only window title is available

Existing fields like these still matter for IDEs:

- `bundleIdentifier`
- `appName`
- `windowTitle`
- `currentWorkingDirectory`
- `repositoryRoot`
- `repositoryName`
- `branch`
- `confidence`

The important change is semantic, not just additive:

- `currentWorkingDirectory` can no longer be treated as terminal-only truth
- IDE rows may be valid with `windowTitle` plus `bundleIdentifier` even when cwd is nil

## Implementation Guidance

The expansion should land in this order:

1. introduce `sourceKind`
2. preserve current terminal behavior without regressions
3. add IDE bundle-ID recognition and chooser grouping
4. add app-specific repo or workspace resolution where possible
5. add title-only fallback for unresolved IDE targets
6. validate visual parity in capture and stack

This keeps the system useful even before every IDE has repo-aware resolution.

## Verification Checklist

Minimum verification for the IDE expansion slice:

- terminal support still works for Terminal and iTerm2
- Tier 1 IDE bundle IDs are recognized
- chooser groups render as `Recent`, `Open Terminals`, and `Open IDEs`
- unresolved IDE targets still produce a stable row via window-title fallback
- capture and stack preserve their current shell, card, shadow, and accessory hierarchy
- rows with fallback labels do not overflow or dominate the main text

## Non-Goals

This plan does not commit to:

- direct-send into IDE prompts in the same slice
- app-specific deep integrations for every editor on day one
- replacing terminal-first resolution with IDE-first resolution
- redesigning capture or stack around a new source picker shell

The main bar is simple:

- support IDEs as first-class origins
- remain useful when repo resolution fails
- keep Prompt Cue visually quiet
