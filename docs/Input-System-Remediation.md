# Prompt Cue Input System Remediation

## Purpose

This document defines the diagnosis and remediation plan for the capture input box.

The current input works for simple typing, but it is not yet engineered for the real workload Prompt Cue needs to support:

- slow manual typing
- rapid typing bursts
- large paste payloads
- IME/composition input
- placeholder + screenshot slot layout changes
- expansion into internal scrolling without visual jump

The goal is not just to patch visible glitches. The goal is to give Prompt Cue a durable input architecture.

## Current Symptoms

The current implementation shows these user-visible failures:

1. The capture text can jump or flicker when a new line wraps.
2. Large paste payloads can render outside the capture surface before the shell catches up.
3. The panel can resize after the text view has already drawn the new content, which makes the input feel unstable.
4. Input behavior is optimized for one-key-at-a-time typing, not for burst insertions.
5. The current shell is too dependent on SwiftUI update timing for per-keystroke sizing.

## Root Diagnosis

### 1. Two-phase sizing causes the visible lag

The current sizing path is:

1. `NSTextView` lays out the new text.
2. `CueEditorContainerView` measures the new used height.
3. `onMetricsChange` writes into `AppModel.draftEditorMetrics`.
4. `CaptureComposerView` rebuilds and updates the SwiftUI frame.
5. `CapturePanelController` resizes the floating panel.

That means the AppKit editor grows first and the SwiftUI shell follows later.

This is the main reason large paste can draw outside the capture box for a frame.

### 1a. Split height ownership is the confirmed architectural blocker

The current runtime has three different layers trying to own editor height:

1. `CueEditorContainerView` sets the inner AppKit document view height.
2. `CaptureComposerView` clamps the representable using `draftEditorMetrics.visibleHeight`.
3. `CapturePanelController` resizes the floating panel after the model publishes that new height.

That means one wrap event is not one layout transaction. It is a chain:

1. AppKit lays out text
2. editor metrics are recomputed
3. SwiftUI updates the editor frame
4. the panel catches up afterward

That is why the “line 1 becomes line 2” moment still flickers even after padding tweaks.

### 1b. Bottom padding is still coupled to measured content, not owned as shell chrome

The latest fixes added more inset and a bottom breathing-room constant, but those values are still baked into the measured editor height.

That means bottom padding is still not a separate visual guarantee. It only appears after the outer frame has consumed the new measured height. When the second line first appears, the text can still render before the shell has fully claimed the extra space.

For Prompt Cue, these need to be separate values:

- text content height
- visible editor height
- persistent shell bottom padding

If they remain one number, the same “text moves first, shell catches up later” artifact will keep coming back.

### 2. The input shell is still partially view-driven instead of editor-driven

`CaptureComposerView` uses SwiftUI layout to size the editor and then asks AppKit to follow.

For a multiline editor, the safer direction is the opposite:

- the AppKit editor should own its content height
- the panel shell should read that height and adapt
- SwiftUI should not be the first responder for per-keystroke geometry

### 3. Wrapping and resizing are coupled too tightly

When a wrap happens, multiple things can change together:

- line fragments
- text view used rect
- editor visible height
- panel height
- screenshot slot layout

Right now those changes happen in adjacent frames rather than one coherent layout transaction.

### 4. Width becomes unstable at the scroll threshold

The current measurement path computes height from the current scroll-view width and only then decides whether the vertical scroller should appear.

That means the editor can measure against one width and then render against a smaller width after the scroller appears.

This creates:

- rewrap right at the threshold
- extra height churn
- visible jump when a new line crosses the clamp boundary

### 5. The editor does not explicitly keep the caret visible after large paste

Once content exceeds the visible-height cap, the editor becomes scrollable, but there is no explicit guarantee that the insertion point is scrolled into view after a large paste.

That is a major reason paste can feel like the content escaped the shell even when the editor technically became scrollable.

### 6. The editor still does more mutation than necessary during updates

The recent cleanup removed the worst repeated styling path, but the current `NSViewRepresentable` bridge still rebuilds through SwiftUI on each content change.

That is acceptable for simple text, but it is still fragile under:

- paste bursts
- composition
- selection preservation
- future undo/redo polish

### 7. Command routing is not IME-safe yet

The current submit/cancel path is driven from raw `keyDown` interception.

That is too low-level for a production multiline text surface.

It risks conflicts with:

- marked text / IME composition
- newline handling during composition
- future text commands and undo grouping

### 8. There is no dedicated paste burst strategy

Large paste currently follows the exact same path as one typed character.

That is the wrong model.

Paste should be treated as a transaction with:

- immediate content insertion
- immediate synchronous height clamp
- one shell resize
- no intermediate overflow frame

## Input Quality Bar

Prompt Cue should treat the capture editor as a first-class system component.

The input box should support all of these reliably:

1. Single-line typing with no layout shimmer.
2. Rapid multiline typing with no jump at wrap boundaries.
3. Large paste payloads with no one-frame overflow outside the capture surface.
4. `Shift + Enter` newline insertion with stable cursor position.
5. IME/composition with no forced premature submission.
6. Undo/redo that preserves text, cursor, and measured height.
7. Screenshot slot presence or absence without moving the text unexpectedly.
8. Automatic transition from grow-to-fit into internal scrolling at the height cap.
9. Focus changes that do not lose draft text or selection.
10. Placeholder behavior that does not fight with composition or pasted content.

## Recommended Architecture

### A. Make AppKit own editor layout

The multiline input should be driven by a dedicated AppKit editor surface.

That surface should own:

- current text
- current measured content height
- current visible height
- current scroll state
- selection and composition state

SwiftUI should consume a stable editor host, not participate in line-by-line remeasurement.

### B. Split height into two explicit values

The editor should track:

- `contentHeight`: full measured text height
- `visibleHeight`: clamped height shown in the UI

This prevents a large paste from first expanding content outside the shell.

The shell should always render against `visibleHeight`.

### C. Reserve the shell before the content paints

For wrap or paste events:

1. measure the next content height
2. compute the clamped visible height
3. resize the shell
4. then allow the new frame to present

The UI should not show the new content with the old shell size.

### D. Treat paste as a transaction

Paste should have a dedicated path.

The editor should:

- detect paste entry
- insert text
- synchronously recompute measured height
- clamp to max visible height
- invalidate intrinsic size once
- scroll only if over cap
- ensure the insertion point is visible after the transaction

### E. Move placeholder ownership into the AppKit editor host

The placeholder is currently a SwiftUI overlay.

That is serviceable for small cases, but it is not ideal for:

- composition
- very large paste
- text storage changes
- selection edge cases

The placeholder should ultimately belong to the editor host so it is driven by the real text state.

### F. Use command routing that is composition-safe

Submit and cancel should be handled through text-system command routing, not only raw key interception.

The editor host should know:

- whether marked text is active
- whether `Return` means newline or submit in the current state
- when `Escape` should cancel composition instead of dismissing the panel

### G. Explicitly support undo

The text view should enable undo and preserve selection/caret state through external model sync.

Prompt Cue is small, but users still expect paste, undo, and rapid correction to behave like a real native editor.

## Proposed Implementation Plan

## Confirmed R7 Reframe

The current diagnosis means the remaining capture-input issues are not “just more tuning.”

The safe next step is:

1. move live measurement back to the AppKit editor host
2. expose one resolved visible height to SwiftUI
3. let the panel resize from that resolved height only
4. keep shell padding as shell chrome, not part of measured text height

That is the minimum architectural shift needed to fix both:

- wrap flicker
- bottom padding lag

## Phase R7B: AppKit-Owned Sizing Rewrite

### Goal

Replace the current split ownership path with a single AppKit-owned capture host for the live capture panel.

### Locked Design

1. The live capture panel will stop using `CaptureComposerView` for runtime input layout.
2. `CueEditorContainerView` will become the source of truth for:
   - content height
   - visible height
   - scrollability
   - placeholder visibility
3. The capture shell will own shell chrome separately:
   - horizontal padding
   - top padding
   - bottom breathing room
4. `CapturePanelController` will resize the panel from one resolved host height only.
5. `AppModel` remains the source of truth for draft text and screenshot state, but not per-keystroke geometry.

### Track Ownership

- Track A, AppKit editor host:
  - `PromptCue/UI/Components/CueTextEditor.swift`
  - new AppKit capture host files under `PromptCue/UI/Capture/`
- Track B, verification:
  - `PromptCueTests/CueTextEditorMetricsTests.swift`
  - `PromptCueTests/CaptureComposerLayoutTests.swift`
  - `scripts/qa_capture_input.sh`
- Master only, integration:
  - `PromptCue/UI/WindowControllers/CapturePanelController.swift`
  - `PromptCue/App/AppModel.swift`
  - `PromptCue/UI/Views/CaptureComposerView.swift`

### Quality Gates

1. Track gate:
   - build passes for touched targets
   - focused input tests pass
   - risk notes call out any remaining IME or accessibility gaps
2. Integration gate:
   - full `xcodebuild ... build`
   - focused input tests
   - capture QA harness produces screenshot and metrics logs
3. Runtime gate:
   - 1-line to 2-line wrap has no visible text flash
   - second line appears with persistent bottom breathing room
   - large paste grows to cap before scrolling

## Phase R7A: Input Contract Lock

### Goal

Define a stable model for the editor before more polish lands.

### Tasks

1. Introduce an explicit input state model:
   - `text`
   - `contentHeight`
   - `visibleHeight`
   - `isScrollable`
   - `isComposing`
2. Stop using a single-height geometry signal and keep `draftEditorMetrics` as the contract.
3. Freeze how capture panel height is derived from the editor host.

### Exit Criteria

- Editor state is explicit.
- Panel sizing no longer depends on ad hoc inferred values.

## QA Automation

Prompt Cue now has a local capture-input QA harness:

- [qa_capture_input.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/qa_capture_input.sh)

The harness is for regression checks on:

1. capture panel opens with seeded multiline content
2. large draft text stays inside the capture surface
3. screenshot capture artifacts are produced for visual review
4. editor metrics are logged for width/content/visible/scroll state

Recommended usage:

```bash
scripts/qa_capture_input.sh --app /tmp/PromptCueR7QA/Build/Products/Debug/Prompt\ Cue.app --draft-file /tmp/promptcue-r7-fixture.txt --wait 2.5
```

Expected output artifacts:

- `capture.png`
- `stdout.log`
- `stderr.log`
- `run.json`

Expected metrics shape for an overflowing multiline fixture:

- `contentHeight` > `visibleHeight`
- `visibleHeight` == `AppUIConstants.captureEditorMaxHeight`
- `scroll=true`

## Phase R7B: AppKit Editor Host Rewrite

### Goal

Replace the current per-change SwiftUI sizing loop with an AppKit-owned layout path.

### Tasks

1. Promote `CueEditorContainerView` into a more explicit host:
   - intrinsic content size
   - clamped visible height
   - scroll threshold behavior
   - stable width after scroller decision
2. Push height updates through one channel only.
3. Ensure selection and first responder state survive layout changes.
4. Move placeholder rendering into the editor host or a tightly coupled sibling host.

### Exit Criteria

- Wrap does not produce visible jump.
- Large paste never draws outside the shell.

## Phase R7C: Paste, IME, And Fast Input Hardening

### Goal

Make the editor robust under real input patterns.

### Tasks

1. Add paste-specific handling in the AppKit text view subclass.
2. After large paste, always scroll the insertion point into view once layout settles.
3. Add composition awareness so submit does not interfere with IME.
4. Enable undo and verify undo/redo, selection retention, and newline behavior.
5. Add explicit fast-input smoke coverage.

### Exit Criteria

- Input behavior is stable under fast typing and paste.
- Composition and newline flows are not accidental.

## Phase R7D: QA Harness And Regression Coverage

### Goal

Stop relying on visual guesswork for editor behavior.

### Tasks

1. Add a QA env hook that opens the capture panel with seeded text payloads.
2. Add harness scenarios for:
   - one-line typing
   - wrap at second line
   - large paste
   - paste over height cap
   - paste that triggers scroller appearance
   - screenshot slot visible while typing
3. Add automated checks for:
   - no overflow beyond shell bounds
   - stable top anchor
   - no editor height regression when placeholder disappears
   - stable width after scroller toggle
   - caret remains visible after large paste

### Exit Criteria

- The known broken cases are reproducible on demand.
- Fixes are validated against saved scenarios.

## Immediate Priorities

The next implementation slice should be:

1. `R7A` contract lock
2. `R7B` AppKit editor host rewrite
3. scroller-threshold width stabilization
4. `R7D` QA harness for paste and wrap
5. `R7C` fast-input, IME, and undo hardening

## What Is Wrong Right Now

In one sentence:

The current capture input is still architected like a SwiftUI-sized wrapper around an AppKit editor, when it needs to be an AppKit-owned text system with a SwiftUI shell.

That is why:

- wrap jitter still leaks through
- paste overflow still exists
- edge cases feel underdesigned

## Local Automation

Use `scripts/qa_capture_input.sh` to run a lightweight local QA pass for the capture input shell.

The harness does not change app behavior by itself. It launches the app with the planned QA env hooks so the runtime can opt into deterministic capture-mode setup when those hooks exist:

- `PROMPTCUE_OPEN_CAPTURE_ON_START=1`
- `PROMPTCUE_QA_DRAFT_TEXT_FILE=/path/to/draft.txt`
- `PROMPTCUE_LOG_EDITOR_METRICS=1`

The script will:

1. locate a local Debug build of `Prompt Cue.app` unless `--app` is provided
2. create a timestamped output folder under `/tmp/promptcue-qa/capture-input/`
3. create a sample multiline draft file unless `--draft-file` is provided
4. launch Prompt Cue with stdout and stderr redirected into that run folder
5. wait for the requested settle time
6. capture a full-screen screenshot
7. print a concise summary with paths to the screenshot, logs, and metadata

Example:

```bash
scripts/qa_capture_input.sh --wait 3.0
```

Useful options:

- `--app /path/to/Prompt Cue.app`
- `--draft-file /path/to/draft.txt`
- `--out-dir /tmp/promptcue-qa/manual-run`
- `--keep-running`

This harness is intended to support the upcoming input rewrite, especially for:

- wrap and height-clamp regressions
- large-paste visual overflow checks
- screenshot-slot coexistence checks
- editor metric logging during manual QA
