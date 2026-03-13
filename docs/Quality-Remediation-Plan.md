# Backtick Quality Remediation Plan

## Purpose

This document turns the latest quality audit into an execution plan.

The goal is not generic cleanup. The goal is to close the specific gaps that currently block Backtick from feeling release-ready as an AI coding scratchpad / thought staging tool:

- unreachable MVP behavior
- fragile screenshot attachment ownership
- incomplete screenshot privacy model
- non-deterministic clipboard export
- design-system drift and reuse gaps
- weak automated coverage outside `PromptCueCore`

## Audit Baseline

The current audit found these primary gaps:

1. Staged grouped export exists in model code, but the shipped stack interaction still depends on explicit mode entry and single-click auto-close.
2. Screenshot attachments are stored as external file paths instead of app-owned assets.
3. Screenshot folder access is still implicit instead of user-approved and bookmark-backed.
4. Clipboard export of image + text is not reliable across target apps.
5. Persistence failure is not surfaced clearly enough.
6. The design-system document, token layer, and production surfaces have drifted apart.
7. Automated coverage is concentrated in `PromptCueCore`; app-level critical flows are still manual.

## Remediation Principles

- Fix contract and ownership issues before polishing surface behavior.
- Move pure logic into `PromptCueCore` early when it reduces duplication or improves testability.
- Keep release-sensitive changes master-owned unless a track is explicitly opened.
- Prefer one finished vertical slice over half-finished parallel spikes.
- Do not treat design-system cleanup as cosmetic work only. It is part of stability because it controls drift.
- Reject note-app drift:
  - Capture = frictionless dump
  - Stack = execution queue
  - AI compression happens in Stack, not in Capture

## Parallel Execution Model

This plan assumes `master-managed multi-agent preferred, but optional`.

Parallel work starts only after shared contracts are frozen.

### Master-Owned Files

- `docs/Quality-Remediation-Plan.md`
- `docs/Implementation-Plan.md`
- `docs/Master-Board.md`
- `PromptCue/App/AppModel.swift`
- `PromptCue/App/AppCoordinator.swift`
- `PromptCue/App/PromptCueApp.swift`
- `PromptCue/App/AppDelegate.swift`
- shared contract files in `Sources/PromptCueCore/**` while contract changes are active

### Track Ownership After Contract Lock

- Track A, data ownership and attachment lifecycle:
  - `Sources/PromptCueCore/CaptureCard.swift`
  - `Sources/PromptCueCore/ScreenshotAttachment.swift`
  - `PromptCue/Services/CardStore.swift`
  - `PromptCue/Services/AttachmentStore.swift`
  - related tests
- Track B, stack export UX:
  - `PromptCue/Services/ClipboardFormatter.swift`
  - `PromptCue/UI/Views/CardStackView.swift`
  - `PromptCue/UI/Views/CaptureCardView.swift`
  - `PromptCue/UI/WindowControllers/StackPanelController.swift`
- Track C, screenshot access and settings:
  - `PromptCue/Services/ScreenshotDirectoryResolver.swift`
  - `PromptCue/Services/ScreenshotMonitor.swift`
  - `PromptCue/UI/Settings/PromptCueSettingsView.swift`
  - `PromptCue/UI/WindowControllers/SettingsWindowController.swift`
- Track D, design-system closure:
  - `docs/Design-System.md`
  - `docs/Design-System-Audit.md`
  - `PromptCue/UI/DesignSystem/**`
  - `PromptCue/UI/Components/GlassPanel.swift`
  - `PromptCue/UI/Components/SearchFieldSurface.swift`
  - `PromptCue/UI/Components/CardSurface.swift`

## Phase R0: Contract Lock

### Goal

Freeze the smallest shared contracts required for the later tracks.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Replace raw screenshot path assumptions with an app-owned attachment contract | Master | None | No | `CaptureCard` can distinguish between attachment identity and source path |
| Define screenshot folder access contract and bookmark storage interface | Master | None | No | settings and monitor code can depend on one access model |
| Define staged grouped-copy state contract and panel commit flow | Master | None | No | stack UI and controller can implement default grouped copy without reworking model shape |
| Record integration order and file ownership for remediation tracks | Master | None | No | worker tracks can start without file conflicts |

### Exit Criteria

- Contract names and storage shape are frozen.
- No worker track needs to guess at attachment identity or selection behavior.

## Phase R1: Data Integrity And Attachment Ownership

### Goal

Make screenshots durable, app-owned, and cleanup-safe.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Add attachment store under Application Support | Track A | Phase R0 | Yes | app can import and read owned assets |
| Change save flow to import screenshots on submit instead of storing external path | Track A + Master wiring | Attachment store contract | No | saved cards survive source-file movement |
| Add DB migration for attachment metadata | Track A | Attachment contract | Yes | existing data can be read and new data can be written |
| Delete imported assets on card delete and TTL cleanup | Track A + Master wiring | Attachment store | No | expired or deleted cards do not leave orphaned assets |
| Surface persistence failure state instead of silent no-op | Track A + Master wiring | None | Yes | persistence failures are observable in logs and state |

### Exit Criteria

- Cards do not depend on the original screenshot file remaining in place.
- Delete and TTL cleanup remove owned assets.
- Storage failure is visible and testable.

## Phase R2: Selection And Clipboard Export Closure

### Goal

Make the stack panel satisfy the actual grouped export contract for Backtick's execution queue.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Promote staged grouped copy to the default stack card-click behavior | Track B | Phase R0 | Yes | clicking a card updates the staged grouped payload without entering a separate mode |
| Keep clipboard synced to the staged grouped payload while the stack stays open | Track B | selection contract | Yes | click and unclick both update the live grouped clipboard without auto-closing the panel |
| Commit staged grouped copy into copied-state ordering on panel close | Track B | selection contract | No | cards move into the copied group only when the stack closes or the controller explicitly commits |
| Remove the explicit `Copy Multiple` affordance and legacy single-click auto-close path | Track B | selection contract | Yes | the default stack contract no longer depends on a separate multi-copy entry point |
| Redesign pasteboard writing so image + text export is deterministic for supported targets | Track B | attachment ownership from Phase R1 | No | paste behavior is stable in target apps under test |
| Add copy/export smoke coverage for staged click, deselect, and close-to-commit flows | Track B | above tasks | Yes | stack export no longer depends on ad hoc manual checking |

Backtick rule for Phase R2:

- add intelligence and compression affordances in Stack if needed
- do not push review/organization complexity back into Capture

### Default Multi-Copy UX Pivot

This worktree should treat the existing staged multi-copy path as the new default stack contract.

#### Locked Interaction Rules

1. Clicking an unselected stack card stages it for grouped copy and immediately refreshes the clipboard payload.
2. Clicking a staged card again removes it from the grouped payload and immediately refreshes the clipboard payload.
3. Card clicks no longer auto-close the stack panel.
4. Staged cards do not move into the copied grouping while the panel is still open.
5. Closing the stack panel commits the current staged set into copied-state ordering and re-sorts on the next presentation.
6. The explicit `Copy Multiple` control is removed rather than repurposed.

#### Non-Goals For This Slice

- redesign the copied-group visual treatment
- change stack ordering outside the staged-copy commit path
- rework pasteboard clearing semantics when the staged set becomes empty unless testing proves it is required

#### Execution Order

1. Freeze the default stack-click contract in `AppModel` and `StackPanelController`.
2. Remove `Copy Multiple` entry points and old auto-close assumptions from the stack views.
3. Keep live clipboard sync on every stage/unstage transition.
4. Commit copied-state grouping on panel close and verify reorder timing.
5. Add or update focused tests before broader target-app paste validation.

#### Verification

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- targeted stack tests for staged copy / deselect / close commit flow

### Exit Criteria

- Default grouped export is reachable without a separate mode switch.
- Card clicks keep the stack open while the clipboard stays live.
- Copied-group reordering happens on commit, not on the initial click.
- Image + text export behavior is documented and verified against target apps.

## Phase R3: Screenshot Access, Permissions, And Settings

### Goal

Replace implicit folder scanning with explicit, user-controlled screenshot access.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Add screenshot folder picker in Settings | Track C | Phase R0 | Yes | user can choose the watched folder |
| Persist security-scoped bookmark and rehydrate on launch | Track C | folder access contract | Yes | folder access survives relaunch |
| Update screenshot monitor to use approved access path instead of fallback scanning | Track C | bookmark support | No | monitor behavior matches privacy model |
| Add reconnect / invalid bookmark state in Settings | Track C | bookmark support | Yes | failure mode is visible and recoverable |
| Keep default onboarding behavior sensible for the common Desktop case | Track C | folder picker | Yes | first-run experience is low-friction without hidden scanning |

### Exit Criteria

- Screenshot behavior is explicit and user-controlled.
- Folder access survives relaunch.
- The implementation is compatible with later MAS hardening.

## Phase R4: Design-System Reconciliation

### Goal

Make the design system real enough to constrain future work instead of merely documenting intent.

Boundary note:

- `docs/Design-System-Architecture-Proposal.md` is the current-main-aligned ownership map for this phase.
- `docs/Design-System-Execution-Plan.md` is the phased execution guide for this phase.
- R4 must not flatten runtime-owned AppKit behavior or Backtick-specific pattern surfaces into generic components just to reduce visible hardcoding.
- In the active strategy branch, DS1, DS2, and DS3 are complete, and DS4 has started with narrowly shared helpers only.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Reconcile `docs/Design-System.md` with `PrimitiveTokens.swift` | Track D | None | Yes | documented scale matches shipped scale |
| Preserve the explicit separation between foundations, semantics, runtime bridges, reusable components, and Backtick patterns | Track D + Master | None | No | future cleanup no longer re-couples stack backdrop, stack cards, and capture runtime behavior |
| Move stack backdrop and notification plate styling onto semantic tokens | Track D | None | Yes | production surfaces stop embedding raw visual math |
| Remove duplicated glass shell recipes where practical | Track D | semantic cleanup | Yes | shell behavior composes from shared components |
| Add AppKit bridge tokens for editor typography/color | Track D | None | Yes | `CueTextEditor` no longer relies on matching by convention |
| Refresh `Design-System-Audit.md` to match actual preview/gallery coverage | Track D | None | Yes | audit docs are trustworthy again |

### Exit Criteria

- Design doc and tokens do not contradict each other.
- Production surfaces consume reusable semantics instead of local one-off styling.

## Phase R5: Verification And Release Confidence

### Goal

Raise confidence in the real app surface, not just the core package.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Add app-level smoke checklist for capture, screenshot attach, stack export, and restart | Master | R1-R3 | Yes | critical flows are manually repeatable |
| Add focused app tests or harness coverage for app-owned attachment lifecycle | Master + Track A | R1 | Yes | regressions are catchable before release |
| Add coverage for selection/export flow | Master + Track B | R2 | Yes | grouped export remains safe under iteration |
| Add coverage for bookmark resolution and invalid-folder recovery | Master + Track C | R3 | Yes | permission flow is not purely manual |
| Re-run full build/test/validator gate after each merged track | Master | every phase | No | integration stays green |

### Exit Criteria

- Core flows have repeatable verification.
- Release readiness is based on observed behavior, not optimism.

## Phase R6: Stack Sync And Light-Mode Readability

### Goal

Remove the current mismatch between successful capture submission and what the stack panel actually shows, and make the light-mode stack legible enough that new cards are unmistakable.

### Current Diagnosis

1. Capture submission is now async for screenshot-backed drafts, but stack presentation can still happen before that async path fully settles.
2. The stack panel currently reloads store-backed data when it opens, which can race with the in-flight submit path and briefly present a stale snapshot.
3. In light mode, the stack backdrop and notification-card surfaces are too close in luminance, so a newly inserted active card can appear as if it is missing even when it exists.
4. The original `Enter` submit path queued work in a `Task`, which created a short gap where `Cmd + 2` could fire before capture submission was actually marked in-flight.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Add explicit capture-submission flush behavior before stack presentation | Track A + Master wiring | Existing screenshot submit flow | No | Stack never opens from a stale pre-save snapshot after `Enter` |
| Make `AppModel` the in-memory source of truth during normal app interactions | Track A + Master wiring | Flush behavior | No | Stack presentation no longer depends on store reload timing |
| Add regression tests for `submit -> immediate stack open` | Track A | Flush behavior | Yes | Async save races are automated |
| Rebuild light-mode stack veil so underlying content is not readable behind cards | Track B | Existing semantic tokens | Yes | Backdrop acts like a quiet veil instead of a transparent white sheet |
| Increase separation between light-mode stack cards and the panel backdrop | Track B | Veil update | Yes | New active cards are immediately visible in light mode |
| Re-run end-to-end smoke for `capture -> save -> open stack` in both appearance modes | Master | Track A and B | No | Sync and contrast issues are manually confirmed |

### Exit Criteria

- Saving a cue and immediately opening the stack shows the new card without delay or stale counts.
- Light-mode cards and collapsed copied stacks are clearly distinct from the background.
- The stack panel no longer depends on "try again" behavior to reflect the latest state.

## Phase R6A: System-Inherit Appearance And Theme Consistency

### Goal

Remove the app-level light/dark override path so Backtick always inherits the active macOS appearance, and make open capture/stack surfaces repaint cleanly when the system appearance changes.

### Product Decision

1. Backtick should feel seamlessly integrated with macOS instead of carrying a separate app-owned theme preference.
2. The user-facing `Appearance` control is low-value relative to the regression surface it creates.
3. The app should not claim "done" on theme work until live system-appearance switching has been simulated and verified on the real runtime surfaces.

### Current Diagnosis

1. The current `Appearance` feature still introduces a global AppKit override pipeline: `appearance.mode` -> `NSApp.appearance` -> per-window and per-panel fan-out.
2. That override path fights the normal inherited appearance path. AppKit shells tend to update from `effectiveAppearance`, while SwiftUI stack cards and thumbnails consume inherited `colorScheme`.
3. In the stack panel, the shell can repaint correctly while some idle cards keep stale dark rasters. This aligns with the prewarmed stack host plus the idle-card `.drawingGroup()` path.
4. Similar low-level residue risk exists in smaller surfaces that have already shown history of missed theme updates, including capture editor text presentation, suggested-target accessory text, and stack-card background surfaces.
5. Theme-token branching is not itself the main bug. The main bug class is split appearance ownership. The token system should remain unified and resolve appearance internally from the inherited system state only.

### Design Decision

1. Remove the user-facing theme override and all persistence for `appearance.mode`.
2. Backtick will always inherit the active macOS appearance.
3. Keep one semantic token family. Light/dark differences may still exist inside the token implementation, but they must resolve from inherited `effectiveAppearance` / `colorScheme`, not from a second app-owned on/off switch.
4. Keep appearance refresh ownership local to runtime hosts:
   - AppKit surfaces react to `viewDidChangeEffectiveAppearance`
   - SwiftUI surfaces consume inherited `colorScheme`
   - no global coordinator fan-out of `NSAppearance`
5. If residue remains after the override path is removed, treat prewarmed stack-host invalidation as the first fix target before reopening token tuning or broad render-path changes.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Remove the `Appearance` section from Settings and delete theme persistence / observer logic | Master | None | No | users can no longer force light or dark mode from Backtick |
| Remove `NSApp.appearance` and coordinator-driven per-window/panel appearance fan-out | Master | Settings removal | No | the app no longer owns a global appearance override pipeline |
| Rewire stack, capture, settings, and debug windows to rely on inherited system appearance only | Master | override removal | No | windows repaint from the system appearance without explicit app theme pushes |
| Add stack-host theme-flip handling for the prewarmed panel so idle cards do not keep stale rasters | Master | inherit-only runtime | No | shell, header, idle cards, and hover cards all match after a live system theme flip |
| Audit capture editor text, placeholder, accessory text, and stack-card background surfaces for inherited-theme correctness | Master | inherit-only runtime | Yes | historically fragile small surfaces stay in sync with the active system appearance |
| Define a bounded simulation harness for live `light -> dark -> light` switching on already-open capture and stack surfaces | Master | inherit-only runtime | No | theme regressions are reproducible without ad hoc manual guessing |
| Re-run non-perf regression gates before every perf pass touching stack/capture appearance paths | Master | above tasks | No | theme fixes do not silently break capture text, stack rendering, or export behavior |
| Re-run stack perf verification after each accepted runtime invalidation change | Master | stack-host handling | No | theme correctness work does not destroy approved stack performance |

### Verification Gate

Do not call this phase complete until every item below is true:

1. Live simulation has been run against the real Debug app, not only static snapshots.
2. The following scenarios all pass on already-created surfaces:
   - open `Capture`, then flip system light/dark
   - open `Stack`, then flip system light/dark
   - keep the prewarmed stack panel path active, then flip system light/dark before and after presentation
3. Small but historically fragile surfaces are explicitly checked:
   - capture editor text color
   - capture placeholder and caret
   - suggested-target accessory text
   - stack card idle background
   - stack hover/emphasis state
4. Non-perf regression verification is green before any perf conclusion is accepted:
   - `swift test`
   - `xcodegen generate`
   - `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
   - targeted capture/stack rendering tests for touched surfaces
5. Perf guardrails are still acceptable after the final implementation:
   - `PromptCueTests/StackPanelVisualPerformanceTests/testStackVisualRenderBenchmark`
   - `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`

### Guardrails

1. Do not accept a theme fix that only looks correct after closing and reopening panels.
2. Do not accept a theme fix that regresses capture text readability or stack-card separability in either appearance.
3. Do not accept a theme fix that relies on broad always-on invalidation if the work can be scoped to actual theme-flip events.
4. Do not accept a performance regression just because a visual bug disappears; correctness and approved stack speed must hold together.
5. Do not announce the lane as complete until the simulation gate above has passed in full.

### Exit Criteria

- Backtick has no user-facing theme override and always inherits the system appearance.
- Open capture and stack surfaces repaint correctly on live system appearance changes.
- Idle stack cards no longer retain stale dark or light backgrounds after a theme flip.
- Capture editor text and smaller accessory surfaces remain synchronized with the active appearance.
- Final verification includes live simulation plus regression and perf guardrails, not optimism.

## Merge Order

1. Phase R0 contract lock
2. Track A, data integrity and attachment ownership
3. Track C, screenshot access and settings
4. Track B, selection and clipboard export
5. Track D, design-system reconciliation
6. Phase R5 verification pass
7. Phase R6 stack sync and light-mode readability
8. Phase R6A system-inherit appearance and theme consistency
9. Phase R7 capture input system hardening
10. Phase R8 AI Export Tail / Prompt Suffix
11. Phase R9 stack card overflow and hover expansion
12. Phase DP capture/stack visual polish under explicit review gates

## Immediate Next Slice

The current slice status is:

1. Phase R0 contract lock: completed
2. Phase R1 attachment ownership: integrated
3. Phase R3 screenshot access and settings: integrated
4. Phase R2 selection and grouped export: in progress
5. Phase R4 design-system reconciliation: in progress via the design-system strategy branch (`Phase DS1` and `Phase DS2` implemented, `Phase DS3` and early `Phase DS4` underway)
6. Phase R5 app-level verification: started, but still too light
7. Phase R6 stack sync and light-mode readability: in progress
8. Phase R6A system-inherit appearance and theme consistency: planned, master-owned

The next master-owned remediation lane after the current stack/export validation work is `Phase R6A`, because theme override removal and live-system inheritance are now the clearest path to eliminating the remaining light/dark residue bugs without reopening ad hoc token churn.

## Phase DP: Capture And Stack Visual Polish

### Goal

Finish the visible capture/stack polish work without reopening structural regressions or allowing ad hoc UI drift.

Reference:

- [Design-Polish-Execution-Plan.md](/Users/ilwonyoon/Documents/PromptCue/docs/Design-Polish-Execution-Plan.md)

### Why This Needs A Separate Phase

Backtick now has enough structural ownership to polish safely, but the remaining issues are visual and subjective enough that they require:

- explicit ownership boundaries
- screenshot-based review packets
- master-owned token changes

### Exit Criteria

- capture shell elevation is clear in both appearance modes
- stack cards are brighter and easier to scan without flattening the UI
- semantic tokens expose the needed light/dark polish roles
- every slice ships with before/after review artifacts

### Current Status

- `DP0`: complete in docs
- next bounded slices:
  - `DP1`: capture elevation pass
  - `DP2`: stack card brightness pass
- current state:
  - semantic token and runtime-shell extraction is in progress for `DP1`
  - stack-card brightness and copied-stack quieting are in progress for `DP2`
  - final light/dark review artifacts are still the gate

That means:

## Phase R7: Capture Input System Hardening

### Goal

Rebuild the capture input so it behaves like a production-quality AppKit text system instead of a best-effort SwiftUI wrapper.

### Current Diagnosis

1. The current editor sizing path is two-phase: AppKit content grows first, then SwiftUI shell height catches up.
2. That architecture is especially fragile under multiline wrap and large paste payloads.
3. The current editor bridge still performs too much work through SwiftUI update cycles for a high-frequency text surface.
4. The app has no dedicated paste burst strategy, IME/composition contract, or deterministic QA harness for input stress cases.
5. Current code review confirms split height ownership across `CueEditorContainerView -> CaptureComposerView -> AppModel -> CapturePanelController`.
6. Bottom padding is still encoded as part of measured editor height instead of being owned as shell chrome.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Lock an explicit editor state contract (`contentHeight`, `visibleHeight`, `isScrollable`, composition state) | Master | None | No | input geometry is no longer implicit |
| Promote the AppKit editor host to own clamped sizing and scroll threshold behavior | Track A + Master wiring | editor state contract | No | wrap and paste do not leak outside the shell |
| Add paste-specific handling and composition-safe submit behavior | Track A | editor host rewrite | Yes | paste bursts and IME do not break the editor |
| Move placeholder ownership out of loose SwiftUI overlay logic | Track B | editor host rewrite | Yes | placeholder no longer fights real text state |
| Add QA harness scenarios for wrap, large paste, and screenshot-slot interaction | Track B | editor host rewrite | Yes | known regressions are reproducible on demand |
| Replace live SwiftUI capture composition with an AppKit-owned capture host | Master + Track A | editor host rewrite | No | runtime capture panel no longer depends on per-keystroke SwiftUI frame updates |

### Current Status

- Explicit editor metrics contract is now live via `CaptureEditorMetrics`.
- The capture editor now reserves scroller width in measurement and clips to the surface.
- Initial presentation now precomputes draft metrics before panel display.
- A deterministic local QA harness now exists in `scripts/qa_capture_input.sh`.
- Automated capture QA has been run against a multiline fixture and produced:
  - screenshot artifact: `/tmp/promptcue-qa/manual-r7/capture.png`
  - metrics log showing `width=336.0 content=1232.0 visible=176.0 scroll=true`
- Remaining follow-up is no longer “minor polish.” The blocker is architectural: sizing authority still spans AppKit, SwiftUI, the model, and the panel.
- R7B is now authorized: the live capture panel will be rewritten around an AppKit-owned host while preserving the current visual shell.

### Exit Criteria

- Wrap does not visibly jump.
- Large paste never renders outside the capture surface.
- Fast input, paste, and composition behavior are explicitly covered.

1. QA the new tracked capture-submission path in real `Enter -> Cmd + 2` flow
2. Fine-tune any remaining light-mode veil and shadow issues without reopening the sync path
3. Keep app-level tests around `capture -> submit -> immediate stack open` green
4. Verify grouped export against target apps that consume image + text differently
5. Reconcile design-system docs and semantic usage before more surface polish

## Phase R8: AI Export Tail / Prompt Suffix

### Goal

Add a user-controlled export suffix that can be appended to copied/exported payloads without modifying stored cue content.

### Product Rules

1. Terminology in product, docs, and code review should prefer `AI Export Tail` or `Prompt Suffix`.
2. The suffix is export-time only. It must not mutate saved cards, stack previews, or persistence.
3. The suffix is optional and user-controlled.
4. The suffix text supports multiline input.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Add Settings state for `AI Export Tail enabled` and multiline `Prompt Suffix` text | Master + settings track | Existing Settings surface | Yes | toggle and text are persisted and reload correctly |
| Define export formatter contract for suffix append behavior | Master | None | No | formatter has one explicit append rule for enabled/disabled/empty states |
| Append suffix only in export/clipboard composition path | Track B + Master wiring | formatter contract | No | copied payload includes suffix only at export time |
| Keep stack rendering and stored cards suffix-free | Track B | formatter integration | Yes | UI and persistence remain unchanged |
| Add tests for enabled, disabled, empty, and multiline suffix behavior | Master + Track B | formatter integration | Yes | regression coverage locks the export-only rule |
| Add an app-level smoke check for `save -> copy -> suffix appended` | Master | above tasks | No | behavior is verified outside unit tests |

### Integration Order

1. freeze names and settings storage shape
2. wire formatter and clipboard append behavior
3. wire Settings toggle and multiline text editor
4. add focused tests and smoke validation

### Exit Criteria

- Users can enable or disable `AI Export Tail` in Settings.
- Users can enter multiline `Prompt Suffix` text.
- Exported payloads append the suffix only when enabled and non-empty.
- Saved cards, card counts, previews, and persistence remain unchanged.

## Phase R9: Stack Card Overflow And Hover Expansion

### Goal

Keep Stack scannable when a saved cue is extremely long, while still letting users read full content on demand.

### Product Rules

1. A single long card must not dominate the queue by default.
2. Overflow should be legible, not hidden silently.
3. Reveal behavior should feel temporary and lightweight.
4. The same overflow system should apply to active cards and copied-stack summaries.
5. Stack should still read as an execution queue, not a long-form reader.
6. Initial design target:
   - active text-only cards expose roughly `3-4` lines at rest
   - hover/focus reveal exposes roughly `6-8` lines before any deeper interaction

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Define max resting card height and overflow metrics | Master + design-system track | Existing stack card styles | No | one capped-height rule exists for normal stack cards and copied summaries |
| Add overflow affordance that communicates hidden remaining content | Track B | metrics contract | Yes | long cards clearly indicate more content exists |
| Implement hover or focus reveal for active stack cards | Track B + Master wiring | metrics contract | No | users can read long text without permanent layout blowout |
| Make collapsed copied-stack summaries obey the same cap and remain stable | Track B | metrics contract | Yes | copied-stack summary never breaks when the first copied card is very long |
| Add automated QA fixtures for long text, mixed image+text, and copied-stack long-card cases | Master + Track B | overflow implementation | Yes | long-card behavior is reproducible and regression-tested |

### Integration Order

1. freeze overflow metrics and interaction behavior
2. update active card rendering
3. update copied-stack summary rendering
4. add automated fixtures and verification

### Exit Criteria

- Very long cards do not create unbounded stack rows in the resting state.
- Users can tell that more text exists.
- Hover or focus reveal reads smoothly and does not destabilize the stack.
- Copied-stack collapsed summaries remain visually stable regardless of source card length.
