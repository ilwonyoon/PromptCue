# Working With Apps Chooser Stabilization Plan

## Goal

Stabilize the `working with apps` chooser so it behaves like a fixed, quiet accessory surface instead of a height-reactive content dump.

This plan applies to both:

- capture chooser panel
- stack chooser popover

The shared contract is:

- preserve the base `main` capture and stack shells
- keep the origin selector visually secondary
- keep chooser padding stable
- make longer app lists scroll instead of stretching or clipping
- keep mouse hover and keyboard selection in sync

## Current Problems

### 1. Panel height is content-estimated instead of viewport-based

The capture chooser panel currently derives its height from total row count in:

- [CapturePanelController.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/UI/WindowControllers/CapturePanelController.swift)

This causes:

- unstable top and bottom padding
- panel growth based on list size
- clipped shadows or clipped rows
- no clear "list viewport" concept

### 2. The chooser body is still carrying section chrome

The chooser view currently renders all content directly in a `VStack` in:

- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/UI/Views/CaptureCardView.swift)

This causes:

- no internal scrolling
- no stable visible row count
- section headers and labels competing with the actual app rows

### 3. Keyboard movement does not auto-scroll the list cleanly

The model tracks highlighted selection by index in:

- [AppModel.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/App/AppModel.swift)

But the UI does not scroll the highlighted row into view.

This causes:

- hidden selection when moving down by keyboard
- mismatch between logical selection and visible viewport
- current keyboard movement can feel like blinking because scrolling recenters too aggressively

### 4. Hover and keyboard selection are coupled

The chooser currently lets hover updates feed into the same highlight state that drives keyboard navigation.

This causes:

- moving the mouse across rows can trigger scroll movement
- hover and keyboard movement fight over one selection state
- the list feels reactive instead of stable

## Target Behavior

### Capture chooser

- opens above capture with fixed vertical spacing
- keeps visible top and bottom padding at all times
- uses a tiered viewport height
- shows `1 row` when only one choice exists
- shows exact height for `2-3 rows`
- shows roughly `4.x rows` when there are `4+` choices so the next row is hinted
- scrolls internally when there are more rows
- keeps capture panel stationary
- keeps hover highlight and keyboard highlight visually aligned

### Stack chooser

- uses the same row layout and ordering
- uses the same viewport rules where feasible
- does not visually dominate the card

## Information Architecture

Rules:

- automatic/recent row appears first when present
- remaining rows keep provider order
- automatic/recent target is shown as a row-level marker
- terminal-heavy lists should not consume the entire panel

## Viewport Rules

The chooser should stop sizing from total list count and start sizing from a fixed viewport model.

Suggested constants:

- `captureChooserPeekVisibleRows = 4.x`
- `captureChooserPeekFraction`
- `captureChooserRowHeight`

The panel should be sized from:

- outer panel padding
- surface padding
- scroll viewport height

It should **not** be sized from the full number of rows in the list.

## Rendering Contract

The chooser should render as:

1. a single sticky question header
2. flat scrollable list body

The list body contains:

- automatic/recent row first when present
- remaining rows in provider order

The outer surface keeps fixed top and bottom padding regardless of list length.
Use the same shell padding rhythm as capture mode, especially for vertical insets.

Capture and chooser rows must share one explicit control-width contract inside the capture shell:

- selector control width = `captureSurfaceWidth - (captureSurfaceInnerPadding * 2)`
- capture selector and chooser rows both center the same visible capsule width
- do not let capture and chooser derive their own horizontal insets independently

Chooser rows should reuse the same one-line identity language as the capture origin accessory:

- app icon
- primary workspace label
- optional inline secondary branch hint
- optional inline `Recent` marker
- optional trailing selected checkmark

Do not use a second subtitle line in chooser rows.
Do not use visible section titles.
Use one sticky question-style header: `For which AI workflow?`
Show the selectable target count inline in the header as a bare number, for example `5`.
Do not use a bottom dim or overflow scrim.

## Keyboard Contract

### Capture

- `Up` from the editor opens chooser
- `Up/Down` moves highlighted row
- `Tab` selects highlighted row and closes chooser
- `Enter` selects highlighted row if chooser is open; otherwise submits capture
- `Esc` closes chooser first, then capture

### Scrolling

When highlighted row changes:

- keyboard navigation may auto-scroll, but only enough to keep the highlighted row visible
- do not recenter the list on every move
- hover should never trigger scrolling
- hover highlight should be visual-only and separate from keyboard selection state

## Implementation Checklist

### Phase 1: Stabilize panel sizing

- [ ] Add chooser viewport sizing constants in [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/App/AppUIConstants.swift)
- [ ] Replace row-count-driven `desiredSuggestedTargetPanelHeight()` in [CapturePanelController.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/UI/WindowControllers/CapturePanelController.swift) with viewport-based sizing
- [ ] Preserve fixed top and bottom padding even with many rows
- [ ] Keep capture panel stationary while chooser opens/closes

### Phase 2: Make the list scroll

- [ ] Convert chooser body from raw `VStack` to a flat `ScrollView`
- [ ] Keep terminal-first ordering without visible section titles
- [ ] Render automatic target as a row-level `Recent` marker
- [ ] Ensure terminal-heavy lists show a stable viewport instead of stretching the panel
- [ ] Reuse the capture origin identity styling for chooser rows
- [ ] Apply `1 / 2-3 / 4.x+` viewport sizing rules

### Phase 3: Sync keyboard movement with viewport

- [ ] Introduce stable row ids for automatic and explicit choices
- [ ] Wrap the chooser body in `ScrollViewReader`
- [ ] Auto-scroll highlighted row into view only when keyboard selection changes
- [ ] Stop hover from mutating keyboard selection state
- [ ] Replace center-anchored scroll behavior with minimal visibility-preserving scroll

### Phase 4: Trim visual weight

- [ ] Keep the origin accessory capsule visually quiet in capture
- [ ] Keep only a single sticky question header and remove other chooser titles
- [ ] Confirm stack popover uses the same row language as capture
- [ ] Re-check panel shadow clipping after fixed-height conversion
- [ ] Keep capture selector and chooser row capsules on the same explicit width contract

## Verification Checklist

- [ ] Open chooser with `0`, `1`, `3`, and `6+` available targets
- [ ] Confirm `4+` choices show a partial next row hint instead of a hard cutoff
- [ ] Confirm top and bottom padding remain visible in all cases
- [ ] Confirm capture panel frame does not move when chooser opens
- [ ] Confirm `Up/Down` can reach hidden rows via auto-scroll
- [ ] Confirm `Up/Down` no longer feels like recentering or blinking
- [ ] Confirm mouse hover does not trigger scroll movement
- [ ] Confirm `Tab` selects and closes chooser
- [ ] Confirm `Esc` closes chooser without closing capture prematurely
- [ ] Confirm stack chooser preserves the same row language and ordering
- [ ] Confirm `Terminal`, `Antigravity`, `Cursor`, and `Xcode` rows all render with sane fallback labels
- [ ] Render a deterministic PNG fixture and confirm chooser row capsule edges match the capture selector capsule edges

## File Ownership

Primary files for this stabilization slice:

- [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/App/AppUIConstants.swift)
- [CapturePanelController.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/UI/WindowControllers/CapturePanelController.swift)
- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/UI/Views/CaptureCardView.swift)
- [CaptureComposerView.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/UI/Views/CaptureComposerView.swift)
- [AppModel.swift](/Users/ilwonyoon/Documents/PromptCue-tag-priority-direct-send-to-apps/PromptCue/App/AppModel.swift)

## Order Of Execution

Do the work in this order:

1. panel sizing
2. scrollable chooser body
3. keyboard auto-scroll
4. visual density polish

Do not start density polish before viewport and scrolling are stable.
