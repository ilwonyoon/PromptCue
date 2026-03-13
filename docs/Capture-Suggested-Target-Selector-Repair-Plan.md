# Capture Suggested-Target Selector Repair Plan

## Purpose

Repair the capture suggested-target selector at the state-contract level so that it stops regressing when visual polish changes are made.

This plan is intentionally narrower than capture-panel hardening. It covers only the suggested-target selector contract in capture:

- inline selector accessory
- detached chooser panel
- selection, hover, and keyboard focus behavior
- row chrome and fill ownership

The current restoration checkpoint for target resolution and warm start is commit `25cc8a6`.

## Problem Summary

The selector has shown repeated regressions:

- more than one row can look active at the same time
- hover can make a second row look selected
- outline or stroke changes in the chooser also affect the inline selector
- visual tweaks can cascade into keyboard and focus breakage because the repair boundary is unclear

Two adjacent regressions were data-path issues and are already restored in `25cc8a6`:

- `55917f7` removed rich terminal and IDE enrichment
- `5af995d` deferred the suggested-target provider and made chooser readiness feel cold

Those two commits explain missing repo and branch labels and slow initial loading, but they do not explain the selector state regressions by themselves.

## Last Known-Good Reference

Use commit `d4b966c` as the behavioral reference for:

- detached chooser panel placement
- capture-panel keyboard ownership
- immediate chooser readiness feel

Important nuance:

- `d4b966c` is not a clean architecture for selector state
- it is only the last known-good product behavior reference

## Root Causes

### 1. State Contract Is Ambiguous

The selector currently models both committed selection and highlighted choice, but both are rendered as active-looking states.

Current surfaces:

- [AppModel+SuggestedTarget.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+SuggestedTarget.swift)
- [CaptureSuggestedTargetViews.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift)

Current problems:

- `captureChooserTarget` represents the committed value
- `highlightedCaptureSuggestedTarget` represents the keyboard or hover focus target
- `selectedCaptureSuggestedTargetIndex` is reused as the source for highlight
- the view treats `isSelected`, `isHighlighted`, and `isHovered` as parallel rendering inputs

Result:

- one row can be committed
- another row can still look active because it is highlighted or hovered

### 2. Hover Mutates Model-Level Focus

Chooser row hover currently flows into model highlight behavior instead of remaining local view state.

Result:

- moving the mouse can shift model focus
- keyboard focus and mouse hover compete
- the UI can show a faint second selector while the committed row remains selected

### 3. Accessory Chrome And Chooser Chrome Share One Primitive

The inline accessory selector and chooser rows both use `SuggestedTargetControlChrome`.

Result:

- changing stroke or fill to fix chooser visuals also changes the inline selector
- outline regressions recur because there is no ownership boundary between the two surfaces

### 4. Verification Is Too Coarse

Current verification catches build and logic failures but not selector rendering contracts.

Missing checks:

- exactly one row is selected-looking
- hover never mutates committed selection
- hover never leaves a persistent second active background
- chooser row chrome changes do not affect inline selector chrome

## Repair Goals

The repaired selector must satisfy all of these contracts.

### UX Contract

- exactly one row may look selected at a time
- hover may provide a subtle local affordance, but must not look selected
- keyboard focus may move independently from committed selection, but must not look equal to selected
- the selected row should use the strongest fill in light mode
- inline accessory chrome and chooser row chrome must be independently stylable

### State Contract

- committed selection is a stable identity
- focused choice is a separate stable identity
- hover is local view state only
- committed selection changes only on explicit selection completion
- keyboard navigation changes focused choice, not committed selection

### Ownership Contract

- AppModel owns committed and focused choice identity
- chooser row owns hover only
- chooser row chrome owns chooser visuals only
- inline selector chrome owns inline visuals only
- panel and keyboard ownership must not change as part of this repair

## Proposed Design

### 1. Introduce Explicit Choice Identity

Replace the implicit index-driven state with explicit choice IDs.

Add:

- `committedCaptureSuggestedTargetChoiceID`
- `focusedCaptureSuggestedTargetChoiceID`

Choice identity rules:

- automatic target uses a reserved automatic ID
- explicit targets use `canonicalIdentityKey`

### 2. Replace Parallel Booleans With A Single Row State

Introduce a single derived row-state model for rendering, for example:

- `selected`
- `focused`
- `hovered`
- `idle`

Rendering rule:

- only `selected` may use the strong white selected fill
- `focused` gets a weaker affordance than `selected`
- `hovered` gets a weaker affordance than `focused`
- `idle` gets base fill

### 3. Keep Hover Local

Hover must never call back into AppModel.

Allowed:

- local `@State isHovered`

Forbidden:

- changing focused choice on mouse hover
- changing committed choice on mouse hover

### 4. Split Chrome Primitives

Replace the shared primitive with two surfaces:

- `SuggestedTargetAccessoryChrome`
- `SuggestedTargetChooserRowChrome`

This prevents:

- chooser stroke changes from affecting inline selector chrome
- inline selector fill decisions from leaking into chooser rows

### 5. Preserve Existing Keyboard Ownership

Keyboard ownership must remain on the main capture panel.

This repair should not:

- change panel style masks
- change chooser panel key behavior
- change editor first-responder policy

If keyboard issues appear while doing this work, stop and treat them as a separate regression.

## Implementation Plan

### Phase 1. Freeze State Contract

Files:

- [AppModel+SuggestedTarget.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+SuggestedTarget.swift)
- [AppModel.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel.swift)

Work:

- replace index-only highlight reasoning with explicit committed and focused IDs
- keep current public behavior for selection completion and cancellation
- remove hover-driven model mutation

Exit criteria:

- model can express committed and focused choice independently
- no API requires hover to mutate model state

### Phase 2. Split Rendering Contract

Files:

- [CaptureSuggestedTargetViews.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift)

Work:

- derive a single row render state from committed and focused IDs plus local hover
- split chooser row chrome from accessory chrome
- make selected fill stronger than focused and hover

Exit criteria:

- exactly one row can render as selected
- focused and hover are visually weaker than selected
- inline selector outline rules are independent from chooser row outline rules

### Phase 3. Guard Against Regression

Files:

- selector tests in `PromptCueTests`

Required tests:

- committed selection remains stable while hovering a different row
- focused choice changes with keyboard navigation without changing committed selection
- selected-looking row count is exactly one
- automatic target and explicit target identity logic stay stable

## Verification

Minimum required verification:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Required manual QA:

1. Open capture with one automatic target and at least two explicit targets.
2. Confirm exactly one row looks selected.
3. Hover a different row.
4. Confirm the hovered row does not look equal to the selected row.
5. Use arrow keys to move focus.
6. Confirm focus moves without changing committed selection until explicit choose.
7. Confirm the inline selector does not gain chooser stroke regressions.
8. Confirm keyboard input still works in the editor before and after opening the chooser.

## Non-Goals

This plan does not include:

- new target-detection heuristics
- new chooser layouts
- cloud sync or screenshot changes
- capture panel keyboard ownership redesign
- visual redesign outside the selector contract

## Rollback Boundary

If Phase 1 causes keyboard or panel regressions, revert only the selector-repair slice and keep `25cc8a6` as the stable restoration checkpoint.
