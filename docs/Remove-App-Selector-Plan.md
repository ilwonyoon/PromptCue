# Remove App Selector (Suggested Target) Plan

Date: 2026-03-19
Branch: `refactor/remove-app-selector`
Worktree: `../PromptCue-remove-app-selector`

## Motivation

App selector (~2,200 LOC) provides low user value relative to its complexity:

- Auto-detection is unreliable (most recently used app != intent)
- Manual selection adds friction to a capture flow that should be <2 seconds
- Tags (`#tag`) already cover the same need with higher accuracy and lower friction
- OS-level introspection (osascript, CGWindowList, lsof, git) is brittle across macOS updates

## Scope

Remove the entire suggested target feature: domain model, service, state management, UI (capture panel pill + chooser popup + stack card badge), persistence, MCP schema, tests, docs.

**NOT in scope:** Tag feature improvements (separate track).

## Impact Summary

| Metric | Before | After |
|--------|--------|-------|
| Files deleted | — | 7 |
| Files edited | — | 16 |
| LOC removed | — | ~3,500 |
| Capture panel height (default) | ~206pt | ~172pt |
| Capture panel content stack items | 4 | 3 |

## Layout Changes

### Capture panel (before)

```
┌───────────────────────────────────────────┐
│  [24pt top pad]                           │
│  ── screenshot (hidden by default)        │
│  ── [12pt spacing]                        │
│  ── suggested target pill  ← REMOVING     │
│  ── [12pt spacing]                        │
│  ── text editor (54–176pt)                │
│  ── [12pt spacing if tags visible]        │
│  ── inline tag suggestions (hidden)       │
│  [24pt bottom pad]                        │
└───────────────────────────────────────────┘
```

### Capture panel (after)

```
┌───────────────────────────────────────────┐
│  [24pt top pad]                           │
│  ── screenshot (hidden by default)        │
│  ── [12pt spacing]                        │
│  ── text editor (54–176pt)                │
│  ── [12pt spacing if tags visible]        │
│  ── inline tag suggestions (hidden)       │
│  [24pt bottom pad]                        │
└───────────────────────────────────────────┘
```

Panel shrinks by ~30-34pt (pill height + spacing). The editor moves up to directly below the top pad (or screenshot if visible). No visual gaps because NSStackView automatically removes spacing for absent arranged subviews.

### Stack cards (before vs after)

Card bottom area currently shows a suggested target badge (`CaptureCardSuggestedTargetAccessoryView`). After removal, that space simply disappears — cards become shorter. Existing cards with stored `suggestedTarget` JSON will just ignore the orphaned column.

### Chooser popup panel

The `CaptureSuggestedTargetPanel` (separate NSPanel child window that appears above the capture panel) is removed entirely. No replacement needed.

## Height formula change

```swift
// BEFORE
minimumSurfaceHeight(
    editorHeight: 54,
    inlineTagSuggestionHeight: 0,
    suggestedTargetHeight: ~34,  // pill + 12pt spacing
    screenshotHeight: 0
)
// = max(70, 54 + 0 + 0 + 34 + 48) = 136pt

// AFTER — remove suggestedTargetHeight parameter entirely
minimumSurfaceHeight(
    editorHeight: 54,
    inlineTagSuggestionHeight: 0,
    screenshotHeight: 0
)
// = max(70, 54 + 0 + 0 + 48) = 102pt
```

Panel height: `ceil(28 + 102 + 42) = 172pt` (was ~206pt).

## Execution Phases

### Phase 1: Model layer (PromptCueCore)

**Files:**
- DELETE `Sources/PromptCueCore/CaptureSuggestedTarget.swift`
- EDIT `Sources/PromptCueCore/CaptureCard.swift`
  - Remove `suggestedTarget` property, CodingKey, init parameter, encode/decode
  - Remove `updatingSuggestedTarget(_:)` method
  - Remove `suggestedTarget` parameter from `updatingContent(...)`
  - Remove `suggestedTarget: suggestedTarget` from `markCopied()`, `togglePinned()`, `clearCopied()`

**Verify:** `swift test` (expect compile errors in app target, that's fine — core tests should pass after editing test file)

**Test edits:**
- EDIT `Tests/PromptCueCoreTests/PromptCueCoreTests.swift` — remove ~15 suggestedTarget tests and `makeSuggestedTarget()` helper

### Phase 2: Service layer

**Files:**
- DELETE `PromptCue/Services/RecentSuggestedAppTargetTracker.swift`
- EDIT `PromptCue/Services/CardStore.swift`
  - Remove `suggestedTargetJSON` from `PersistableCard`
  - Remove `encodeSuggestedTarget` / `decodeSuggestedTarget` methods
- EDIT `PromptCue/Services/PromptCueDatabase.swift`
  - Keep `"addSuggestedTargetJSON"` migration entry but **empty the body** (GRDB requires migration ordering)
- EDIT `PromptCue/Services/StackWriteService.swift`
  - Remove `suggestedTarget` from `StackNoteCreateRequest` and `StackNoteUpdateRequest`
- EDIT `PromptCue/Services/StackReadService.swift`
  - Remove `suggestedTarget`-based classification in `classifyNotes`
- EDIT `PromptCue/Services/StackExecutionService.swift`
  - Remove `suggestedTargetJSON` from local persistable struct

### Phase 3: AppModel state

**Files:**
- DELETE `PromptCue/App/AppModel+SuggestedTarget.swift`
- EDIT `PromptCue/App/AppModel.swift`
  - Remove `CaptureSuggestedTargetChoice` enum
  - Remove ~15 `@Published` properties (availableSuggestedTargets, isShowingCaptureSuggestedTargetChooser, etc.)
  - Remove `suggestedTargetProvider` property and init parameter
  - Remove `ensureSuggestedTargetProviderStarted()`, `refreshSuggestedTargetProviderLifecycle()`, `stopSuggestedTargetProvider()`
  - Remove `assignSuggestedTarget(_:to:)` method
  - Remove target state cleanup in `start()` / `stop()`
  - Remove `suggestedTarget:` from `card(_:replacingScreenshotPath:)`
- EDIT `PromptCue/App/AppModel+CaptureSession.swift`
  - Remove chooser state resets from `beginCaptureSession()`, `endCaptureSession()`
  - Remove `draftSuggestedTargetOverride` from `beginEditingCaptureCard()`
  - Remove `suggestedTarget: effectiveCaptureSuggestedTarget` from card creation in `submitCapture()`
  - Remove target state resets from `clearDraft()`

**Test edits:**
- DELETE `PromptCueTests/AppModelSuggestedTargetTests.swift`
- EDIT `PromptCueTests/AppModelEditingTests.swift` — remove suggested target test, `EditingTestSuggestedTargetProvider`, `makeTarget()`

### Phase 4: UI layer

**Files:**
- DELETE `PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift`
- EDIT `PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift`
  - Remove `suggestedTargetAccessoryView` property and init
  - Remove from `contentStack` (was slot [2])
  - Remove `suggestedTargetHeight` from `minimumSurfaceHeight` — drop the parameter entirely
  - Remove `suggestedTargetAccessoryView.layoutSubtreeIfNeeded()` from `recomputePreferredPanelHeight()`
  - Remove `$availableSuggestedTargets` and `$isShowingCaptureSuggestedTargetChooser` subscribers from `bindModel()`
  - Remove `updateSuggestedTargetAccessory()` and `makeSuggestedTargetAccessoryView()`
  - Remove chooser keyboard routing from `handleEditorCommand` and `shouldPromoteUpArrowToChooserOpen()`
  - Remove `suggestedTargetHeight` from bootstrap height calculation
  - Remove appearance refresh for suggestedTargetAccessoryView
- EDIT `PromptCue/UI/WindowControllers/CapturePanelController.swift`
  - Remove `suggestedTargetPanel` property, observer, and all ~320 lines of private panel classes
  - Remove `makeSuggestedTargetPanel()`, `suggestedTargetPanelFrame()`, `updateSuggestedTargetPanelIfNeeded()`
  - Remove `desiredSuggestedTargetPanelHeight()`, `suggestedTargetVisibleRowUnits()`
  - Remove `CaptureSuggestedTargetPanelLayout` enum
  - Remove `detachAuxiliaryPanel(suggestedTargetPanel)` from `close()`
  - Remove from `visiblePanels()`
  - Remove from `refreshForInheritedAppearanceChange()`
  - Remove chooser dismiss check from mouse-outside handler
- EDIT `PromptCue/UI/Views/CaptureCardView.swift`
  - Remove `availableSuggestedTargets`, `automaticSuggestedTarget` properties
  - Remove `onRefreshSuggestedTargets`, `onAssignSuggestedTarget` callbacks
  - Remove `CaptureCardSuggestedTargetAccessoryView` from card body
- EDIT `PromptCue/UI/Views/CardStackView.swift`
  - Remove target-related properties passed to `CaptureCardView`

### Phase 5: Design tokens and constants

**Files:**
- EDIT `PromptCue/UI/DesignSystem/SemanticTokens.swift`
  - Remove `Surface.captureChooserRowFill`, `captureChooserRowHoverFill`, `captureChooserRowSelectedFill`
  - Remove `Border.captureChooserRow`, `captureChooserRowHover`, `captureChooserRowSelected`
- EDIT `PromptCue/App/AppUIConstants.swift`
  - Remove all `captureChooser*` constants
  - Remove `captureSelectorControlWidth`
  - Remove `suggestedTargetFreshness`
  - Remove `captureChooserVisibleRowUnits(for:allowsPeekRow:)` method

### Phase 6: MCP server

**Files:**
- EDIT `Sources/BacktickMCPServer/BacktickMCPServerSession.swift`
  - Remove `suggestedTarget` from `create_note` and `update_note` input schemas
  - Remove `suggestedTargetSchema()` method
  - Remove `parseSuggestedTarget()`, `parseConfidence()`, `parseSuggestedTargetUpdate()` helpers
  - Remove `suggestedTargetDictionary()` helper
  - Remove `suggestedTarget` from note serialization
  - **Backward compat note:** Existing MCP clients that send `suggestedTarget` in requests will get a validation error if using `additionalProperties: false`. Consider whether to keep the field as ignored for one version cycle. Recommendation: remove cleanly since this is pre-launch.

**Test edits:**
- EDIT `Tests/BacktickMCPServerTests/BacktickMCPServerTests.swift` — remove `suggestedTarget` from test payloads

### Phase 7: Documentation

**Files:**
- DELETE `docs/Capture-Suggested-Target-Selector-Repair-Plan.md`
- EDIT `docs/PR50-Inline-Tag-Integration-Runbook.md` — remove suggested target references (if any remain)

### Phase 8: Regenerate and verify

```bash
cd ../PromptCue-remove-app-selector

# 1. Regenerate Xcode project
xcodegen generate

# 2. Core package tests
swift test

# 3. App build
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

# 4. App tests
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test

# 5. MCP server tests
swift test --filter BacktickMCPServerTests

# 6. Token validation
python3 scripts/validate_ui_tokens.py
```

## Safety Checklist

- [ ] DB migration entry preserved (body emptied, not deleted)
- [ ] `CaptureCard` still decodes old JSON with `suggestedTarget` field (graceful ignore via optional + removed CodingKey)
- [ ] No orphaned `import` statements
- [ ] No orphaned protocol conformances
- [ ] Panel height visually correct (no phantom spacing)
- [ ] Up-arrow in editor no longer triggers chooser (just moves cursor)
- [ ] `classify_notes` MCP tool still works (falls back to tag-based or returns ungrouped)
- [ ] All 4 test suites pass: core, app, MCP, tokens
- [ ] `xcodegen generate` produces clean project

## Merge Strategy

1. Complete all phases in worktree
2. Each phase: edit → build → fix compile errors → repeat until clean
3. Final full verification (Phase 8 checklist)
4. `git diff main...refactor/remove-app-selector --stat` for final review
5. **Conflict check:** `CaptureCard.swift`, `AppModel.swift`, `CapturePanelController.swift` are high-conflict files — check if other branches touch them
6. PR to `main` with clear scope description
7. Post-merge: `xcodegen generate` + full build + test on `main`

## Risks

| Risk | Mitigation |
|------|-----------|
| Old databases with `suggestedTargetJSON` column | Column stays orphaned, GRDB ignores unused columns, migration entry preserved |
| MCP clients sending `suggestedTarget` in requests | Pre-launch, clean break acceptable. If needed, keep field as optional ignored param |
| Other branches touching same files | Check `feat/revert-copied-to-active` diff before merge. Key conflict files: `CaptureCard.swift`, `AppModel.swift`, `CapturePanelController.swift` |
| Capture panel feels too short after removal | 172pt is still above the 70pt floor. Editor gets the same space. Visually cleaner. |
