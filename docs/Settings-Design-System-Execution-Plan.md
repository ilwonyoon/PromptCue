# Settings Design System Execution Plan

## Purpose

This plan turns the Settings standardization research into an implementation sequence that can land safely on `main`.

Reference:

- [Settings-Design-System-Standardization.md](/Users/ilwonyoon/Documents/PromptCue/docs/Settings-Design-System-Standardization.md)
- [macOS-Settings-Reference-Analysis.md](/Users/ilwonyoon/Documents/PromptCue/docs/macOS-Settings-Reference-Analysis.md)

## Goal

Create a dedicated Settings design-system lane so `General`, `Capture`, `Stack`, and `Connectors` all share:

- one token set
- one semantic color system
- one sidebar grammar
- one section/group grammar
- one row grammar
- one inline-panel grammar

The point is to stop page-local styling churn, not to redesign every Settings page from scratch.

## Current Root Problem

Today Settings is split across:

- [PanelMetrics.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/PanelMetrics.swift)
- [SettingsWindowController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers/SettingsWindowController.swift)
- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/PromptCueSettingsView.swift)

And before this pass, Settings-specific fonts, colors, spacing, and row grammar lived privately inside the page file.

That made every Settings iteration vulnerable to:

- inconsistent dividers
- drifting sidebar density
- page-specific spacing changes
- Connectors-specific layout branches
- repeated screenshot matching

## Box Archetypes

This refactor should stop treating each page as a bespoke layout.

Backtick should classify each Settings surface into one of four box archetypes and only compose from those.

### A. Simple Trailing-Control Group

Use when the row is:

- label on the left
- value or control on the right
- no long-form content inside the row

Backtick pages:

- `General > Appearance`
- `General > Shortcuts`

### B. Detail Group

Use when the row keeps a left label rail, but the right side contains:

- short explanatory copy
- a leading-aligned detail value
- a compact action cluster or status treatment

Backtick pages:

- `General > iCloud Sync`
- `Capture > Screenshots`

### C. Long-Form Exception Group

Use when the group shares one label/content rail, but contains:

- one or more ordinary rows
- plus an editor, preview, or larger inset block

Backtick pages:

- `Stack > Retention`
- `Stack > AI Export Tail`

### D. Workflow / Status Group

Use when the surface is action-first and may contain:

- state summary
- CTA
- inline repair/setup details
- richer status messaging than ordinary preferences

Backtick pages:

- `Connectors`

## Alignment Contract

These rules are now required for every Settings group:

1. One group = one left rail.
- Labels inside the same group align to the same starting x-position.

2. One group = one right rail.
- Controls, badges, toggles, status accessories, and trailing actions align to the same ending x-position.

3. One group = one row grammar.
- Do not mix `SettingsFormRow`, ad hoc `HStack`, and custom inset math inside one group unless the group declares a long-form exception.

4. Long-form blocks still inherit the same rails.
- If a group contains `Tail Text`, `Preview`, or action rows, those blocks start on the same content rail used by the short rows above them.

5. Dividers are parent-managed.
- A group owns separator placement.
- Rows inside that group must not stack their own extra dividers on top of group dividers.

6. Status language is visual first.
- Repeated states such as `Connected`, `Failed`, `Needs Repair`, or `Unavailable` should use a shared status primitive instead of plain text-only repetition.

## Implementation Scope

### Phase S1: Freeze Settings tokens

Deliverables:

- [SettingsTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/SettingsTokens.swift)
- [SettingsSemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/SettingsSemanticTokens.swift)

Rules:

- `SettingsTokens` owns stable Settings geometry and typography roles
- `SettingsSemanticTokens` owns Settings semantic colors and fills
- page-local Settings color constants are no longer allowed

### Phase S2: Extract shared Settings components

Deliverables:

- [SettingsSidebarItem.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSidebarItem.swift)
- [SettingsSection.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSection.swift)
- [SettingsFormRow.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsFormRow.swift)
- [SettingsTwoColumnGroupRow.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsTwoColumnGroupRow.swift)
- [SettingsStatusBadge.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsStatusBadge.swift)
- [SettingsSidebarIconTile.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSidebarIconTile.swift)
- [SettingsInlinePanel.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsInlinePanel.swift)

Rules:

- parent containers own dividers
- rows own label/control alignment
- grouped hybrid sections own one shared label rail
- grouped hybrid sections also own one shared trailing rail
- sidebar items own selection and icon slot treatment
- inline panels replace repeated inset box recipes

### Phase S3: Migrate all Settings pages onto the shared grammar

Targets:

- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/PromptCueSettingsView.swift)

Tasks:

1. General uses `SettingsSection`, `SettingsRows`, and `SettingsFormRow`
2. Capture uses `Detail Group` grammar, not a one-off row that mixes path and action content ad hoc
3. Stack uses `Long-Form Exception Group` grammar, not product-style surfaces
4. Hybrid groups such as `Retention` and `AI Export Tail` share one 2-column label/content rail inside each group
5. Connectors uses `Workflow / Status Group` primitives even when its state model is richer

### Phase S4: Remove dead Settings styling branches

Cleanup targets:

- old private settings constants
- dead sidebar plate colors
- duplicate inset surface helpers
- unused connector-only presentation helpers

### Phase S5: Add review tooling

Add a stable review path for:

- light mode
- dark mode
- empty/error/connected connector states
- long helper text
- screenshot reconnect state

This can be done with previews or a small internal preview host.

## Parallel Ownership Map

Master-owned:

- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/PromptCueSettingsView.swift)
- [PanelMetrics.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/PanelMetrics.swift)
- [SettingsWindowController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers/SettingsWindowController.swift)
- integration docs and merge sequencing

Track A: docs / contracts

- [Settings-Design-System-Execution-Plan.md](/Users/ilwonyoon/Documents/PromptCue/docs/Settings-Design-System-Execution-Plan.md)
- [Settings-Design-System-Standardization.md](/Users/ilwonyoon/Documents/PromptCue/docs/Settings-Design-System-Standardization.md)
- optional reference updates in [macOS-Settings-Reference-Analysis.md](/Users/ilwonyoon/Documents/PromptCue/docs/macOS-Settings-Reference-Analysis.md)

Track B: new shared primitives

- [SettingsTwoColumnGroupRow.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsTwoColumnGroupRow.swift)
- [SettingsStatusBadge.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsStatusBadge.swift)
- [SettingsSidebarIconTile.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSidebarIconTile.swift)

Track C: preview/simulation only

- [SettingsSimulationView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Preview/SettingsSimulationView.swift)
- [DesignSystemPreviewView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Preview/DesignSystemPreviewView.swift)
- [DesignSystemPreviewTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/DesignSystemPreviewTokens.swift)

Rule:

- no track edits `PromptCueSettingsView.swift` except master
- no track edits release-sensitive window or app entry files except master
- if a shared token signature changes, master merges that first before UI migration continues

## Phased Landing Order

### Phase P0: Freeze contracts

- archetypes
- alignment contract
- ownership map
- verification gates

### Phase P1: Shared foundation

- freeze `SettingsTokens` and `SettingsSemanticTokens`
- land new shared primitives without page migration
- keep previews compiling

### Phase P2: Preview validation

- update simulation/preview surfaces to exercise:
  - simple trailing-control group
  - detail group
  - long-form exception group
  - workflow/status group
- require `General`, `Capture`, and `Stack` preview groups to prove that each box uses one shared left rail and one shared right rail before live migration starts

### Phase P3: Live page migration

Order:

1. `General`
2. `Capture`
3. `Stack`
4. `Connectors`

Merge lowest-risk layout first, then migrate richer pages after the primitives prove out.

### Phase P4: Sidebar polish

- sidebar icon tile depth / gradient / highlight
- hover and selection tuning
- icon size and spacing audit against references

### Phase P5: Cleanup

- remove dead layout helpers
- remove duplicate divider math
- remove one-off page-local inset and spacing hacks

## Current Pass

This pass should land:

- Settings token extraction
- Settings semantic token extraction
- shared Settings component extraction
- first migration of `PromptCueSettingsView` onto those shared pieces
- compactness token pass for shell, sections, rows, and inline panels
- smaller default settings window geometry and narrower content measure

This pass does not need to fully redesign Connectors again.

## Compactness Rules

Compactness is now an explicit Settings requirement, not a page-by-page polish preference.

Rules:

- prefer one short section description above a group, never a floating footer below it
- keep content on a narrower readable measure instead of stretching groups to the full panel width
- keep short controls in compact rows; reserve full-width blocks for editors, previews, or setup flows
- reduce row height, inset, and section spacing only through `SettingsTokens`
- when a page needs an exception, add a shared Settings primitive first instead of inventing page-local spacing

## Definition of Done

This plan is complete when:

1. Settings-specific constants are no longer privately owned inside `PromptCueSettingsView.swift`
2. the sidebar uses one shared component
3. grouped sections use one shared component
4. form rows use one shared component
5. inline inset panels use one shared component
6. no Settings page uses stack/capture chrome by accident

## Verification

Required:

- `xcodegen generate`
- `swift test`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Track-specific expectations:

- docs-only tracks do not require build/test reruns if they do not touch code
- shared primitive tracks must run `swift test` and `xcodebuild ... build`
- master integration must run the full verification set after merge

## Risks and Rollback

Primary risks:

- shared primitive drift if page migration starts before contracts are frozen
- `PromptCueSettingsView.swift` conflict churn if multiple tracks touch it
- visual regression if dividers and rail ownership are not unified
- Connectors losing action clarity if forced into ordinary preference rows too early

Rollback strategy:

1. revert the latest migration layer, not the whole Settings pass
2. keep shared primitives if they compile and are not behaviorally harmful
3. preserve simulation-only files even if live migration is rolled back
4. if a group archetype proves wrong, roll back that group to the previous page-local layout and revise the contract before retrying

## Follow-Up

After this plan is landed and stable:

1. tighten Connectors onto the same row grammar more aggressively
2. add a small Settings preview matrix
3. revisit newer Apple glass APIs only after the repo upgrades toolchains
