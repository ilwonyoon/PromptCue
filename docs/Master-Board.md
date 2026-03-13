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
| Public launch hardening lane | In progress | `H0` contract lock is active in `docs/Public-Launch-Hardening-Plan.md`; master-owned `H1` release work may proceed in parallel while runtime `H2-H5` merges stay behind the current `safe-main` gate |
| Remediation lane | In progress | Contract lock and phased closure tracked in `docs/Quality-Remediation-Plan.md` |
| Performance remediation lane | Completed | `P1-P4`, the approved capture/stack visuals, the long-note overflow path, and the live stack-open trace harness are active in the merge-safe landing candidate; the historical `P5` compositor benchmark remains documented in `docs/Performance-Remediation-Plan.md` |
| Design polish lane | In progress | `DP0` review lock is complete; `DP1` capture elevation and `DP2` stack brightness are now in implementation and awaiting visual review packets |
| Settings surface | In progress | Shortcut recorders and screenshot folder controls are now implemented |
| Stack sync and light-mode readability | In progress | `Phase R6` now uses tracked capture submission plus a stronger light-mode veil; real-device QA is still the gate |
| Capture input system hardening | In progress | `Phase R7A` contract lock and QA harness are complete; `Phase R7B` now rewrites the live capture panel around an AppKit-owned sizing host, and the suggested-target selector is fully fixed with the v2 replacement contract locked in `docs/Capture-Suggested-Target-Selector-Repair-Plan.md` |
| Inline tag contract hardening | In progress | prototype interaction is landed, but live diagnosis confirmed polluted structured tags from mixed-script input; `Phase R7C` now locks canonical slug tags before broader MCP-facing rollout |
| AI Export Tail / Prompt Suffix | Planned | export-time-only suffix append with Settings toggle, multiline text, and regression coverage |
| Stack card overflow and click expansion | In progress | long cards need capped resting height, `+N lines` affordance, click-to-expand, and stable copied-stack behavior |
| Design-system architecture alignment | In progress in strategy branch | `docs/Design-System-Architecture-Proposal.md` defines a five-layer model that preserves runtime and pattern ownership |
| Design-system execution planning | In progress in strategy branch | `docs/Design-System-Execution-Plan.md` breaks the strategy into DS1-DS5; DS1, DS2, and DS3 are implemented, DS4 has started, and DS5 remains pending |

## Current File Ownership

For `Phase H` public launch hardening, the authoritative ownership model is now the one in `docs/Public-Launch-Hardening-Plan.md`.

`Phase H` worktree map:

- Master:
  - release-sensitive docs, config, entitlements, scripts, and app entrypoints
- `services-security`:
  - screenshot/bookmark/attachment-ingress/privacy-boundary work
- `core-perf`:
  - idle polling, startup lifecycle, and wake-up containment work
- `ui-battery`:
  - minimal disclosure UI only when a privacy decision requires it, plus runtime smoke support

This `Phase H` map supersedes the older Track A-E naming below for the public launch hardening lane.

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

## MCP Direction

Current MCP direction is narrower than the old plan:

- build MCP over `Stack` storage directly
- do not keep board or work-item experiments alive

Current MCP-facing tag rule:

- Stack notes may carry lightweight structured tags to improve downstream AI classification
- those tags must come from the canonical storage contract, not from arbitrary `#...` body text
- polluted mixed-script tag strings are a data-integrity issue, not a presentation issue
- fix storage and parsing first, then let Capture and Stack reconstruct inline display from the cleaned structured tags

Carry forward:

- `CaptureCard`
- `CardStore`
- `CopyEvent`
- `copy_events` persistence

Remove from active planning:

- `ExecutionMap*`
- `Work Board`
- `Create Item`
- `WorkItem`
- `WorkItemSource`
- `WorkItemStore`
- startup or menu flags that only existed for board experiments

Reason:

- the real requirement is Stack DB `read/write` from `Claude Code CLI` and `Codex CLI`
- copied state should update when an AI actually executes a note
- derived planning surfaces add merge surface and conceptual debt without helping that path

Active MCP rollout:

1. `MCP2` Stack read bridge
   - expose active and copied Stack notes
   - expose note text, target metadata, and copied metadata

2. `MCP3` Stack write bridge
   - create, update, and delete Stack notes directly

3. `MCP4` execution action
   - mark executed notes as copied
   - persist `CopyEvent` rows with MCP actor/session metadata

4. `MCP5` stdio tool surface
   - expose Stack note tools to external MCP clients

5. `MCP6` connector settings surface
   - show supported MCP clients, config status, and expected Backtick MCP command/path
   - give users a native place to understand where MCP is attached
   - support both repository-checkout workflows and a future bundled helper path

6. `MCP7` guided setup and validation
   - help users connect `Claude Code` and `Codex` without relying on undocumented shell knowledge
   - test that client setup actually works

7. `MCP8` bundled helper packaging
   - ship a launchable `BacktickMCP` helper with release builds
   - keep the source-checkout path as the developer fallback

Current landed slices:

- `MCP2` read bridge landed on `main`
- `MCP3` write bridge landed on `main`
- `MCP4` execution action landed on `main`
- `MCP5` stdio tool surface landed on `main`
- `MCP6` connector settings surface landed on `main`
- `MCP7` guided setup and local server validation landed on `main`
- `MCP8` bundled helper packaging landed on `main`
- execution-map style UI remains out of scope while post-MCP rollout work is prioritized
- Settings-based connector UI is now the user-facing MCP rollout surface, including setup and local validation

Landed MCP gates:

- read service lists active and copied notes directly from Stack storage
- read service returns note detail plus `CopyEvent` history
- service creates, updates, and deletes Stack notes directly
- service cleans up managed screenshot attachments on delete
- write service does not write `CopyEvent` rows
- execution service updates copied state and `CopyEvent` rows together
- no menu, settings, or panel behavior changes
- app build and targeted read/write service tests pass

`PR #24` gate:

- execution service updates copied state and `CopyEvent` rows together
- execution service preserves requested note order for returned copied notes
- plain write operations still do not write `CopyEvent` rows
- no menu, settings, panel, or execution-map changes
- app build and targeted execution-service tests pass

Landed `MCP5` gate:

- MCP transport calls the landed Stack services instead of duplicating logic
- tool surface exposes read, write, and execute actions for Stack notes
- no menu, settings, panel, or execution-map changes
- end-to-end smoke coverage exists for the shared DB path
- `main` contains the read, write, execution, and stdio transport layers together

Current external smoke finding:

- `Claude Code` and `Codex` both connect successfully on merged `main`
- both smokes ran from a temp directory with no source checkout present and used the bundled `BacktickMCP` helper path directly
- `Claude Code` in `--permission-mode dontAsk` requires Backtick MCP tools in `--allowedTools`
- treat non-interactive permission denial as client setup friction, not as an MCP server failure

Landed `MCP6` gate:

- Settings shows a `Connectors` tab without regressing existing tabs
- `Claude Code` and `Codex` sections expose CLI path, project/home config status, quick-add command, and config snippet
- `Copy Command`, `Copy Add Command`, `Copy Config Snippet`, `Reveal`, and `Open Docs` all worked in manual smoke
- `MCP2` through `MCP5` behavior remains unchanged; this slice is read-mostly UI
- external MCP client smoke has now run against merged `main` and feeds `MCP7`

Landed `MCP7` gate:

- Settings `Connectors` now shows `What It Does`, `Setup Flow`, `Launch Command`, and `Server Test`
- the local server self-test validates `initialize` and `tools/list` directly from Settings and promotes a configured client to `Connected`
- failure states keep specific detail for launch failure, invalid response, missing tools, and other local validation issues
- `Claude Code` now shows an automation lane for `--permission-mode dontAsk` with a copyable `--allowedTools` example
- existing connector inspection actions remain intact while setup guidance moved into the same Settings surface

Post-`MCP5` rollout:

- `MCP6` adds a `Connectors` section to Settings so the user can see:
  - whether `Claude Code` or `Codex` is configured
  - what command/path those clients should launch
  - copyable config/install instructions
- `MCP7` adds guided setup and validation so the user can connect a client and confirm the MCP handshake works
  - guided setup explains what MCP means in Backtick terms and walks the user through config plus validation
  - initial validation is a Backtick-owned local self-test of the launch command and tool surface
  - Claude gets a separate automation lane for `--permission-mode dontAsk`
  - product error handling should separate `tool permission denied` from launch/connect failures
- connector UX refinement keeps that surface terse and action-first
  - the default screen should show server readiness, client setup state, and the next action without opening long snippets
  - action priority is fixed:
    - install the client if the CLI is missing
    - add Backtick to config if setup is missing
    - run the local test after setup
    - show fix-oriented troubleshooting when validation fails
  - refined states should read like product status, not transport internals:
    - `CLI not found`
    - `Needs setup`
    - `Set up`
    - `Not verified`
    - `Local server OK`
    - `Needs attention`
  - generic `Advanced` should be replaced by:
    - `Manual Setup`
    - `Troubleshooting`
    - `Automation`
  - raw config, CLI paths, and automation examples belong behind those action-specific disclosures
  - reference patterns:
    - Cursor `Tools & MCP` settings structure
      - https://cursor.com/docs/mcp
    - Claude Code MCP docs
      - https://docs.anthropic.com/en/docs/claude-code/mcp
    - Codex docs
      - https://developers.openai.com/codex
- `MCP8` packages a helper binary so connector setup works in release builds outside source checkouts
- these slices exist because transport-only MCP is not enough if the user cannot discover, attach, or verify the connector from inside Backtick

Rules:

- Stack remains the only source of truth
- no derived item layer should sit between Stack and MCP tools
- copied state means execution happened, not that planning or grouping happened
- cleanup of board and work-item code is not optional follow-up; it is part of getting MCP scope back into focus

## Recent Non-MCP Landing

`PR #25` `feat/default-multi-copy` is on `main` and is now the stack/export baseline for MCP-facing clipboard behavior.

Landed scope:

- staged grouped copy is the default stack click behavior
- copied ordering commits on stack close instead of on click
- standalone raw literals skip the export tail suffix

Verification already run:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackMultiCopyTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/PromptExportTailSettingsTests -only-testing:PromptCueTests/StackMultiCopyTests`
- stack smoke:
  card click stages copy without closing, second click unstages, panel close commits copied ordering

Current rule:

- `MCP5` transport work must inherit this stack/export baseline instead of reintroducing the older `Copy Multiple` flow

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
- Clipboard export works for live staged stack copy and grouped export commit
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

- 2026-03-10: passed after the hidden stack-panel prewarm landed on the landing candidate
- latest live trace reruns after that fix: `21.35 ms`, `18.74 ms`, `22.22 ms`

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
