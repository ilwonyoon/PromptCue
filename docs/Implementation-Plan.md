# Backtick Implementation Plan

## Current State

- Product identity is `Backtick`.
- Current repo name, app target, and core module remain `PromptCue` / `PromptCueCore` for now.
- Planning decisions should be judged against Backtick as an AI coding scratchpad / thought staging tool, not a note app.
- Core interaction model:
  - Capture = frictionless dump
  - Stack = execution queue
  - AI compression happens in Stack

- Architecture direction is fixed: `native macOS utility app`, not `App Extension`.
- UI stack is fixed: `SwiftUI + AppKit hybrid`.
- The workspace already contains an early native scaffold:
  - `project.yml`
  - `PromptCue/App/*`
  - `PromptCue/Domain/*`
  - `PromptCue/Services/*`
  - `Sources/PromptCueCore/*`
- The app target is now wired to `PromptCueCore` for shared pure logic.
- Current overall status: `Phase 0 complete`, `Phase 1 in progress`, `Phase 2 and Phase 3 started`.
- A quality audit has now been completed and a remediation lane is active in `docs/Quality-Remediation-Plan.md`.
- A current-main-aligned design-system boundary proposal now exists in `docs/Design-System-Architecture-Proposal.md`.
- A design-system execution document now exists in `docs/Design-System-Execution-Plan.md`.
- A bounded capture/stack design-polish plan now exists in `docs/Design-Polish-Execution-Plan.md`.
- `Phase DS1`, `Phase DS2`, and `Phase DS3` are now implemented in the design-system strategy branch, and `Phase DS4` has started where reuse is already proven.
- a dedicated performance remediation lane now exists in `docs/Performance-Remediation-Plan.md`

## Phase Summary

| Phase | Goal | Status | Notes |
| --- | --- | --- | --- |
| Phase 0 | Research and lock technical direction | Completed | Native macOS direction decided |
| Phase 1 | Foundation and shared contracts | In progress | Early scaffold exists, shared contracts need tightening |
| Phase 2 | Core capture flow | In progress | Services, panels, and capture UI skeleton are implemented |
| Phase 3 | Stack and export UX | In progress | Card stack and copy interactions are implemented, smoke testing pending |
| Phase 4 | Platform and operations hardening | In progress | Settings and screenshot folder access are now implemented |
| Phase 5 | Polish, validation, and release prep | Pending | Final integration phase |
| Phase R | Audit remediation and quality closure | In progress | Resolves MVP gaps, privacy model drift, and design-system drift |
| Phase DS1 | Design-system boundary freeze | Completed in strategy branch | Ownership boundaries are now explicit in docs and code comments |
| Phase DS2 | Runtime/value ownership split | Completed in strategy branch | Grouped contracts now back runtime callers; `AppUIConstants` is only a compatibility facade |
| Phase DS3 | Pattern recipe centralization | Completed in strategy branch | Capture shell chrome, stack card chrome, copied-stack recipe, and stack backdrop recipe now live in owner files |
| Phase DS4 | Reusable surface rationalization | In progress in strategy branch | Shared notification-card chrome and top-edge highlight helpers are now extracted where reuse is proven; broader reusable-surface cleanup is still pending |
| Phase DP | Capture and stack design polish | In progress | `DP0` review lock is complete; `DP1` capture elevation and `DP2` stack brightness are now in implementation with review still pending |

## Current Hot Slice

The immediate implementation slice is:

- `safe-main merge candidate: preserve the currently approved functionality while merging performance core, approved capture/stack visuals, and long-note overflow behavior`
- `Phase R7: capture input system hardening`
- queued next: `Phase R8: AI Export Tail / Prompt Suffix`
- queued after that: `Phase R9: stack card overflow and click expansion`
- in parallel planning/visual lane: `Phase DP0 -> DP4` from `docs/Design-Polish-Execution-Plan.md`

This slice exists because the performance lane is complete, but the merge target is now constrained by preserving current `main` behavior and current UI style while still landing the large service/state/runtime wins.

That means current work is prioritized in this order:

1. keep the merge-safe scope on `feat/performance-main-safe` green with `scripts/verify_main_merge_safety.sh --profile safe-main`
2. finish `Phase R7` without reintroducing layout churn or capture latency regressions
3. add `AI Export Tail / Prompt Suffix` as an export-time-only setting and formatter slice
4. then land `Phase R9` overflow/click expansion intentionally, not piggybacked on performance work
5. then return to grouped export validation and broader release verification

All work in this slice should preserve the product model:

- Capture stays optimized for fast dumping of raw thoughts
- Stack owns ordering, grouping, export, and AI-facing compression
- proposals that turn Capture into a note surface should be rejected

Progress on this slice:

- `Phase R7A` contract lock is implemented through `CaptureEditorMetrics`
- initial draft presentation now precomputes editor metrics before the panel is shown
- reserved-width remeasurement is in place at the scroll threshold
- automated capture QA now runs through `scripts/qa_capture_input.sh` and has produced screenshot + metrics artifacts
- current diagnosis confirms the next R7 step must move height ownership back into the AppKit editor host; further padding-only tweaks are not sufficient
- `Phase R7B` is now the active implementation lane: replace the live SwiftUI capture composition with an AppKit-owned host and keep geometry out of `AppModel`
- `Phase P1` is accepted with quantified overflow-cache wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P2` is accepted with quantified incremental-write wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P3A-P3B` is accepted with quantified capture-open decoupling wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P3C-P3D` is accepted with quantified preview-cache and resize-churn wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P4A` is accepted with quantified copied-card sync batching wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P4B` is accepted with quantified remote sync apply dispatch and queued-completion wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P4C` is accepted with quantified startup-deferral wins recorded in `docs/Performance-Remediation-Plan.md`
- `Phase P5` remains recorded in `docs/Performance-Remediation-Plan.md` as the quantified visual-retune experiment, but the merge-safe landing candidate now carries the approved capture/stack visuals directly and does not gate on the historical stack visual benchmark file
- the performance remediation lane is now complete
- `feat/performance-main-safe` now exists as a clean candidate branch in `../PromptCue-main-safe` and passes `scripts/verify_main_merge_safety.sh --profile safe-main`
- the final merge-safe screenshot risk is closed: `beginCaptureSession()` restores the recent-screenshot slot immediately from the synchronous signal probe, and `submitCapture()` now waits for async readable promotion without rearming repeated scans on every poll
- `safe-main` was rerun after the hidden stack-panel prewarm landed and remains green, with live trace reruns at `21.35 ms`, `18.74 ms`, and `22.22 ms`

Working-with-apps port rule:

- current `main` capture and stack visuals are the baseline
- older PRs are ported as behavior slices, not merged as architectural truth
- stage the feature in this order:
  1. hidden metadata and persistence contract
  2. current-runtime-compatible chooser state and keyboard contract
  3. current-style capture accessory and stack reassignment UI
- reject any port step that reintroduces:
  - older capture controller ownership
  - full-table persistence writes
  - visual deviations from the approved capture/stack baseline

## Active Remediation Lane

The current highest-priority work is tracked in:

- `docs/Quality-Remediation-Plan.md`
- `docs/Design-System-Architecture-Proposal.md` for design-system ownership boundaries
- `docs/Design-System-Execution-Plan.md` for phased design-system execution

That remediation lane is now authoritative for:

- multi-card selection and grouped export closure
- screenshot attachment ownership and cleanup
- explicit screenshot folder access and bookmark persistence
- clipboard reliability for image + text export
- `AI Export Tail / Prompt Suffix` settings, export-only append behavior, and test coverage
- design-system reconciliation and reuse cleanup
- app-level verification expansion

Design-system rule for all future polish work:

- generic tokenization must not collapse runtime-owned AppKit behavior or Backtick-specific pattern surfaces
- visual polish must follow the review gates in `docs/Design-Polish-Execution-Plan.md`, not ad hoc local tuning
- `Phase DP0` is now complete in docs; the first code slice should be `DP1` capture elevation with master-owned token changes

## Queued Next Slice

The next planned remediation slice after `Phase R7` is:

- `Phase R8: AI Export Tail / Prompt Suffix`

This slice exists to add a user-controlled export suffix without polluting stored cue content or capture UI.

Backtick rule for this slice:

- the suffix is export-time compression/output polish
- it must not turn Capture into a templated note surface

Planned scope:

1. add Settings controls for:
   - enable/disable toggle
   - multiline suffix text
2. append the suffix only at export time
3. keep stored cards unchanged in persistence and stack rendering
4. add formatter and app-level regression coverage before UI polish

Planned integration order:

1. freeze the export-tail contract and settings storage shape
2. update export formatter / clipboard composition path
3. wire Settings UI and state
4. add regression tests for enabled, disabled, empty, and multiline behavior

After `Phase R8`, the next planned slice is:

- `Phase R9: stack card overflow and click expansion`

This slice exists because very long cue content currently turns Stack into a layout outlier instead of a stable execution queue.

Backtick rule for this slice:

- Stack should reveal that a card is long without letting one card dominate the queue by default
- expansion should feel temporary and lightweight, not like opening a document

Planned scope:

1. define one default max resting card height for active and copied-stack cards
   - current target: resting preview cap should be more generous and may extend to `2x` the capture max height when needed
2. define one overflow affordance that communicates remaining hidden text
   - explicit affordance: `+N lines`
   - hover highlights affordance only
3. add click-to-expand behavior that reveals more text without destabilizing surrounding layout
   - clicking `+N lines` should reveal the full card text
   - cards may not introduce an inner text scroller
4. keep copied-stack collapsed summaries visually stable even when the first card is very long
   - collapsed copied summaries do not expand inline
5. add QA fixtures for short, medium, very long, and screenshot-plus-text cards

Planned integration order:

1. freeze card overflow metrics and interaction rules
2. update active stack cards
3. update collapsed copied-stack summaries
4. add automated visual/behavior verification for long-card fixtures

## MCP Reset

The MCP direction is reset around one rule:

- MCP exists to read and write the `Stack` database directly

Anything outside that path is out of scope for the current lane:

- no `Execution Map`
- no `Work Board`
- no `Create Item`
- no `WorkItem` or `WorkItemSource` layer between Stack notes and MCP tools

Keep:

- `CaptureCard`
- `CardStore`
- `CopyEvent`
- `copy_events` persistence

Remove:

- `ExecutionMap*` UI and window wiring
- `WorkItem*` models and storage
- startup or menu behavior tied to MCP board experiments
- stack affordances that manufacture derived items instead of operating on Stack notes

Why:

- the actual product need is `Claude Code CLI` and `Codex CLI` reading and writing Stack data through MCP
- an AI execution step should update copied state on the source Stack notes directly
- intermediate board and work-item layers add complexity without helping the MCP bridge

Execution semantics:

- MCP read:
  expose active and copied Stack notes directly from Stack storage
- MCP write:
  create, update, and delete Stack notes directly
- MCP execute:
  when an agent actually executes a note, mark the source note as copied and record a `CopyEvent`

Implementation rules for the next MCP lane:

- treat Stack as the source of truth
- do not reintroduce derived task or board models unless a concrete MCP workflow requires them
- copied state must reflect actual execution, not speculative planning or grouping
- keep MCP-specific naming internal until the stdio bridge and tool surface are real

Next rollout:

1. `MCP2` Stack read bridge
   - list Stack notes
   - fetch note detail and copied state

2. `MCP3` Stack write bridge
   - create notes
   - update note text or metadata
   - delete notes

3. `MCP4` execution action
   - mark a note executed by updating `lastCopiedAt`
   - persist a matching `CopyEvent` with MCP actor metadata

4. `MCP5` stdio tool surface
   - expose read/write/execute actions through an MCP server transport
   - keep tool names aligned with Stack note semantics

5. `MCP6` connector settings surface
   - add a Settings section for MCP connectors
   - show which clients are currently configured to use Backtick MCP
   - show the executable / command path that clients should run
   - provide client-specific config snippets for `Claude Code` and `Codex`
   - support both repository-checkout workflows and a future bundled helper path

6. `MCP7` guided setup and validation
   - help the user attach Backtick MCP to external clients without manual guesswork
   - validate that a configured client can actually reach the MCP server
   - show last-known connection or handshake status in product language

7. `MCP8` bundled helper packaging
   - ship a launchable `BacktickMCP` helper with release builds
   - keep source-checkout fallback for local development
   - make connector setup usable outside a Swift package checkout

Current landed slices:

- `MCP2` Stack read bridge is on `main`
  - `PromptCue/Services/StackReadService.swift`
  - `PromptCueTests/StackReadServiceTests.swift`
  - lists all, active, and copied notes
  - returns note detail plus `CopyEvent` history
- `MCP3` Stack write bridge is on `main`
  - `PromptCue/Services/StackWriteService.swift`
  - `PromptCueTests/StackWriteServiceTests.swift`
  - creates, updates, and deletes Stack notes directly
  - cleans up managed screenshot attachments on delete
- `MCP4` execution action is on `main`
   - `PromptCue/Services/StackExecutionService.swift`
   - `PromptCueTests/StackExecutionServiceTests.swift`
   - marks executed notes copied in Stack storage
   - persists matching `CopyEvent` rows in the same transaction
- `MCP5` stdio tool surface is on `main`
   - `Package.swift`
   - `Package.resolved`
   - `Sources/BacktickMCP/main.swift`
   - `Sources/BacktickMCPServer/BacktickMCPApp.swift`
   - `Sources/BacktickMCPServer/BacktickMCPServerSession.swift`
   - `Tests/BacktickMCPServerTests/BacktickMCPServerTests.swift`
   - exposes `list_notes`, `get_note`, `create_note`, `update_note`, `delete_note`, and `mark_notes_executed`
   - routes all note operations through the landed Stack services against the shared DB
- `MCP6` connector settings surface is on `main`
   - `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`
   - `PromptCue/UI/Settings/PromptCueSettingsView.swift`
   - `PromptCue/UI/WindowControllers/SettingsWindowController.swift`
   - `PromptCueTests/MCPConnectorSettingsModelTests.swift`
   - shows `Claude Code` and `Codex` connector status, launch command, add command, and config snippets
   - supports repository-checkout launch commands while bundled helper packaging is still pending
- `MCP7` guided setup and validation is on `main`
   - `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`
   - `PromptCue/UI/Settings/PromptCueSettingsView.swift`
   - `PromptCueTests/MCPConnectorSettingsModelTests.swift`
   - explains what Backtick MCP does, shows a concrete setup flow, and runs a local server self-test from Settings
   - promotes configured clients to `Connected` after a successful local launch/tool-surface validation
   - includes a Claude-specific automation example for `--permission-mode dontAsk` with explicit `--allowedTools`

Verification gates run for landed MCP slices:

- `xcodegen generate`
- `swift test`
- `swift test --filter BacktickMCPServerTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/MCPConnectorSettingsModelTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackReadServiceTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackWriteServiceTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackExecutionServiceTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `swift run BacktickMCP --database-path <temp-db> --attachments-path <temp-attachments>`

Current immediate next step:

1. `MCP8` bundled helper packaging
   - package `BacktickMCP` with app builds so Settings can show a ready command outside local source checkouts
   - copy the helper into `Prompt Cue.app/Contents/Helpers/BacktickMCP` during app builds
   - prefer the bundled helper in Settings connector setup when it exists
   - keep repository-root detection as the development fallback
   - make connector setup work for direct-download users without requiring a Swift toolchain
   - preserve the repository-checkout launch path as the developer fallback while release packaging lands

2. release-path connector validation
   - rerun the Settings server test against a packaged helper, not just a source checkout
   - verify `Claude Code` and `Codex` setup still works when the user has no local Swift toolchain
   - keep treating `tool permission denied` as client setup friction instead of a Backtick MCP launch failure

Why this rollout is required:

- transport alone is not enough user value if the user does not know how to attach `Claude Code` or `Codex`
- MCP is a connector feature from the user point of view, not just a local executable
- sensitive integration behavior should be visible in Settings rather than hidden in docs or shell commands
- connector setup is incomplete for release users until Backtick ships a helper binary or equivalent launchable surface
- successful interactive connection is not enough if common automation modes still fail on client-side tool permissions

Rules after `MCP5`:
- no new board, work-item, or execution-map layer
- no dependency on current UI selection state
- keep Stack as the only source of truth
- reuse the landed services instead of duplicating note logic in the transport layer
- `main` already contains `StackReadService`, `StackWriteService`, and `StackExecutionService`

## Phase 0: Research And Decisions

### Goal

Confirm the right product shape, operating constraints, and implementation stack.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Confirm app form factor: utility app vs App Extension | Architecture lead | None | No | Decision captured in PRD and plan | Completed |
| Confirm UI shell: SwiftUI + AppKit hybrid | Architecture lead | None | No | Core windowing choice locked | Completed |
| Confirm distribution strategy: Gumroad-backed direct download first, MAS later optional | Product + platform lead | None | Yes | Distribution path documented with sandbox implications | Completed |
| Capture Alfred/Raycast interaction patterns to copy or avoid | UX lead | None | Yes | UX principles list approved | Completed |
| Identify key platform risks: hotkeys, panels, screenshot access, login item | Platform lead | None | Yes | Risk register created | Completed |

### Exit Criteria

- Product shape is stable enough to avoid rework.
- Native macOS stack is accepted as the long-term baseline.
- Constraints around screenshot permissions and distribution are documented.

## Phase 1: Foundation And Shared Contracts

### Goal

Create the stable technical foundation that other tracks can build on without file conflicts.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Normalize project structure around `project.yml` and app target layout | Foundation lead | Phase 0 | No | Buildable app project structure is agreed | In progress |
| Freeze shared contracts: card model, draft model, panel constants, service protocols | Foundation lead | Phase 0 | No | Shared types stop changing daily | In progress |
| Add `GRDB` and define SQLite-backed storage for cards and attachments | Data lead | Shared contracts | Yes | Persistence interface is stable and migration-ready | In progress |
| Define screenshot source abstraction and permission model | Platform lead | Shared contracts | Yes | Folder selection and watcher rules are agreed | In progress |
| Define global shortcut abstraction and action routing | Platform lead | Shared contracts | Yes | Capture and stack actions are centrally routed | Pending |
| Add baseline test targets and verification commands | Foundation lead | Project structure | Yes | Unit test target exists and runs | Completed |

### Parallel Tracks

- Track A: Contracts and domain models
- Track B: Platform services contracts
- Track C: Test harness and build validation

### Exit Criteria

- App compiles with placeholder implementations.
- Shared types and ownership boundaries are frozen.
- Worker tracks can proceed without touching the same files.

## Phase 2: Core Capture Flow

### Goal

Ship the fastest path from hotkey to saved card.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Implement global shortcut registration for quick capture and stack toggle | Platform lead | Phase 1 contracts | Yes | Hotkeys fire reliably from any app | In progress |
| Implement capture panel controller and panel positioning | Windowing lead | Phase 1 contracts | Yes | Panel opens in the intended edge position and accepts focus | In progress |
| Implement capture composer UI with `Enter` submit and `Esc` cancel | UI lead | Capture panel controller | Yes | User can dump a thought in under 2 seconds | In progress |
| Implement card persistence with TTL cleanup | Data lead | Storage abstraction | Yes | Cards survive relaunch and expired cards are removed | In progress |
| Implement screenshot lookup/attachment for recent screenshots | Platform lead | Screenshot abstraction | Yes | Recent screenshot attaches automatically when eligible | In progress |
| Wire model actions: create card, clear draft, reset screenshot state | App state lead | Persistence and screenshot support | No | Capture flow is end-to-end functional | In progress |

### Parallel Tracks

- Track A: Hotkeys + panel shell
- Track B: Persistence + TTL + screenshot attachment
- Track C: Capture UI and view model binding

### Exit Criteria

- The configured capture shortcut opens the capture panel. The default is `Cmd + \``.
- Typing and pressing `Enter` creates a card.
- Screenshot auto-attach works for the agreed MVP rule.
- State persists locally across app restarts.

## Phase 3: Stack And Export UX

### Goal

Make stored thoughts easy to review, compress, and export from the execution queue without slowing the workflow.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Implement right-side stack panel window behavior | Windowing lead | Phase 2 panel shell | Yes | Stack panel opens/closes cleanly and preserves size/placement rules | In progress |
| Implement newest-first card stack UI | UI lead | Phase 2 persistence | Yes | Cards render in correct order with timestamps | In progress |
| Implement screenshot thumbnail rendering | UI lead | Phase 2 screenshot attachment | Yes | Attached screenshots render safely and do not block the UI | In progress |
| Implement default staged grouped copy-on-click behavior | UX lead | Card stack UI | Yes | Clicking a card stages or unstages it and refreshes the grouped clipboard payload immediately | In progress |
| Commit staged copy state on panel close and remove explicit `Copy Multiple` entry | UX lead | Card stack UI | Yes | Closing the stack promotes staged cards into copied ordering and the old mode-switch affordance is gone | Planned |
| Implement delete/expiry refresh behavior in the stack | App state lead | Persistence | Yes | Stack reflects deletions and TTL cleanup without stale state | In progress |

Backtick judgment rule for this phase:

- Stack can add grouping, selection, and AI compression affordances
- Capture should not accumulate note-taking features that belong in Stack

### Parallel Tracks

- Track A: Window behavior
- Track B: Card list UI and image rendering
- Track C: Clipboard/export interactions

### Exit Criteria

- The configured stack shortcut opens the review/export surface. The default is `Cmd + 2`.
- Card clicks update grouped copy without auto-closing the stack.
- Closing the stack commits staged cards into copied ordering.
- The stack remains visually stable under frequent updates.

### `PR #25` Landed State

`PR #25` (`feat/default-multi-copy`) is on `main` and is now the stack/export baseline that `MCP5` should inherit.

Landed scope:

- `PromptCue/App/AppModel.swift`
- `PromptCue/Services/ClipboardFormatter.swift`
- `PromptCue/UI/Views/CaptureCardView.swift`
- `PromptCue/UI/Views/CardStackView.swift`
- `PromptCue/UI/Views/InteractiveDetectedTextView.swift`
- `PromptCue/UI/WindowControllers/StackPanelController.swift`
- `Sources/PromptCueCore/ContentDisplayFormatter.swift`
- `Sources/PromptCueCore/ExportFormatter.swift`
- `PromptCueTests/PromptExportTailSettingsTests.swift`
- `PromptCueTests/StackMultiCopyTests.swift`
- `Tests/PromptCueCoreTests/ContentDisplayFormatterTests.swift`
- `Tests/PromptCueCoreTests/PromptCueCoreTests.swift`
- `docs/Engineering-Preflight.md`
- `docs/Quality-Remediation-Plan.md`
- regenerated `PromptCue.xcodeproj/project.pbxproj`

Verification that ran for `PR #25`:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackMultiCopyTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/PromptExportTailSettingsTests -only-testing:PromptCueTests/StackMultiCopyTests`

Required smoke checks after the gate:

- clicking a stack card stages it without closing the panel
- clicking the same staged card again removes it from the grouped clipboard payload
- closing the stack commits the staged set into copied ordering
- standalone raw literals such as links, paths, emails, secrets, and localhost URLs copy without the export tail suffix

Current rules inherited by `MCP5`:

- no changes to `StackReadService`, `StackWriteService`, or `StackExecutionService`
- no new MCP transport or tool wiring
- do not reintroduce `Execution Map`, `Work Board`, `Create Item`, or `WorkItem` language into docs or code
- keep copied semantics for MCP execution separate from clipboard formatting changes in this PR

## Phase 4: Platform And Operations Hardening

### Goal

Turn the working prototype into an operable macOS utility app.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Add launch-at-login support via `SMAppService` | Platform lead | Working app shell | Yes | Login item can be enabled and disabled reliably | Pending |
| Add settings surface for screenshot folder, TTL, and startup behavior | Product engineering lead | Working core flows | Yes | Sensitive behaviors are user-configurable | In progress |
| Implement security-scoped bookmark storage for screenshot folder | Platform lead | Settings surface | Yes | Folder access persists across launches | In progress |
| Add logging for hotkey, capture, storage, and watcher failures | Platform lead | Core services | Yes | Failure paths are observable | Pending |
| Decide update strategy and wire `Sparkle` if shipping direct | Release lead | Distribution decision | Yes | Auto-update path is documented or implemented | Pending |
| Add notarization/signing pipeline | Release lead | Build stability | Yes | Signed and notarized app can be shipped | Pending |
| Add DMG packaging pipeline for Gumroad releases | Release lead | Signed app build | Yes | Versioned DMG can be generated repeatably | Pending |
| Prepare Gumroad release assets and delivery checklist | Product + release lead | DMG pipeline | Yes | Store listing, version notes, and upload checklist exist | Pending |
| Define MAS compatibility lane and gap list | Platform + release lead | Working direct-distribution build | Yes | Sandbox blockers and entitlement differences are documented | Pending |

### Parallel Tracks

- Track A: Permissions and folder access
- Track B: Settings and startup behavior
- Track C: Release and update pipeline
- Track D: Commerce packaging and distribution ops

### Exit Criteria

- The app is operable on a clean machine.
- Folder access survives relaunch.
- Startup and update behavior are not manual hacks.
- Gumroad-ready DMG packaging is repeatable.
- App Store blockers are explicitly listed, not assumed away.

## Phase 5: Polish, Validation, And Release Prep

### Goal

Verify that the product feels like a native macOS utility, not just a working prototype.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Refine spacing, typography, animation, and focus behavior | UI lead | Phase 3 complete | Yes | UI feels intentional and lightweight | Pending |
| Add keyboard navigation and selection polish | UX lead | Phase 3 complete | Yes | Keyboard-first flow is smooth | Pending |
| Add automated tests for TTL, formatting, persistence, and watcher logic | Test lead | Core services complete | Yes | Critical logic is covered by unit tests | Pending |
| Add smoke test checklist for capture, recall, export, and restart | QA lead | Phases 2-4 complete | Yes | Repeatable manual validation exists | Pending |
| Run performance and memory checks for idle utility behavior | Platform lead | Stable build | Yes | Idle footprint is acceptable | Pending |
| Prepare release checklist and rollback plan | Release lead | Stable build | Yes | Release path is reversible | Pending |

### Parallel Tracks

- Track A: UI polish
- Track B: automated testing
- Track C: release validation

### Exit Criteria

- Core journeys pass on a clean machine.
- Idle behavior is lightweight.
- Release artifacts and rollback plan are documented.

## Suggested Ownership Map

- Master only:
  - App entrypoints
  - Dependency wiring
  - Shared contracts
  - Integration docs
- Track A:
  - Domain models
  - Persistence
  - TTL logic
- Track B:
  - Hotkeys
  - Panel/window controllers
  - Login item
- Track C:
  - SwiftUI views
  - Selection/copy UX
  - Visual polish
- Track D:
  - Release pipeline
  - Signing/notarization
  - Update path

## Multi-Agent Execution Rules

1. Freeze shared contracts before parallel code work starts.
2. Assign each track a file ownership boundary, not a vague feature label.
3. Do not allow workers to edit the same file unless master opens an explicit edit window.
4. Integrate in this order:
   1. shared contracts
   2. core services
   3. UI/interaction
   4. ops/release
5. Require each worker to submit:
   - what changed
   - what was verified
   - remaining risks
6. If a shared contract changes, pause dependent tracks and rebase work at the plan level before more edits land.

## Master Review Gates

### Track Gate

- Touched files stay inside ownership boundaries.
- The changed surface builds locally or has a concrete blocker documented.
- New behavior is covered by at least one verification step.
- The worker calls out behavioral risk and rollback approach.

### Integration Gate

- The app builds from the integration branch/workspace.
- Shared handoff points compile together.
- Core journeys work:
  - quick capture
  - stack open
  - staged stack copy
  - grouped copy commit on close
  - relaunch persistence
  - TTL cleanup

### Release Gate

- No unresolved TODOs on hotkey, persistence, or permission-critical paths.
- Signing and launch-at-login behavior are validated.
- Update path and rollback plan are documented.

## Locked Implementation Choices

- Primary storage: `SQLite + GRDB`
- Primary distribution: Gumroad-backed direct download first, signed and notarized
- App Store path: deferred until screenshot permission flow is proven
- UI shell: `SwiftUI + AppKit hybrid`

## Immediate Next Slice

1. Tighten shared contracts in `Sources/PromptCueCore/*` and app-facing aliases.
2. Add `GRDB` and land the first SQLite-backed persistence slice.
3. Lock file ownership for:
   - services
   - window controllers
   - SwiftUI views
4. Build Phase 2 and Phase 3 in parallel under master review.
