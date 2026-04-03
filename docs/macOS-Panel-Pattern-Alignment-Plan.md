# macOS Panel Pattern Alignment Plan

## Purpose

This plan defines how Backtick should align its `Settings` and `Memory` windows with the current macOS panel language visible in the provided `Notes` and `System Settings` screenshots.

The intent is not pixel-matching. The intent is to extract:

- the shell and column hierarchy macOS currently emphasizes
- the background and divider relationships that make the panels feel native
- the icon placement rules used by titlebars, sidebars, and per-column controls
- the exact places where Backtick's current `Settings` and `Memory` windows drift away from that pattern
- a phased implementation order that can land safely without destabilizing the app

This document is the planning baseline for branch:

- `design/macos-panel-pattern-plan`

## Scope

In scope:

- `Settings` window shell and visual grammar
- `Memory` window shell and visual grammar
- shared panel tokens that affect these surfaces
- toolbar and icon placement strategy
- color, separator, and grouping rules
- preview and verification strategy for phased rollout

Out of scope for the first pass:

- redesigning Capture or Stack to match this window language
- changing product IA or tab definitions
- adding brand-new flows unrelated to panel chrome
- adopting OS-version-specific APIs that would raise the deployment target above the current baseline

## Constraints

### Platform Baseline

Backtick currently targets macOS `14.0` in [project.yml](/Users/ilwonyoon/Documents/PromptCue/project.yml).

This matters because some newer Apple design guidance now talks about `Liquid Glass` for sidebars and navigation. That guidance is still useful as a hierarchy reference, but Backtick cannot assume the latest visual APIs are available at runtime.

Implementation rule:

- copy the hierarchy and composition pattern first
- use AppKit and SwiftUI materials that exist on the shipping deployment target
- do not create a fake futuristic glass layer that fights the rest of the system

## Source Inputs

### Official Apple Guidance

These sources are useful for structural rules, but they do not provide production-ready color tokens or exact Notes/Settings measurements:

- Apple HIG: `Toolbars`
  - toolbar items should be grouped by role
  - leading edge hosts navigation and sidebar-affecting controls
  - trailing edge hosts actions and overflow
  - Notes is explicitly used as an example of a standard macOS toolbar
  - source: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Apple HIG: `Sidebars`
  - sidebars belong to the navigation layer
  - if hierarchy is deeper than two levels, a split view with a content list between sidebar and detail is appropriate
  - source: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Apple HIG: `Materials`
  - navigation and controls are treated as a distinct layer
  - content should not use the same elevated treatment as navigation chrome
  - source: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG: `Layout`
  - when content doesn't span the whole window, a background extension should maintain a coherent surface behind sidebars and edge areas
  - source: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple HIG: `Buttons`
  - familiar actions should use familiar symbols
  - symbol-only controls belong in the appropriate toolbar or view context
  - source: https://developer.apple.com/design/human-interface-guidelines/buttons

### Screenshot Diagnosis

The provided screenshots are the stronger source for:

- current color relationships
- titlebar icon grouping
- per-column ownership of controls
- divider weight
- sidebar icon treatment
- relative contrast between navigation, list, and detail columns

Where this document cites a rule as `inferred`, it means the rule is derived from the screenshots rather than explicitly stated in Apple's docs.

## Reference Diagnosis

### A. Notes Window Pattern

From the screenshot, modern Notes uses a `3-column shell`:

1. source/sidebar column
2. content list column
3. detail/editor column

Observed pattern:

- each column reads as its own surface with slightly different luminance
- the leftmost source list is the darkest and most recessed
- the middle list is still dark, but lighter than the source list
- the detail/editor column is the brightest working surface
- vertical dividers are visible but soft; they separate surfaces rather than acting like hard borders

Toolbar/icon pattern, inferred from the screenshot and consistent with Apple's toolbar guidance:

- leading titlebar controls belong to navigation and shell state
- title and note context stay near the leading/center region
- trailing controls are action-oriented
- controls are not randomly centered over the whole window; they appear anchored to column ownership or toolbar role

Important pattern:

- Notes does not decorate the content area with card-heavy grouping
- the shell itself does most of the visual work
- the detail column feels flatter and calmer than Backtick's current Settings cards

### B. System Settings Pattern

From the screenshot, modern System Settings uses a `2-column shell`:

1. sidebar with icon-and-label navigation rows
2. content pane with grouped settings cards

Observed pattern:

- selected sidebar rows use a strong blue selection pill
- unselected rows sit directly on the sidebar background
- sidebar icons are small colored rounded tiles, but not glossy in a game-like way
- the content background is a separate flat system surface from the sidebar
- group cards are subtle inset surfaces, not dramatic glass plates
- section headings are compact and secondary
- group rows rely on alignment and spacing more than ornamental framing

Important pattern:

- the window already feels native before any single card is inspected
- the shell contrast is doing most of the hierarchy work
- the cards are quiet containers inside a coherent window, not standalone objects

### C. Shared Cross-App Rules

Across both screenshots, the shared macOS pattern appears to be:

- shell first, cards second
- navigation layer darker or more recessed than working content
- dividers soft and continuous
- icon placement follows ownership of a pane or toolbar role
- controls cluster at the top edge; content below should not duplicate the same hierarchy unnecessarily
- color hierarchy is low-saturation and system-led, with accent color used primarily for selection and action emphasis

## Backtick Current-State Diagnosis

### Settings

Backtick Settings already matches part of the System Settings composition:

- 2-column shell
- sidebar + detail
- grouped settings sections
- colored sidebar icons

But it still drifts in several ways:

1. Sidebar icon tiles are too glossy and too dimensional.
- [SettingsSidebarIconTile.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSidebarIconTile.swift) uses stacked gradients, white highlight overlays, extra stroke layers, and shadow.
- The result reads more custom and decorative than the flatter system tiles in System Settings.

2. Settings owns a private visual token lane that doesn't yet generalize to Memory.
- [SettingsSemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/SettingsSemanticTokens.swift)
- [SettingsTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/SettingsTokens.swift)
- The shapes are useful, but the color system is still page-family specific instead of panel-family based.

3. The content header is still page-owned instead of clearly participating in a broader window chrome strategy.
- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/PromptCueSettingsView.swift)
- The title is inside the scroll content. This is acceptable, but it means the visual contract with toolbar/titlebar controls is weaker than in Apple's current apps.

4. The content cards are close to the target pattern, but their surface math needs recalibration.
- current fills and borders are slightly too custom relative to the quieter System Settings groups
- the content background to group contrast can be tuned closer to the native pattern

### Memory

Memory is structurally closer to Notes than Settings, but the visual system is not yet aligned.

Current strengths:

- true multi-column split view
- project/list/detail hierarchy already exists
- columns already use different backgrounds

Current drift:

1. The window toolbar is effectively empty.
- [MemoryWindowController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers/MemoryWindowController.swift)
- It creates a toolbar, but only returns `.flexibleSpace`.
- This misses the Notes pattern where top-edge controls help express column ownership and high-frequency actions.

2. Memory uses its own hardcoded color lane instead of shared panel semantics.
- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift)
- `MemoryPaneColors` and `MemoryPaneMetrics` are private and local.
- This makes Settings and Memory feel like two different products even when the layout skeleton is similar.

3. The column backgrounds are directionally correct, but not yet tuned to Notes.
- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift)
- left sidebar is close
- middle and right panes are too dependent on raw system backgrounds and local separators instead of a deliberately harmonized three-surface recipe

4. Memory still uses bottom/footer action grammar where Notes emphasizes top-toolbar action grammar.
- `New Document` currently lives in the footer of the middle column
- that isn't automatically wrong, but it does diverge from the reference pattern the user wants to move toward

5. Typography, badges, and inline metadata are internally coherent but not yet calibrated against the Settings window.
- Memory reads like a bespoke product surface, not a sibling of Settings

## Token Strategy

### Decision

Before visual redesign work starts in earnest, Backtick should first align `Settings` and `Memory` on a shared panel-token contract.

This means the project should not begin by independently polishing the two windows. It should begin by extracting and freezing the shared shell semantics both windows should obey.

### What Must Match First

These token categories should be shared before panel-specific redesign begins:

- window shell background
- navigation/sidebar surface level
- list/content-list surface level
- working/detail surface level
- pane divider color and weight
- accent and selection usage rules
- toolbar/icon emphasis rules
- active vs inactive window contrast behavior

Reason:

- these are the parts that define whether the two windows feel like they belong to the same app family
- if Settings and Memory are tuned independently first, the project will likely pay a second convergence pass later

### What Must Not Be Forced Into Early Unification

These areas should remain panel-specific until after the shared shell contract is stable:

- Settings group/card fill strategy
- Settings sidebar icon tile styling details
- Memory 3-column spacing and list density
- Memory detail typography and markdown rendering
- footer action vs toolbar action decisions in Memory

Reason:

- `Settings` and `Memory` should share a parent language, not identical component grammar
- forcing full token unification too early would flatten the meaningful difference between a `2-column settings form` and a `3-column notes-style workspace`

### Execution Rule

Use this order:

1. extract shared `panel shell semantics`
2. map existing Settings and Memory values onto that shared token layer
3. explicitly document which tokens remain panel-specific
4. only then start panel-by-panel visual redesign work

This rule should override the tempting but riskier approach of redesigning `Settings` first and fixing `Memory` later.

### Phase 1 Token Inventory

The first extraction pass should lift the following roles into a shared panel token lane:

| Shared role | Current Settings owner | Current Memory owner | Keep shared? |
| --- | --- | --- | --- |
| navigation sidebar background | `SettingsSemanticTokens.Surface.sidebarBackground` | `MemoryPaneColors.notesSidebarBackground` | Yes |
| navigation sidebar top tint | `SettingsSemanticTokens.Surface.sidebarBackgroundTopTint` | none | Yes |
| navigation sidebar bottom shade | `SettingsSemanticTokens.Surface.sidebarBackgroundBottomShade` | none | Yes |
| main content canvas background | `SettingsSemanticTokens.Surface.contentBackground` | window/content shell equivalents | Yes |
| reading/detail background | inline settings/editor surfaces | `MemoryPaneColors.textBackground` | Yes |
| window background | implicit AppKit/system background usage | `MemoryPaneColors.windowBackground` | Yes |
| pane divider base color | `SettingsSemanticTokens.Border.paneDivider` | `MemoryPaneColors.separator` | Yes |
| quiet group fill | `SettingsSemanticTokens.Surface.formGroupFill` | none | Yes |
| quiet inset fill | `SettingsSemanticTokens.Surface.inlinePanelFill` | none | Yes |
| selection accent | `SettingsSemanticTokens.Accent.selection` | implicit system selection | Yes |

The following should stay panel-specific after the shared extraction:

- Settings sidebar icon tile rendering recipe
- Settings grouped form geometry and row layout
- Memory list density, detail typography, and markdown rendering
- Memory footer action and future toolbar migration decisions

## Alignment Rules To Freeze Before Implementation

### Rule 1: Shared Panel Family

Create one shared visual family for resizable app windows:

- sidebar/navigation surfaces
- list/content-list surfaces
- working/detail surfaces
- pane dividers
- grouped inset surfaces
- toolbar/icon emphasis

This should not force Settings and Memory to become identical. It should give them a common parent language.

### Rule 2: Navigation Surfaces Stay More Recessed Than Working Surfaces

For both Settings and Memory:

- navigation sidebars should be darker or more recessed
- editable or primary reading areas should be calmer and slightly brighter
- separators should describe plane changes, not draw attention to themselves

### Rule 3: Toolbar Icons Must Follow Pane Ownership

Adopt this mental model:

- whole-window navigation controls: leading toolbar cluster
- pane-specific global actions: top edge, near the pane they affect
- row-specific actions: stay inside rows
- do not place icons in the titlebar unless they act on a window area or current selection context

### Rule 4: Sidebar Icons Need a Flatter System Tone

Settings sidebar icons should keep the colored-tile concept, but:

- reduce gloss
- reduce shadow
- reduce highlight complexity
- preserve recognition at a glance
- use accent only for the selected row background, not for every ornamental edge

### Rule 5: Cards Should Be Quiet

For Settings:

- keep grouped containers
- lower ornamentation
- let spacing and alignment do more work than fills and strokes

For Memory:

- avoid importing Settings-style cards into the list and detail columns
- keep Notes-like flatter content treatment where the shell does most of the hierarchy work

## Phased Execution Plan

### Phase 0: Freeze References and Review Harness

Deliverables:

- this planning document
- one compact visual checklist for Settings and Memory
- preview or screenshot fixtures for both windows in light and dark appearance

Tasks:

- lock down the target behaviors before token edits begin
- capture current screenshots so visual regressions are measurable
- define the success bar for sidebar contrast, divider contrast, and icon treatment

### Phase 1: Extract Shared Panel Semantic Tokens

Goal:

- create a shared token layer for `window shell`, `navigation surface`, `list surface`, `detail surface`, `divider`, and `quiet inset group`
- make `Settings` and `Memory` converge on the same shell contract before either receives deeper visual polish

Likely landing zone:

- new shared tokens near [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/SemanticTokens.swift)

Tasks:

- separate app-wide panel semantics from Settings-only semantics
- keep `SettingsTokens` for geometry, but move reusable color relationships into a shared panel family
- migrate Memory off private `MemoryPaneColors` where the values represent reusable shell semantics
- produce an explicit table of `shared tokens` vs `panel-specific tokens`
- do not start card-level or toolbar-level redesign until this split is reviewed

### Phase 2: Define Toolbar and Header Ownership

Goal:

- stop treating Settings and Memory headers as unrelated

Tasks:

- decide whether Settings keeps the page title in content or partially promotes header ownership into window chrome
- design a Notes-like toolbar strategy for Memory
- identify which top-edge icons belong to window navigation versus document actions
- avoid decorative toolbar buttons that don't map to a clear ownership rule

### Phase 3: Rebuild Settings Sidebar and Surface Tone

Targets:

- [SettingsSidebarItem.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSidebarItem.swift)
- [SettingsSidebarIconTile.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/Components/SettingsSidebarIconTile.swift)
- [SettingsSemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/SettingsSemanticTokens.swift)

Tasks:

- flatten icon tile rendering
- retune sidebar background against content background
- verify selection pill contrast in light and dark appearance
- reduce the sense that the sidebar row is a standalone custom component

### Phase 4: Rebalance Settings Content Groups

Targets:

- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/PromptCueSettingsView.swift)
- Settings component set under `PromptCue/UI/Settings/Components`

Tasks:

- retune content background and group fill contrast
- preserve existing row grammar and alignment contract
- reduce surface noise while keeping clear grouping
- make section-to-group rhythm closer to System Settings

### Phase 5: Rebuild Memory Shell Around Notes-Like Hierarchy

Targets:

- [MemoryWindowController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers/MemoryWindowController.swift)
- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift)

Tasks:

- define explicit three-surface hierarchy for project, document, and detail columns
- retune dividers to read like Notes rather than generic split view lines
- move or supplement high-frequency actions into toolbar positions that match pane ownership
- keep the middle column action story coherent if the footer CTA remains temporarily during migration

### Phase 6: Unify Icon and Control Language Across Both Windows

Goal:

- make Settings and Memory feel like siblings

Tasks:

- align titlebar symbol weight, hover feel, and placement density
- align sidebar row density where the platform pattern overlaps
- confirm that SF Symbol usage maps to familiar system actions

### Phase 7: Final Polish and Regression Pass

Verification:

- compare against the supplied Notes and System Settings screenshots
- verify light and dark mode
- verify inactive-window appearance
- verify reduced transparency and increased contrast if feasible
- verify minimum window sizes still preserve toolbar and split-view clarity

## Implementation Order Recommendation

Recommended landing sequence:

1. shared panel semantic tokens and ownership split
2. Settings sidebar/icon flattening
3. Settings surface rebalance
4. Memory shell color/divider rebalance
5. Memory toolbar/action placement
6. cross-window polish pass

Reason:

- shared shell tokens reduce rework before either panel gets visual polish
- Settings is still the lower-risk proving ground once the shared token contract exists
- Memory still has bigger structural changes because toolbar ownership is currently underdeveloped

## Key Risks

1. Overfitting to screenshots.
- risk: copying one screenshot state too literally instead of following Apple's broader hierarchy rules
- mitigation: treat screenshots as tone reference, not pixel spec

2. Mixing incompatible patterns.
- risk: importing Settings cards into Memory and losing the Notes-like flat reading surface
- mitigation: share shell semantics, not identical component grammar

3. Overusing decorative icon treatments.
- risk: keeping glossy colored tiles and adding Notes-like toolbar icons on top
- mitigation: flatten sidebar icon rendering before adding more icon emphasis elsewhere

4. Deployment-target mismatch.
- risk: designing around effects only available on newer macOS releases
- mitigation: implement with APIs available on the current target and treat newer HIG language as structural guidance

## Open Questions

1. Should Memory keep the footer `New Document` action after a toolbar action is introduced, or should it migrate fully to the titlebar?
2. Should Settings keep its page title inside the content column, or should the window chrome assume more of the header role?
3. Should the shared panel token layer cover `Stack` later, or stay limited to `Settings` and `Memory` until the pattern stabilizes?

## Minimum Success Criteria

The first implementation pass is successful if:

- Settings and Memory clearly belong to the same app family
- Settings reads closer to System Settings without becoming a screenshot clone
- Memory reads closer to Notes without losing Backtick's information density
- icon placement feels intentional and pane-owned instead of decorative
- the color hierarchy is clearer than the current implementation in both light and dark appearance
