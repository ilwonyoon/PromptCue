# Capture Suggested-Target Selector V2 Replacement Plan

## Purpose

Replace the capture suggested-target selector as a narrow subsystem so future visual or interaction changes stop causing state, outline, or keyboard regressions.

Status: completed on `main`. Selector is fully fixed under this v2 replacement contract.

This plan is intentionally limited to the capture suggested-target selector:

- inline selector accessory
- detached chooser panel content
- selection, focus, and hover state contracts
- chooser row and accessory chrome ownership

This plan does not reopen capture panel ownership, screenshot lifecycle, or suggested-target provider startup policy.

## Baseline

Current `main` is the behavioral baseline.

The last accepted local recovery state is:

- `25cc8a6` restored rich suggested-target resolution and warm-start behavior
- `0f4cdea` tuned chooser contrast
- `f5945ad` and `9f6688e` reverted failed selector-contract experiments

For this plan, treat current `main` after those reverts as the only valid starting point.

## Why Patch-Based Repair Failed

The repeated regressions were not caused by one bad color value. They came from a structural mismatch between state ownership and rendering ownership.

### 1. One Index Drives Too Much

Current selector behavior still hangs off `selectedCaptureSuggestedTargetIndex` in:

- [AppModel+SuggestedTarget.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+SuggestedTarget.swift)

That single index currently stands in for:

- committed choice
- keyboard focus
- highlighted row

As a result, changing one interaction path often changes another.

### 2. Accessory And Chooser Do Not Share The Same Job

The inline accessory and the detached chooser both display target information, but they do not need the same rendering contract.

Current implementation still computes chooser visuals directly inside:

- [CaptureSuggestedTargetViews.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift)

That makes it too easy to fix chooser visuals and accidentally change the inline selector, or vice versa.

### 3. Visual Repair Was Attempted Before Contract Repair

Recent attempts tried to improve:

- outline stroke
- selected fill brightness
- hover behavior

without first separating:

- committed selection
- focused choice
- local hover state

That is why the system repeatedly regressed into:

- more than one active-looking row
- outline stroke reappearing
- focus or keyboard behavior becoming unstable

### 4. Keyboard Ownership Is Too Sensitive To Touch During Selector Work

The capture panel is a sensitive AppKit surface.

Keyboard and panel ownership currently work again, but past attempts showed that selector work can easily bleed into:

- capture panel key handling
- chooser panel activation
- editor first responder behavior

That means keyboard ownership must be treated as a frozen outer boundary, not part of selector v2.

## Product-Level Requirements

Selector v2 must satisfy all of these, simultaneously.

### Visual Contract

- no outline stroke in default chooser rows
- selected row uses a `#ffffff`-adjacent fill in light mode
- only one row may look selected at a time
- hover may exist, but it must not look selected
- focus may exist, but it must remain visually weaker than selected
- inline accessory and chooser row chrome must be independently stylable

### Interaction Contract

- opening the chooser must not slow capture readiness
- keyboard behavior must remain exactly as it works in the current baseline
- arrow key movement must move chooser focus only
- `Enter` must commit the focused choice
- `Esc` must close the chooser without changing the committed choice
- mouse hover must not mutate committed choice
- mouse hover must not mutate keyboard focus

### Data Contract

- automatic target remains the committed choice when no explicit override exists
- explicit override becomes committed only after explicit completion
- target labels and metadata remain sourced from the existing target-resolution path
- selector v2 must not change `cwd`, repo, branch, or provider freshness policy

## Non-Goals

Selector v2 must not attempt to fix or redesign any of the following:

- capture panel style mask or window class
- chooser panel key-window behavior
- editor focus plumbing
- `RecentSuggestedAppTargetTracker` startup lifecycle
- `CaptureSuggestedTarget` label-policy redesign
- screenshot onboarding, screenshot expiration, or screenshot slot behavior

If work in those areas becomes necessary, stop and split that into a separate task.

## Replacement Strategy

Do not patch the existing selector in place.

Instead:

1. keep current `main` behavior as the shipping baseline
2. introduce a new selector state layer behind the same outer app contract
3. migrate the chooser and accessory to that new state layer
4. remove the legacy index-driven coupling only after the new path passes verification

This is a subsystem replacement, not a visual tweak pass.

## Proposed Architecture

### 1. Add A Selector-Specific State Model

Introduce a small selector state model in the app target.

Recommended shape:

- `CaptureSuggestedTargetSelectorState`
- `CaptureSuggestedTargetSelectorChoice`
- `CaptureSuggestedTargetSelectorRowState`

Suggested row states:

- `selected`
- `focused`
- `hovered`
- `idle`

The important rule is that row state is derived in one place, not scattered across the view tree.

### 2. Separate Committed Choice From Focused Choice

Introduce explicit identities:

- `committedChoiceID`
- `focusedChoiceID`

Identity rules:

- automatic target uses a reserved selector ID such as `__automatic__`
- explicit targets use `canonicalIdentityKey`

Contract:

- `committedChoiceID` is derived from `draftSuggestedTargetOverride` plus `automaticSuggestedTarget`
- `focusedChoiceID` exists only while the chooser is open
- when the chooser opens, focus starts from the committed choice
- when the chooser closes without completion, committed choice remains unchanged

### 3. Keep Hover Local To The Row

Hover must not live in `AppModel`.

Allowed:

- local `@State private var isHovered`

Forbidden:

- changing committed choice on hover
- changing focused choice on hover
- writing hover-derived state back into `AppModel`

### 4. Add A View-Model Layer For Rendering

The view should not deduce selection and focus by juggling several booleans.

Instead, build a row model list once per render:

- `id`
- `target`
- `isAutomatic`
- `rowState`
- `showsRecentBadge`

Recommended ownership:

- `AppModel` owns committed/focused identities
- a selector adapter builds row models from those identities
- SwiftUI rows render only the already-derived `rowState`

### 5. Split Accessory And Chooser Chrome Permanently

Keep two distinct primitives:

- `SuggestedTargetAccessoryChrome`
- `SuggestedTargetChooserRowChrome`

Rules:

- accessory chrome must never inherit chooser border or chooser fill behavior
- chooser chrome owns selected/focused/hover visual differences
- accessory chrome stays visually quiet and only reflects the committed target

## File Ownership

### Master-Owned

- [PromptCue/App/AppModel.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel.swift)
- [PromptCue/App/AppModel+SuggestedTarget.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+SuggestedTarget.swift)
- [PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift)
- [PromptCueTests/AppModelSuggestedTargetTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/AppModelSuggestedTargetTests.swift)

### Explicitly Out Of Scope For V2

- [PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)
- [PromptCue/UI/WindowControllers/CapturePanelController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers/CapturePanelController.swift)
- [PromptCue/Services/RecentSuggestedAppTargetTracker.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentSuggestedAppTargetTracker.swift)
- [Sources/PromptCueCore/CaptureSuggestedTarget.swift](/Users/ilwonyoon/Documents/PromptCue/Sources/PromptCueCore/CaptureSuggestedTarget.swift)

Those files may be read for context, but they must not be edited as part of selector v2 unless a separate blocker is identified first.

## Implementation Phases

### Phase 1. Freeze The Outer Contract

Work:

- keep current panel ownership and keyboard behavior unchanged
- keep current target-resolution and chooser label policy unchanged
- document the current baseline and rejected recent regressions

Exit criteria:

- no selector v2 work depends on panel or provider changes

### Phase 2. Introduce Internal Selector State

Files:

- [AppModel+SuggestedTarget.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+SuggestedTarget.swift)
- [AppModel.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel.swift)

Work:

- add explicit committed and focused choice identity
- keep `selectedCaptureSuggestedTargetIndex` only as a compatibility bridge during migration if needed
- ensure chooser open/close/complete/cancel paths are fully deterministic

Exit criteria:

- model can represent committed and focused states independently
- no hover path is modeled in `AppModel`

### Phase 3. Replace Row Rendering

Files:

- [CaptureSuggestedTargetViews.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift)

Work:

- introduce row view models or a selector adapter
- render rows from `rowState` instead of open-coded booleans
- apply strict visual hierarchy:
  - `selected`: strong white fill
  - `focused`: weaker than selected
  - `hovered`: weaker than focused
  - `idle`: base fill

Exit criteria:

- exactly one row can render as selected
- hover never creates a second selected-looking row
- no default outline stroke appears

### Phase 4. Remove Legacy Glue

Work:

- delete index-driven assumptions that are no longer needed
- remove dead helpers that only existed to support the old selector path

Exit criteria:

- selector state no longer depends on one mutable index as the primary truth

## Verification

Minimum required verification:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Required selector-specific automated coverage:

- opening chooser starts focused choice from committed choice
- moving keyboard focus does not change committed choice
- cancel restores committed choice and closes chooser
- complete commits the focused choice
- automatic and explicit IDs remain stable across refreshes

Required manual QA:

1. Open capture with one automatic target and at least two explicit targets.
2. Confirm exactly one row looks selected.
3. Move keyboard focus to a different row.
4. Confirm the newly focused row does not overwrite the committed target until completion.
5. Hover a third row.
6. Confirm hover does not create a second selected-looking state.
7. Confirm no outline stroke appears in default rows.
8. Confirm the selected row reads as `#ffffff`-adjacent in light mode.
9. Confirm `Esc`, arrow keys, `Tab`, and `Enter` all behave exactly as in the current baseline.

## Abort Conditions

Stop selector v2 immediately if any of these occur:

- typing in the capture editor breaks
- panel focus or key-window behavior changes
- chooser opening latency changes noticeably
- target labels regress back to low-information placeholders

If any abort condition occurs, revert to baseline and split the blocker into a separate task before continuing selector work.

## Success Definition

Selector v2 is complete only when:

- current baseline behavior is preserved
- visual regressions stop recurring
- one selected-looking row is guaranteed by contract
- future brightness or polish changes can be made without touching keyboard or panel ownership

Until then, current `main` remains the shipping fallback.
