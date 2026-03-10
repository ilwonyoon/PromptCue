# Backtick Master Board

## Objective

Ship Backtick as a native macOS utility app that gives AI-assisted developers a frictionless scratchpad for capture, execution-queue review, and clipboard export.

## Locked Decisions

- Product identity: `Backtick`
- Current repo/app target/core module names remain `PromptCue` / `PromptCueCore` for now
- Product proposals are judged against Backtick as an AI coding scratchpad / thought staging tool, not a note app
- Interaction model:
  - Capture = frictionless dump
  - Stack = execution queue
  - AI compression happens in Stack
- Platform shape: standard macOS utility app, not an App Extension
- App shell: `LSUIElement` background utility with status item and floating panels
- UI stack: SwiftUI for view composition, AppKit for windowing and system integration
- Distribution baseline: Gumroad-backed direct distribution first, Mac App Store compatibility deferred
- Screenshot strategy: user-selected screenshot folder with security-scoped bookmark support
- Persistence baseline: local-only storage with optional auto-expiration, disabled by default
- Storage engine baseline: `SQLite + GRDB`

## Current Status

| Area | Status | Notes |
| --- | --- | --- |
| Execution PRD | Completed | Repo-backed and aligned to native macOS direction |
| Implementation plan | Completed | Phase/task breakdown landed in repo |
| Engineering preflight | Completed | Setup, distribution, Gumroad, DMG, and MAS considerations documented |
| Architecture decision | Locked | Native macOS utility app |
| Repo scaffold | In progress | App target, local package, CI, and XcodeGen wiring are in place |
| Core contracts | In progress | App target now depends on `PromptCueCore`; some app-only state contracts remain local |
| Hotkey integration | In progress | Carbon-backed registration is implemented; runtime smoke test still needed |
| Windowing | In progress | NSPanel controllers are implemented; runtime focus behavior still needs verification |
| Persistence | In progress | SQLite-backed `CardStore` is implemented via GRDB and attachment ownership is app-managed |
| Screenshot attachment | In progress | Recent screenshot detection now depends on an explicitly approved folder |
| Core UI | In progress | Capture and stack views now render real MVP UI |
| Quality audit | Completed | Findings captured and prioritized for remediation |
| Remediation lane | In progress | Contract lock and phased closure tracked in `docs/Quality-Remediation-Plan.md` |
| Performance remediation lane | Completed | `P1-P4`, the approved capture/stack visuals, the long-note overflow path, and the live stack-open trace harness are active in the merge-safe landing candidate; the historical `P5` compositor benchmark remains documented in `docs/Performance-Remediation-Plan.md` |
| Design polish lane | In progress | `DP0` review lock is complete; `DP1` capture elevation and `DP2` stack brightness are now in implementation and awaiting visual review packets |
| Settings surface | In progress | Shortcut recorders and screenshot folder controls are now implemented |
| Stack sync and light-mode readability | In progress | `Phase R6` now uses tracked capture submission plus a stronger light-mode veil; real-device QA is still the gate |
| Capture input system hardening | In progress | `Phase R7A` contract lock and QA harness are complete; `Phase R7B` now rewrites the live capture panel around an AppKit-owned sizing host |
| AI Export Tail / Prompt Suffix | Planned | export-time-only suffix append with Settings toggle, multiline text, and regression coverage |
| Stack card overflow and click expansion | In progress | long cards need capped resting height, `+N lines` affordance, click-to-expand, and stable copied-stack behavior |
| Design-system architecture alignment | In progress in strategy branch | `docs/Design-System-Architecture-Proposal.md` defines a five-layer model that preserves runtime and pattern ownership |
| Design-system execution planning | In progress in strategy branch | `docs/Design-System-Execution-Plan.md` breaks the strategy into DS1-DS5; DS1, DS2, and DS3 are implemented, DS4 has started, and DS5 remains pending |

## Current File Ownership

- Master only:
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Master-Board.md`
  - `/Users/ilwonyoon/Documents/PromptCue/project.yml`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppCoordinator.swift`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppDelegate.swift`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/PromptCueApp.swift`
- Track A, product execution docs:
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Execution-PRD.md`
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Engineering-Preflight.md`
- Track B, delivery planning docs:
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Implementation-Plan.md`
- Future implementation Track C, foundation and services:
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/Domain`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services`
  - `/Users/ilwonyoon/Documents/PromptCue/Sources/PromptCueCore`
- Future implementation Track D, windowing and shell:
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel.swift`
- Future implementation Track E, views and interaction:
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Theme.swift`

## Integration Order

1. Contracts and persistence
2. Screenshot monitoring and clipboard formatting
3. Hotkeys and panel shell
4. Capture UI and stack UI
5. Launch-at-login, settings, and polish
6. AI Export Tail / Prompt Suffix integration
7. Stack card overflow and click expansion
8. DMG packaging, Gumroad release prep, and MAS compatibility review
9. Continue design-system strategy execution in the strategy branch: finish DS3, expand DS4 conservatively, then run DS5 native-alignment pass
10. Run the bounded capture/stack polish lane: `DP0 -> DP4`, with review packets per slice

## Remediation Merge Order

1. Phase R0 contract lock
2. Track A, data integrity and attachment ownership
3. Track C, screenshot access and settings
4. Track B, selection and clipboard export
5. Track D, design-system reconciliation
6. Phase R8 AI Export Tail / Prompt Suffix
7. Phase R9 stack card overflow and click expansion
8. Full verification pass

## Track Gates

### Gate 1: Track Review

- Touched files stay within ownership
- Build passes for affected target
- Self-review includes behavior change, risk, and rollback note
- No unresolved stubs in claimed scope

### Gate 2: Integration Review

- Full app builds on macOS target
- Capture flow works with keyboard only
- Card stack opens and closes reliably
- Clipboard export works for single and multi-card selection
- TTL cleanup runs without data corruption

### Gate 3: Release Review

- Screenshot permission path is explicit and understandable
- Launch-at-login behavior is stable
- Window focus and hotkey behavior are verified across apps
- Failure states are surfaced without blocking capture flow

## Main Merge Plan

Current constraints:

- the exploratory worktree now lives on `feat/performance-main-integration`, not directly on `main`
- a clean style-preserving candidate now exists on `feat/performance-main-safe` in `../PromptCue-main-safe`
- local `main` remains the fast-forward target and should stay clean while commit slicing happens on the integration branches

Branch strategy:

1. create one temporary integration branch from the current local `main`
2. move the dirty worktree onto that branch
3. land the groups below in order, with each group building and passing its own gate before the next one is committed
4. after the final integration gate passes, fast-forward `main` to the integration branch and push

Safe-main profile:

- if the goal is to land the current approved interaction behavior, visuals, and overflow behavior first, prepare a clean worktree from `main` and copy only the merge-approved files into it
- preferred entrypoint:
  `scripts/sync_safe_main_merge_worktree.sh --verify`
- this profile now carries the long-note overflow path, including `PromptCue/UI/Views/CaptureCardView.swift`, `PromptCue/UI/Views/CardStackView.swift`, `PromptCue/UI/Components/StackCardOverflowPolicy.swift`, and the related rendering/policy tests
- this profile now carries the approved capture/stack visual tune and the long-note overflow path
- this profile intentionally still defers only the historical `P5` stack visual benchmark file and command wiring
- use `scripts/verify_main_merge_safety.sh --profile safe-main` inside that worktree so the verification suite matches the merge-safe scope instead of expecting the deferred visual benchmark files

Recommended commit groups:

0. `Merge infra and safe-main automation`
   Files:
   `.gitignore`
   `scripts/verify_main_merge_safety.sh`
   `scripts/sync_safe_main_merge_worktree.sh`
   `docs/Master-Board.md`
   Verification:
   `scripts/sync_safe_main_merge_worktree.sh --verify`

1. `Performance core: persistence, capture-open decoupling, and sync handoff`
   Files:
   `PromptCue/App/AppModel.swift`
   `PromptCue/Services/CardStore.swift`
   `PromptCue/Services/CloudSyncEngine.swift`
   `PromptCue/Services/CloudSyncControlling.swift`
   `PromptCue/Services/RecentScreenshotCoordinator.swift`
   `PromptCue/Services/RecentScreenshotLocator.swift`
   `PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift`
   `PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift`
   `PromptCue/UI/WindowControllers/CapturePanelController.swift`
   `PromptCueTests/CloudSyncMergeTests.swift`
   `PromptCueTests/RecentScreenshotCoordinatorClipboardTests.swift`
   `PromptCueTests/RecentScreenshotCoordinatorTests.swift`
   `PromptCueTests/StorageServicesTests.swift`
   `PromptCueTests/AppStartupPerformanceTests.swift`
   `PromptCueTests/CapturePanelResizePerformanceTests.swift`
   `PromptCueTests/CapturePreviewImagePerformanceTests.swift`
   `PromptCueTests/CardStorePerformanceTests.swift`
   `PromptCueTests/CloudSyncApplyPerformanceTests.swift`
   `PromptCueTests/CloudSyncPushPerformanceTests.swift`
   `PromptCueTests/RecentScreenshotCoordinatorPerformanceTests.swift`
   `docs/Performance-Remediation-Plan.md`
   Scope note:
   safe-main now includes the approved long-note overflow and click-to-expand behavior, along with the related rendering and policy tests. Keep the historical benchmark file out of the merge candidate.
   Verification:
   `xcodegen generate`
   `swift test`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CardStorePerformanceTests`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/RecentScreenshotCoordinatorPerformanceTests`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyBenchmark`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyDispatchBenchmark`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testQueuedRemoteApplyCompletionBenchmark`

2. `Stack presentation instrumentation and live trace harness`
   Files:
   `PromptCue/App/AppCoordinator.swift`
   `PromptCue/App/PerformanceTrace.swift`
   `PromptCue/UI/WindowControllers/StackPanelController.swift`
   `scripts/record_stack_open_trace.sh`
   `docs/Implementation-Plan.md`
   Verification:
   `xcodegen generate`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
   `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`

3. `Approved capture/stack visual tune`
   Files:
   `PromptCue/UI/Components/StackNotificationCardChromeRecipe.swift`
   `PromptCue/UI/Components/StackNotificationCardSurface.swift`
   `PromptCue/UI/Components/StackPanelBackdrop.swift`
   `PromptCue/UI/Components/StackPanelBackdropRecipe.swift`
   `PromptCue/UI/DesignSystem/PrimitiveTokens.swift`
   `PromptCue/UI/DesignSystem/SemanticTokens.swift`
   `PromptCue/UI/DesignSystem/PanelBackdropFamily.swift`
   `PromptCue/UI/Preview/DesignSystemPreviewView.swift`
   `docs/Design-Polish-Execution-Plan.md`
   Verification:
   `xcodegen generate`
   `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
   `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`

4. `Planning docs only`
   Files:
   `docs/Design-System.md`
   `docs/Execution-PRD.md`
   `docs/Quality-Remediation-Plan.md`
   Rationale:
   these files describe future `R9` overflow and click-to-expand behavior; they are safe to merge only if the team wants planning-only changes on `main` before the code lands

Include generated project wiring with the first commit group that introduces new tracked files, and regenerate it again whenever the tracked file set changes:

- `PromptCue.xcodeproj/project.pbxproj`

Exclude from this merge for now:

- `.claude/**`
- `first`

Functional-first merge gate:

- before any performance benchmark or live trace step, require one non-perf regression suite that proves already-implemented `main` behavior still holds for:
  - capture submit and recent-screenshot attachment resolution
  - clipboard-image fallback and screenshot-session transitions
  - persistence batch upsert/delete behavior
  - cloud-sync merge/apply behavior
  - capture layout and stack-card rendering surfaces
- command:
  `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/AppModelRecentScreenshotTests -only-testing:PromptCueTests/RecentScreenshotCoordinatorTests -only-testing:PromptCueTests/RecentScreenshotCoordinatorClipboardTests -only-testing:PromptCueTests/StorageServicesTests -only-testing:PromptCueTests/CloudSyncMergeTests -only-testing:PromptCueTests/CaptureComposerLayoutTests -only-testing:PromptCueTests/CueTextEditorMetricsTests -only-testing:PromptCueTests/CaptureEditorLayoutCalculatorTests -only-testing:PromptCueTests/CaptureCardRenderingTests`

Final integration gate before fast-forwarding back into `main`:

- preferred entrypoint: `scripts/verify_main_merge_safety.sh [--app <Prompt Cue.app>]`
- safe-main entrypoint for the currently approved UI and interaction set: `scripts/verify_main_merge_safety.sh --profile safe-main [--app <Prompt Cue.app>]`
- `xcodegen generate`
- `swift test`
- the functional-first merge gate command above
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/CloudSyncMergeTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyBenchmark`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyDispatchBenchmark`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testQueuedRemoteApplyCompletionBenchmark`
- optional historical perf reference only: `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/StackPanelVisualPerformanceTests/testStackVisualRenderBenchmark`
- `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`
- `git diff --check`

Latest safe-main rerun:

- 2026-03-10: passed after restoring recent-screenshot open/immediate-submit semantics on the landing candidate
- latest live trace after that fix: `PROMPTCUE_STACK_OPEN_FIRST_FRAME_MS=63.30`

## Immediate Next Moves

1. QA `Phase R6` against real `capture -> Enter -> Cmd + 2` timing in light and dark mode
2. Tune any remaining light-mode veil or capture-surface shadow issues without reopening the sync path
3. Close the remaining `Phase R7` follow-up on IME-safe command routing and placeholder ownership
4. Keep deterministic capture QA and input metrics coverage green
5. Keep regression coverage for `submit -> immediate stack open` green
6. Land `AI Export Tail / Prompt Suffix` as an export-only formatter + Settings slice
7. Land long-card overflow handling so Stack remains scannable under extreme text length
8. Resume grouped export validation against target paste destinations
9. Run `DP1` capture elevation and `DP2` stack brightness in bounded parallel tracks
10. Keep semantic token changes master-owned while capture/stack recipe changes land through review packets
11. Keep `scripts/record_stack_open_trace.sh` in the regression loop whenever stack backdrop, card chrome, panel animation, or windowing behavior changes land

Guardrail:

- do not accept work that turns Backtick into a general note app
- prefer raw dump in Capture and structured compression/export in Stack
- do not accept design-system cleanup that collapses stack backdrop, stack card, or capture runtime ownership into one generic abstraction
- do not accept visual polish that ships without light/dark before-after review artifacts
