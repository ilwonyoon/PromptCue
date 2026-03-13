# Stack Header Rail, Filter, and TTL Plan

## Purpose

Replace the current transient staged-copy header with a persistent stack header rail so Stack stops shifting vertically when cards are clicked, while adding:

- a quiet queue summary
- strong staged-copy feedback
- a launch-facing filter menu for queue state
- a per-card TTL ring for active cards
- theme-adaptive Backtick logo behavior for stack chrome and status-item chrome

This plan is intentionally limited to Stack header and card-surface presentation. AI grouping is out of scope for this slice.

Umbrella note:

- this document is the UI child plan for the broader stack refactor in [Stack-Refactor-Execution-Plan.md](/Users/ilwonyoon/Documents/PromptCue/docs/Stack-Refactor-Execution-Plan.md)

## Baseline

Current `main` is the only valid baseline.

Current shipped stack contract:

- clicking an active card stages it for grouped copy
- clicking the same staged card again unstages it
- the grouped clipboard payload updates immediately while the stack stays open
- copied ordering commits on stack close, not on click

Current UI problem:

- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift) only shows the header when `stagedCopiedCount > 0`
- that conditional header causes the list to jump downward as soon as a card is clicked
- ephemerality is currently implicit instead of visible
- filtering between active and copied notes does not exist yet
- logo behavior across in-app chrome and status-item chrome is not explicitly locked in one place

## Terminology Split

This slice should explicitly separate:

- internal/storage terminology
- launch-facing UI terminology

### Internal Terminology

Keep these words in code, storage, and MCP unless a separate migration is approved:

- `Active`
  - cards that are not yet in copied state
- `Staged`
  - the transient open-panel selection used for grouped copy
- `Copied`
  - cards that have entered copied ordering after commit

Reason:

- current stack storage and sort rules already use copied state
- MCP tools and prompts already use `active` and `copied`
- renaming the domain while redesigning the header would expand blast radius unnecessarily

### Launch-Facing Terminology Decision

The launch UI should not assume that the internal storage term must also be the best user-facing label.

Locked launch-facing terms:

- `On Stage`
  - cards that are still live in the queue
- `Offstage`
  - cards that have left the active queue after use

Immediate action feedback remains:

- `Copied`

This means the product intentionally uses:

- internal semantics for storage and MCP
- stage-based language for long-lived user-facing queue state
- direct clipboard language for the immediate copy action

### Launch Recommendation

Recommended launch split:

- keep internal semantics as `active / staged / copied`
- keep immediate action feedback as `Copied`
- use `On Stage / Offstage` as the user-facing queue language

Recommended launch wording:

- summary: `N on stage · N offstage`
- filter: `All / On Stage / Offstage`
- lower bucket header: `Offstage`
- transient feedback: `1 Copied`, `2 Copied`

Reason:

- it matches Backtick's thought-staging metaphor directly
- it preserves `stage` as a product concept instead of reducing it to an implementation detail
- it lets the long-lived lower bucket feel like "this thought has left the stage" instead of "this item was literally copied"
- it keeps the immediate clipboard action accurate with `Copied`
- it avoids turning Backtick into a task manager by using heavier labels like `Completed`

Important rule:

- `Staged` should remain an internal interaction term
- it should not become the visible label for the long-lived user-facing bucket
- otherwise the temporary click-selection state and the product's stage metaphor will collide

## Product-Level Goals

The new stack header rail must satisfy all of these at once.

1. no layout jump when staged state changes
2. one persistent header rail above the card list
3. quiet summary language for overall queue state
4. strong, localized feedback for staged copy actions
5. theme-adaptive logo treatment that is correct for both app chrome and macOS status-item chrome
6. lightweight filter controls without turning Stack into a management dashboard
7. ephemerality signaled on the cards themselves, not as heavy header copy

## Non-Goals

This slice must not do any of the following:

- redesign AI grouping
- rename copied-state semantics across the app
- change the grouped-copy-on-click and commit-on-close model
- redesign copied-stack collapse behavior outside the new filter rule
- add onboarding copy, subtitles, or extra helper rows to Stack
- redesign card ordering rules
- redesign the menu-bar icon shape or app-icon assets

## UX Contract

### 1. Persistent Header Rail

The header rail always occupies the same height, even when nothing is staged.

Recommended structure:

- left: Backtick logo
- center-left: subtle queue summary
- right: transient staged-copy feedback
- far right: filter button that opens a context menu

The card list must never move vertically when staged state changes.

### 2. Summary Language

Default summary wording:

- `N on stage · N offstage`

This summary is quiet and informational. It is not the place for strong action feedback.

The summary reflects total queue state, not just the currently filtered subset.

Reason:

- users still need queue awareness while a filter is active
- keeping one summary grammar avoids the header from changing too much at once

### 3. Staged-Copy Feedback

The strong feedback slot lives on the right side of the rail and is separate from the quiet summary.

When staged count is non-zero, show:

- `1 Copied`
- `2 Copied`
- `N Copied`

Important meaning rule:

- this is immediate action feedback for the live clipboard payload
- it does not mean copied ordering has already committed in persistence
- underlying commit-on-close behavior remains unchanged

When staged count returns to zero, hide the feedback slot instead of replacing it with another badge.

### 4. Filter Button

The far-right control is a filter button, not a sort toggle.

Menu options:

- `All`
- `On Stage`
- `Offstage`

Default:

- `All`

Behavior:

- `All`
  - show active cards first and copied cards in their existing copied section
- `On Stage`
  - show only active cards
- `Offstage`
  - show only copied cards, directly as an offstage list instead of the collapsed copied summary

The filter is session-local UI state. It is not persisted to settings.

### 5. Card TTL Ring

Ephemerality should move from header text into the cards themselves.

For active cards only:

- show a small ring near the bottom-right corner
- target size: approximately `8px`
- use two layers:
  - a quiet track circle
  - a progress arc
- the progress arc shrinks clockwise as TTL is consumed

Visibility rules:

- show only for active cards
- hide for copied cards
- hide when auto-expire is off

Timing rules:

- compute progress from card age versus effective TTL
- do not animate per second
- use coarse refresh intervals that are sufficient for an 8-hour TTL

### 6. Logo Theme Contract

This slice locks two distinct logo behaviors.

#### In-App Stack Header Logo

The header rail logo follows the current app appearance.

Rules:

- use the Backtick mark as stack chrome, not as a colorful app-icon badge
- prefer template or semantic foreground rendering so the mark adapts cleanly in light and dark themes
- the mark should feel quiet and anchored, not dominant

#### macOS Status-Item Logo

The status-item icon must continue to follow macOS appearance, not the user-selected app appearance.

Rules:

- keep template rendering
- keep `NSStatusItem` image behavior OS-driven
- do not tie the menu-bar icon to the in-app theme override

This means stack chrome and status-item chrome intentionally do not use the same appearance rule.

## Rendering Contract

### Header Rail Visual Hierarchy

- logo: quiet anchor
- summary: subtle
- staged-copy feedback: strongest text in the rail
- filter button: quiet utility affordance

Recommended tone:

- summary uses secondary text styling
- count numerals may use a slightly stronger weight than the surrounding words
- staged-copy feedback uses stronger weight and clearer contrast than the summary
- the rail should still feel lighter than a toolbar

### TTL Ring Visual Hierarchy

- the ring should be readable when noticed
- the ring should disappear into the card when ignored
- avoid warning-red semantics unless the product later chooses a dedicated expiry-warning state

## Architecture And Ownership

Keep this slice narrow.

### App Target Ownership

- stack header rail layout
- filter menu interaction
- staged-copy feedback binding
- logo rendering in stack chrome
- copied-only presentation mode

Expected files:

- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift)
- possible new stack-header component files under `PromptCue/UI/Views` or `PromptCue/UI/Components`
- [AppCoordinator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppCoordinator.swift) only if the status-item logo contract needs a guardrail note or small supporting fix

### PromptCueCore Ownership

Use `PromptCueCore` for anything pure and testable:

- TTL progress calculation
- summary formatting helpers if kept logic-only
- filter/view-model formatting rules if they are independent of AppKit/SwiftUI

### Keep Existing Model Semantics

Do not change:

- staged copy contract in `AppModel`
- copied commit timing
- copied ordering rules
- clipboard composition timing
- storage and MCP naming of copied state

## Implementation Phases

### Phase 1. Freeze Header State Contract

Define a small view-model or formatting layer for:

- active count
- copied count
- staged count
- current filter
- whether the staged feedback slot is visible

This layer should decide:

- summary string
- staged feedback string
- which card sections are visible

### Phase 2. Replace The Conditional Header

Remove the current staged-only header and introduce the persistent rail.

Must preserve:

- existing card ordering
- existing copied collapse behavior in `All`
- no vertical jump on click

### Phase 3. Add Filter Menu

Add the far-right filter control with the locked three-option menu.

Keep this state local to the stack presentation unless a later product need proves persistence is necessary.

### Phase 4. Add TTL Ring

Add the active-card-only TTL ring.

Implementation rules:

- no per-card timers
- no high-frequency invalidation loop
- no extra text label next to the ring

### Phase 5. Lock Logo Appearance Rules

Make the stack header logo and status-item logo obey their separate appearance rules intentionally rather than incidentally.

If template rendering is not visually sufficient for the stack header mark, add a dedicated header-logo treatment without changing the status-item contract.

## Verification

Minimum verification before landing:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Required targeted checks:

- [StackMultiCopyTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/StackMultiCopyTests.swift) stays green
- new tests cover header summary and filter behavior
- new tests cover TTL progress visibility rules

Manual QA:

- clicking a card does not push the list downward
- rail always remains at a stable height
- summary reads as quiet state, not as a badge wall
- staged feedback is obvious and disappears when stage returns to zero
- `All`, `Active`, and `Copied` filters all read correctly
- copied-only filter shows copied cards directly instead of a collapsed summary plate
- active cards show the TTL ring only when auto-expire is enabled
- copied cards do not show the TTL ring
- stack header logo reads correctly in light and dark app themes
- status-item icon still follows macOS appearance rather than app theme overrides

## Abort Conditions

Stop and split the work if any of these become necessary:

- changing grouped-copy commit timing
- renaming copied semantics across storage, MCP, and UI
- redesigning copied-stack collapse behavior beyond the copied-only filter path
- adding AI grouping into the same branch
- changing capture panel, selector, or menu-bar ownership to make the stack header work

If any of those appear, do not keep widening this same slice.
