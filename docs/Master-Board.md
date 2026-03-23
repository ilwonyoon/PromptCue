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
- First-launch review guardrail: `Capture` is bugfix-only before the first DMG;
  non-blocking tuning in typing, IME, and screenshot-attach hot paths defers
  until after launch unless a measured regression is being fixed

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
| Launch readiness review lane | In progress | pre-DMG launch-risk review is tracked in `docs/Launch-Readiness-Review-Plan.md` and should drive the final blocker report before a signed DMG candidate is cut |
| Remediation lane | In progress | Contract lock and phased closure tracked in `docs/Quality-Remediation-Plan.md` |
| Performance remediation lane | Completed | `P1-P4`, the approved capture/stack visuals, the long-note overflow path, and the live stack-open trace harness are active in the merge-safe landing candidate; the historical `P5` compositor benchmark remains documented in `docs/Performance-Remediation-Plan.md` |
| Capture runtime post-launch lane | Planned | after the first DMG, run the structural capture-runtime redesign in `docs/Capture-Runtime-Post-Launch-Plan.md`; keep launch-time capture changes bugfix-only until then |
| Design polish lane | In progress | `DP0` review lock is complete; `DP1` capture elevation and `DP2` stack brightness are now in implementation and awaiting visual review packets |
| Settings surface | In progress | Shortcut recorders and screenshot folder controls are now implemented |
| MCP platform expansion | In progress | stdio connector rollout is shipped for `Claude Desktop`, `Claude Code`, and `Codex`; ChatGPT remote MCP is now an experimental self-hosted OAuth path on `main` |
| Warm memory / project documents | Planned | post-launch MCP follow-on: save long Claude Desktop / ChatGPT discussions as reviewed project documents with explicit `documentType` plus flat topic classification |
| Stack sync and light-mode readability | In progress | `Phase R6` now uses tracked capture submission plus a stronger light-mode veil; real-device QA is still the gate |
| Capture input system hardening | In progress | `Phase R7A` contract lock and QA harness are complete; `Phase R7B` now rewrites the live capture panel around an AppKit-owned sizing host, and the suggested-target selector is fully fixed with the v2 replacement contract locked in `docs/Capture-Suggested-Target-Selector-Repair-Plan.md` |
| Inline tag contract hardening | Completed | canonical slug tag parsing, polluted-tag rejection, legacy tag cleanup, inline reconstruction, and MCP-safe tag payloads are landed on `main`; remaining `Phase R7` work is broader input-system hardening, not tag contract work |
| Inline tag integration | In progress | PR `#50` is now governed by `docs/PR50-Inline-Tag-Integration-Runbook.md`; merge work must preserve selector stability, keyboard safety, and theme-sync behavior on current `main` |
| AI Export Tail / Prompt Suffix | Completed | export-time-only suffix append, Settings toggle, multiline text, clipboard integration, and regression coverage are landed on `main` |
| Stack card overflow and click expansion | Completed | capped resting height, `+N lines` affordance, click-to-expand, and stable collapsed copied-stack summaries are landed on `main` |
| Stack long-text resting rule follow-up | In progress | Stack resting long-text collapse is being tightened to a Stack-specific scan-band line cap so long cards collapse predictably without depending on Capture height |
| Stack refactor execution plan | Planned | the next Stack-wide slice is now locked in `docs/Stack-Refactor-Execution-Plan.md`, covering render containment, clipping repair, and the staged rollout for the new header rail/filter/TTL/logo UX |
| Stack header rail, filter, and TTL ring | Planned | the next stack UX follow-up is locked in `docs/Stack-Header-Rail-Plan.md`, including a persistent header rail, launch-facing queue terminology, stack filtering, per-card TTL rings, and theme-adaptive Backtick logo rules |
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
6. Keep `AI Export Tail / Prompt Suffix` regression coverage green
7. Keep stack-card overflow and click-to-expand regression coverage green
8. DMG packaging, Gumroad release prep, and MAS compatibility review
9. Continue design-system strategy execution in the strategy branch: finish DS3, expand DS4 conservatively, then run DS5 native-alignment pass
10. Run the bounded capture/stack polish lane: `DP0 -> DP4`, with review packets per slice
11. After the first DMG, run the capture-runtime redesign lane from `docs/Capture-Runtime-Post-Launch-Plan.md`

## Remediation Merge Order

1. Phase R0 contract lock
2. Track A, data integrity and attachment ownership
3. Track C, screenshot access and settings
4. Track B, selection and clipboard export
5. Track D, design-system reconciliation
6. Remaining `Phase R7` input-system follow-up
7. MCP platform stabilization and ChatGPT experimental UX cleanup
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

- the real requirement is cross-client `Stack` DB `read/write` from `Claude Desktop`, `Claude Code`, `Codex`, and the experimental ChatGPT path
- the intended user value is: let an AI pull the important notes, summarize or classify what matters, and write the distilled result back into Backtick
- direct repository `docs/` editing is not the Backtick MCP surface itself; that remains a separate code-agent or manual follow-up after the key memory is written back into `Stack`
- after the current Stack-first MCP rollout, the next memory layer is reviewed project documents: long ChatGPT / Claude Desktop discussions should go through a proposal/review/confirm step before becoming typed docs, rather than being silently auto-distilled at the end of a huge thread
- Warm behavior should be carried by server-wide MCP instructions as well as tool descriptions, so Claude Mac / iPhone / web clients all receive the same recall-first and save-proposal defaults
- the concrete design for the next memory polish slice now lives in `docs/MCP-Polish-Plan.md`, including the `Prompt / Memory` vocabulary shift, `propose_document_saves`, and chat-first save review
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

ChatGPT track note:

- current shipped connector surface is `Claude Desktop`, `Claude Code`, and `Codex`
- ChatGPT remains a separate remote-MCP track, not part of the shipped stdio connector scope
- ChatGPT now has an experimental self-hosted remote OAuth path on `main`
- advanced-user assumptions apply: Backtick must remain running, the user must provide a public HTTPS URL/tunnel, and OAuth approval happens in ChatGPT web
- do not plan against localhost ChatGPT registration
- do not treat this track as a replacement for the remaining core product roadmap work now that `Phase R7C`, `Phase R8`, and `Phase R9` are landed on `main`

Current landed slices:

- `MCP2` read bridge landed on `main`
- `MCP3` write bridge landed on `main`
- `MCP4` execution action landed on `main`
- `MCP5` stdio tool surface landed on `main`
- `MCP6` connector settings surface landed on `main`
- `MCP7` guided setup and local server validation landed on `main`
- `MCP8` bundled helper packaging landed on `main`
- `MCP9` experimental self-hosted ChatGPT remote MCP landed on `main`
- execution-map style UI remains out of scope while post-MCP rollout work is prioritized
- Settings-based connector UI is now the user-facing MCP rollout surface, including setup and local validation

Current MCP scope split:

1. shipped on `main`
   - Stack note read/write/execute over MCP for `Claude Desktop`, `Claude Code`, and `Codex`
   - permanent prompt reuse via pinned cards is already part of the shipped Stack surface
2. experimental on `main`
   - ChatGPT remote MCP through a self-hosted OAuth + public HTTPS path
   - advanced-user only; not default onboarding
3. research-backed but not started
   - Warm memory / project documents
   - reviewed long-form docs with `documentType` + flat topic classification
   - dedicated Memory panel and Warm MCP tools

Current MCP platform queue:

1. keep stdio connectors stable for `Claude Desktop`, `Claude Code`, and `Codex`
2. upgrade shipped stdio verification so `Configured` and `Verified locally` are separate product states
3. the stdio `Verified locally` contract should require:
   - exact configured launch command
   - `initialize`
   - `notifications/initialized`
   - `tools/list`
   - one safe read-only `tools/call`
4. keep ChatGPT remote MCP clearly marked `experimental self-hosted`
5. improve stale-app reset, reconnect, and health UX for the ChatGPT path, but keep the visible UX limited to current state, one-line reason, and one next action; then lock the failure matrix behind repeatable stress coverage instead of one-off fixes
6. upgrade the ChatGPT connector from merely `Running` to `Connected` only after Backtick sees a successful remote `/mcp` call from the current app setup
7. add a short access-token TTL lane so expiry + refresh recovery is proven in minutes, not after a full real-time wait
8. keep the minimal sleep/wake + tunnel-drift lane active now: recheck helper health on foreground / wake and collapse any local/public endpoint failure back to one recovery state without adding more UI chrome
9. return main product priority to the remaining non-tag `Phase R7` follow-up plus grouped export and stack-refactor validation work
10. lock the post-launch Warm memory contract so long AI discussions save into reviewed project documents with explicit `documentType` plus topic classification
11. do not blur shipped Stack MCP, experimental ChatGPT remote MCP, and post-launch Warm memory into one roadmap bucket
12. keep ChatGPT distribution on the advanced-user self-hosted track; hosted relay / managed distribution is not in the active plan
13. treat `docs/MCP-Platform-Expansion-Research.md` as the MCP execution reference and `docs/Mem0-Takeaways-for-Backtick.md` as the Warm-memory filter before starting any new MCP follow-on
14. keep the first Warm slice narrow: `ProjectDocument` storage, two-tier retrieval (`list_documents` discovery vs `recall_document` full recall), proactive save/recall tool descriptions, and human-reviewed Hot -> Warm promotion

ChatGPT remote MCP reliability floor:

| Failure class | Expected behavior | Coverage |
| --- | --- | --- |
| stale ChatGPT OAuth grant / refresh token | Backtick should surface a single reset path, and the user should be told to recreate the ChatGPT app if the client is holding an older grant | Settings reconnect guidance + targeted regression |
| helper or app restart while OAuth state persists | persisted dynamic client registration and refresh tokens should still work after helper restart | package regression + stress harness |
| reused authorization code | token endpoint must reject the second exchange with `invalid_grant` | package regression + stress harness |
| invalid or stale refresh token | token endpoint must reject with `invalid_grant` instead of silently degrading into an opaque tool failure | package regression + stress harness |
| missing or invalid bearer token on `/mcp` | helper must return `401` consistently | existing package regression + stress harness |
| missing or invalid public HTTPS base URL in OAuth mode | app should refuse to start the remote helper and Settings should explain why localhost cannot satisfy OAuth discovery | existing runtime guard + settings copy |
| public URL or tunnel changes after app creation | treat as a user-facing stale-app problem; reset local state if needed, then recreate the ChatGPT app against the new URL | manual recovery path only; not hidden as a server bug |
| no proven remote success yet | stay at `Running` instead of `Connected` until Backtick has observed a successful protected remote `/mcp` call | local runtime signal + regression |
| access token expires during a healthy session | expired bearer should fail, refresh should recover, and the same app should keep working | short-TTL regression + stress harness |
| Mac sleep / wake or tunnel suspension | reconnect path must be explicit instead of silently pretending the connector is still healthy | wake/foreground local recheck + public probe landed; long-duration dogfood and automation later |

ChatGPT connector UX rule:

- users should only need to understand the current state, why it is blocked in one sentence, and which single action to take next
- the Settings surface should not expose raw OAuth jargon, helper internals, or debug telemetry by default
- internal failure classes can stay detailed in code/tests, but the user-facing state vocabulary should remain intentionally small
- if a diagnostic element does not change the user's next action, it should stay out of the default connector UI

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
- the local server self-test now uses the exact client-configured launch command from Settings instead of assuming the current app helper path
- the current validation floor is `initialize` plus `tools/list`; this is setup validation, not yet a full `Verified locally` contract
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
  - current validation is a Backtick-owned local self-test of the exact configured launch command plus the MCP tool surface
  - follow-up contract: only call a connector `Verified locally` after `initialize`, `notifications/initialized`, `tools/list`, and one safe read-only `tools/call` succeed
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
6. Keep `AI Export Tail / Prompt Suffix` regression coverage green and documented as landed
7. Keep long-card overflow and click-to-expand regression coverage green and documented as landed
8. Resume grouped export validation against target paste destinations
9. Run `DP1` capture elevation and `DP2` stack brightness in bounded parallel tracks
10. Keep semantic token changes master-owned while capture/stack recipe changes land through review packets
11. Keep `scripts/record_stack_open_trace.sh` in the regression loop whenever stack backdrop, card chrome, panel animation, or windowing behavior changes land

Guardrail:

- do not accept work that turns Backtick into a general note app
- prefer raw dump in Capture and structured compression/export in Stack
- do not accept design-system cleanup that collapses stack backdrop, stack card, or capture runtime ownership into one generic abstraction
- do not accept visual polish that ships without light/dark before-after review artifacts
