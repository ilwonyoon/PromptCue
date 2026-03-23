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
- A dedicated public launch hardening lane is now active at `H0` in `docs/Public-Launch-Hardening-Plan.md`.
- A dedicated pre-DMG launch-readiness review lane now exists in `docs/Launch-Readiness-Review-Plan.md`.
- A current-main-aligned design-system boundary proposal now exists in `docs/Design-System-Architecture-Proposal.md`.
- A design-system execution document now exists in `docs/Design-System-Execution-Plan.md`.
- A bounded capture/stack design-polish plan now exists in `docs/Design-Polish-Execution-Plan.md`.
- `Phase DS1`, `Phase DS2`, and `Phase DS3` are now implemented in the design-system strategy branch, and `Phase DS4` has started where reuse is already proven.
- a dedicated performance remediation lane now exists in `docs/Performance-Remediation-Plan.md`
- a dedicated post-launch capture-runtime follow-up now exists in `docs/Capture-Runtime-Post-Launch-Plan.md`

## Phase Summary

| Phase | Goal | Status | Notes |
| --- | --- | --- | --- |
| Phase 0 | Research and lock technical direction | Completed | Native macOS direction decided |
| Phase 1 | Foundation and shared contracts | In progress | Early scaffold exists, shared contracts need tightening |
| Phase 2 | Core capture flow | In progress | Services, panels, and capture UI skeleton are implemented |
| Phase 3 | Stack and export UX | In progress | Card stack and copy interactions are implemented, smoke testing pending |
| Phase 4 | Platform and operations hardening | In progress | Settings and screenshot folder access are now implemented |
| Phase 5 | Polish, validation, and release prep | Pending | Final integration phase |
| Phase H | Public launch hardening | In progress | `H0` contract lock is active; master-owned `H1` release work may proceed in parallel, while runtime `H2-H5` merges stay behind the current `safe-main` gate |
| Phase R | Audit remediation and quality closure | In progress | Resolves MVP gaps, privacy model drift, and design-system drift |
| Phase DS1 | Design-system boundary freeze | Completed in strategy branch | Ownership boundaries are now explicit in docs and code comments |
| Phase DS2 | Runtime/value ownership split | Completed in strategy branch | Grouped contracts now back runtime callers; `AppUIConstants` is only a compatibility facade |
| Phase DS3 | Pattern recipe centralization | Completed in strategy branch | Capture shell chrome, stack card chrome, copied-stack recipe, and stack backdrop recipe now live in owner files |
| Phase DS4 | Reusable surface rationalization | In progress in strategy branch | Shared notification-card chrome and top-edge highlight helpers are now extracted where reuse is proven; broader reusable-surface cleanup is still pending |
| Phase DP | Capture and stack design polish | In progress | `DP0` review lock is complete; `DP1` capture elevation and `DP2` stack brightness are now in implementation with review still pending |

## Current Hot Slice

The immediate implementation slice is:

- `MCP platform track: stabilize shipped stdio connectors and the experimental self-hosted ChatGPT remote-MCP path`
- main-product follow-up: close the remaining non-tag `Phase R7` input-system hardening work
- `Phase R7C`, `Phase R8`, and `Phase R9` are already landed on `main`
- in parallel planning/visual lane: `Phase DP0 -> DP4` from `docs/Design-Polish-Execution-Plan.md`

This slice exists because the performance lane is complete, the major Capture/Stack follow-up slices (`R7C`, `R8`, `R9`) are now landed, and the active work has shifted to MCP-platform stabilization plus the remaining `Phase R7` input-system cleanup.

That means current work is prioritized in this order:

1. keep shipped MCP connectors stable for `Claude Desktop`, `Claude Code`, and `Codex`
2. tighten stale-app reset, reconnect, and health UX for the experimental ChatGPT path
3. close the remaining non-tag `Phase R7` input-system follow-up without reopening layout churn
4. keep grouped export validation and broader regression coverage green
5. continue bounded visual/design follow-up without reopening landed overflow/export/tag contracts

Important planning split:

- `Phase R7C`, `Phase R8`, and `Phase R9` are the main product roadmap for Capture and Stack
- MCP platform work is a separate track and should not be described as replacing the main product hot slice
- when the team is actively working on MCP connectors, say so explicitly as `MCP platform track`, not as the product-wide hot slice

Public launch hardening positioning for this same queue:

- `H0` and master-owned `H1` may progress now in parallel because they are docs/config/release-lane work
- runtime `H2-H5` changes do not merge ahead of this `safe-main` slice unless the master agent carves out a narrow hard-blocker patch

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
- suggested-target selector follow-up landed through the v2 subsystem-replacement plan in `docs/Capture-Suggested-Target-Selector-Repair-Plan.md`; selector is fully fixed and current `main` is the accepted baseline
- PR `#50` inline-tag integration is now gated by `docs/PR50-Inline-Tag-Integration-Runbook.md`; merge work must preserve the current selector, keyboard, and theme-sync baseline
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
- `Phase R7C` inline tag hardening is landed on `main`
  - canonical slug parsing is enforced in `CaptureTag`
  - polluted mixed-script tags stay in body text instead of structured `tags`
  - legacy polluted tags are scrubbed before stack display, autocomplete, sync, or MCP output reuse
- `Phase R8` AI Export Tail / Prompt Suffix is landed on `main`
  - Settings persistence, multiline suffix text, export-only append behavior, and clipboard integration are all active
  - stored cards and stack rendering remain suffix-free
- `Phase R9` stack card overflow and click expansion is landed on `main`
  - long cards now rest at a capped height with a `+N lines` affordance
  - click-to-expand works for active stack cards, and copied-stack collapsed summaries stay bounded

### `Phase R7C`: Inline Tag Contract Hardening `Landed On Main`

Inline tags were carved out as a focused sub-slice under `Phase R7` because they touch capture input, stack rendering, persistence, and MCP payload quality at the same time. That hardening work is now landed on `main` and should be treated as the accepted contract for future capture, stack, sync, and MCP changes.

Reason for this slice:

- tags are meant to be lightweight metadata that help MCP clients classify Stack notes more accurately
- the current prototype proved the interaction model, but the storage contract is still too loose
- live diagnosis confirmed the current prototype can persist polluted tags such as `ㅗhello` or `ㅠㅕbug` when input-source noise or IME-adjacent keystrokes are interpreted as valid tag characters
- that pollution is not only a stack-display issue; it also feeds autocomplete, sync, and MCP note payloads

Locked contract for this slice:

- `CaptureCard.text` remains the canonical body text only
- `CaptureCard.tags` remains the canonical structured metadata field that MCP and sync should trust
- only canonical slug tags are allowed into `CaptureCard.tags`
- canonical slug format is `^[a-z][a-z0-9_-]*$`
- non-canonical `#...` tokens stay in body text instead of being promoted into structured tags
- capture preview and stack display may reconstruct `#tag body` for readability, but reconstruction must only use canonical structured tags
- autocomplete must only suggest canonical structured tags that already survived storage rules
- MCP and Cloud sync must never emit or learn from polluted tags that violate the canonical contract

Implementation rules:

1. the editor commit path and the save-time parse path must share the same lexical contract
2. save-time parsing must not be looser than the explicit tag-commit interaction
3. invalid or polluted historical tags must be scrubbed before they continue to feed stack display, autocomplete, or MCP output
4. this slice must preserve Capture as a fast dump and must not turn the panel into a heavy tag-management surface

Required verification for `Phase R7C`:

- English tag commit still works for canonical tags such as `#bug`, `#bug_fix`, and `#proj-alpha`
- mixed-script or IME-noise prefixes such as `#ㅗhello` remain body text and do not populate `tags`
- Korean and other IME composition input survives without disappearing during capture
- Stack reconstructs inline `#tag body` only from canonical `tags`
- MCP note payloads expose only canonical `tags`

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

- `docs/Public-Launch-Hardening-Plan.md`
- `docs/Quality-Remediation-Plan.md`
- `docs/Design-System-Architecture-Proposal.md` for design-system ownership boundaries
- `docs/Design-System-Execution-Plan.md` for phased design-system execution
- `docs/Capture-Runtime-Post-Launch-Plan.md` for the first post-launch structural capture-performance lane

That remediation lane is now authoritative for:

- public launch blocker closure across release lane, permissions, battery wake-up risk, and MAS-later compatibility
- `Phase H` status roll-up, worktree ownership, and launch gates
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

The next main-product remediation work after the current MCP stabilization slice is:

- close the remaining non-tag `Phase R7` input-system follow-up
- keep grouped export validation green across target apps with different text/image paste behavior
- continue the broader stack follow-up under `docs/Stack-Refactor-Execution-Plan.md`
- after the first DMG ship, start the structural capture-runtime lane under `docs/Capture-Runtime-Post-Launch-Plan.md`

Recently landed reference slices:

- `Phase R8: AI Export Tail / Prompt Suffix`
  - shipped as an export-only formatter and Settings feature
  - multiline suffix text is persisted, clipboard/export paths append it only when enabled, and stored cards remain unchanged
- `Phase R9: stack card overflow and click expansion`
  - shipped as a capped resting card height plus `+N lines` affordance
  - clicking the overflow affordance expands active stack cards without introducing inner text scrollers
  - copied-stack collapsed summaries remain bounded and do not expand inline
- follow-up rule locked after ship:
  - Stack long-text collapse is governed by a Stack-specific resting line cap, not by `CaptureRuntimeMetrics.editorMaxHeight`
  - active cards should stay fully visible through the scan band, but once they exceed that Stack cap they should collapse and show `+N lines`
  - copied-stack collapsed summaries remain a stricter bounded summary and do not inherit the active-card cap

Planning note:

- do not reopen `R8` or `R9` as open roadmap slices unless a regression or new scoped follow-up is explicitly approved
- the next new Stack-wide execution plan is the broader refactor track in `docs/Stack-Refactor-Execution-Plan.md`, not a re-do of the landed overflow slice

A bounded follow-up plan for the next stack UX slice now exists in:

- `docs/Stack-Header-Rail-Plan.md`

That document is now the UI child plan under `docs/Stack-Refactor-Execution-Plan.md` and locks the persistent stack header rail, launch-facing queue terminology, stack filtering, active-card TTL ring, and theme-adaptive Backtick logo behavior without reopening the current staged-copy and copied-commit contract.

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

- the actual product need is cross-client `Stack` read/write through MCP from `Claude Desktop`, `Claude Code`, `Codex`, and the experimental self-hosted ChatGPT path
- the intended AI workflow is: read the current Stack, summarize or classify what matters, then write condensed notes back into Backtick through MCP
- repo `docs/` authoring is not the Backtick MCP surface itself; that remains a separate code-agent or manual follow-up after the AI has written the important memory back into `Stack`
- the next memory layer after this Stack-first rollout is reviewed project documents: hours-long Claude Desktop / ChatGPT discussions should not be auto-saved blindly; the default flow should be propose what to keep, let the user confirm, then save reviewed typed docs with flat topic classification instead of raw transcripts
- the concrete next-slice contract for this review-first lane now lives in `docs/MCP-Polish-Plan.md`, and the paired eval runbook now lives in `docs/MCP-Polish-Eval-Plan.md`
- an AI execution step should update copied state on the source Stack notes directly
- intermediate board and work-item layers add complexity without helping the MCP bridge

Execution semantics:

- MCP read:
  expose active and copied Stack notes directly from Stack storage
- MCP write:
  create, update, and delete Stack notes directly
- MCP execute:
  when an agent actually executes a note, mark the source note as copied and record a `CopyEvent`

Primary cross-client outcome:

- `Claude Desktop` and ChatGPT should be able to pull the current note context, summarize key decisions, and save the important result back into Backtick
- `Claude Code` and `Codex` should be able to do the same while also using repo context in the coding environment
- the MCP bridge is therefore a memory and context surface over `Stack`, not a direct repository-document writer

Post-Stack Warm memory follow-on:

- long strategy or research discussions from `Claude Desktop` and ChatGPT should be promoted into reviewed project documents rather than left only in ephemeral Stack notes
- those documents should carry explicit `documentType` metadata plus flat `topic` classification
- initial `documentType` buckets should distinguish durable discussion summaries from decision docs, plans, and reference/context docs
- topic classification stays flat and reusable across sessions; fit into existing topics first, create new topics only when clearly distinct
- when Warm implementation starts, use `docs/MCP-Platform-Expansion-Research.md` as the execution reference and `docs/Mem0-Takeaways-for-Backtick.md` as the filter for what to adopt vs reject
- under classification uncertainty, the safest default is one reviewed `discussion` doc first; extracting separate `decision`, `plan`, or `reference` docs should happen after user confirmation rather than as a silent end-of-thread split
- Warm should also adopt a Muninn-style **server-wide instructions** layer so all clients receive the same default behavior at initialization: project mention → recall first, meaningful wrap-up → ask whether to save to Backtick, never save silently
- user-facing wording should refer to this surface as `Backtick` or `백틱`, not generic "memory", to avoid collision with built-in assistant memory

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
   - show setup and verification state in product language without overstating client-specific success

7. `MCP8` bundled helper packaging
   - ship a launchable `BacktickMCP` helper with release builds
   - keep source-checkout fallback for local development
   - make connector setup usable outside a Swift package checkout

ChatGPT note:

- current landed MCP scope is `Claude Desktop`, `Claude Code`, and `Codex`
- treat ChatGPT as a separate remote-MCP track
- do not assume localhost registration from the Backtick app into ChatGPT
- do not promise write-capable ChatGPT support on `Plus` / `Pro` until OpenAI plan support is verified at implementation time
- the current ChatGPT path on `main` is `experimental self-hosted remote MCP`, not a shipped default connector
- advanced-user assumptions are required: Backtick stays running, the user provides a public HTTPS URL/tunnel, and ChatGPT web completes OAuth approval

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
   - keeps repository-checkout launch commands as the development fallback
- `MCP7` guided setup and validation is on `main`
   - `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`
   - `PromptCue/UI/Settings/PromptCueSettingsView.swift`
   - `PromptCueTests/MCPConnectorSettingsModelTests.swift`
   - explains what Backtick MCP does, shows a concrete setup flow, and runs a local server self-test from Settings
   - validates the exact client-configured launch command instead of only the current app helper path
   - current success floor is local launch plus `initialize` and `tools/list`; this is a setup check, not a full client-side proof
   - includes a Claude-specific automation example for `--permission-mode dontAsk` with explicit `--allowedTools`
- `MCP8` bundled helper packaging is on `main`
   - `project.yml`
   - `PromptCue.xcodeproj/project.pbxproj`
   - `scripts/build_backtick_mcp_helper.sh`
   - `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`
   - `PromptCue/UI/Settings/PromptCueSettingsView.swift`
   - `PromptCueTests/MCPConnectorSettingsModelTests.swift`
   - app builds now copy `BacktickMCP` into `Prompt Cue.app/Contents/Helpers/BacktickMCP`
   - connector setup prefers the bundled helper path when it exists and keeps the repository checkout as the fallback
   - bundled-helper smoke has been rerun against the built app helper for `initialize` and `tools/list`
   - release-path external-client smoke was rerun on merged `main` from a temp directory with no source checkout present
   - `Codex` successfully called `mcp__backtick__list_notes` through the bundled helper
   - `Claude Code` successfully called `mcp__backtick__list_notes` through the bundled helper in `--permission-mode dontAsk` when `--allowedTools` included the Backtick tools
   - `Claude Code` without `--allowedTools` failed with the expected non-interactive permission denial, which remains client setup friction rather than an MCP server failure
- `MCP9` experimental remote ChatGPT connector is on `main`
   - `Sources/BacktickMCPServer/BacktickMCPHTTPServer.swift`
   - `Sources/BacktickMCPServer/BacktickMCPOAuthProvider.swift`
   - `Sources/BacktickMCPServer/BacktickMCPApp.swift`
   - `PromptCue/App/AppCoordinator.swift`
   - `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`
   - `PromptCue/UI/Settings/PromptCueSettingsView.swift`
   - `Tests/BacktickMCPServerTests/BacktickMCPServerTests.swift`
   - Backtick can now expose a local HTTP MCP endpoint while the app is running
   - Settings now supports experimental remote MCP with OAuth mode, public HTTPS URL input, and `ngrok`-guided self-hosted setup
   - OAuth discovery now serves both `/.well-known/oauth-authorization-server` and `/.well-known/openid-configuration`
   - OAuth client/token state now persists across helper restarts so reconnect does not immediately fail with `invalid_client`
   - ChatGPT web connection has been verified through a self-hosted public HTTPS URL with OAuth approval
   - this remains an experimental advanced-user path, not the default shipped connector onboarding

Verification gates run for landed MCP slices:

- `xcodegen generate`
- `swift test`
- `swift test --filter BacktickMCPServerTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/MCPConnectorSettingsModelTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackReadServiceTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackWriteServiceTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/StackExecutionServiceTests`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration DevSigned build`
- `swift run BacktickMCP --database-path <temp-db> --attachments-path <temp-attachments>`
- bundled `Prompt Cue.app/Contents/Helpers/BacktickMCP` smoke for `initialize` and `tools/list`
- `Claude Code` and `Codex` release-path smoke from a temp directory with no source checkout present

Current rollout status:

1. release-path external-client validation is complete on merged `main`
   - `Claude Code` and `Codex` both reached the bundled helper from a temp directory with no source checkout present
   - `Claude Code` in `--permission-mode dontAsk` still requires Backtick tools in `--allowedTools`
   - keep treating `tool permission denied` as client setup friction instead of a Backtick MCP launch failure

Current MCP scope split:

1. shipped on `main`
   - Stack note read/write/execute
   - connector settings for `Claude Desktop`, `Claude Code`, and `Codex`
   - pinned cards as the shipped prompt/context reuse surface
2. experimental on `main`
   - self-hosted ChatGPT remote MCP over HTTP + OAuth
   - requires Backtick to stay running plus a user-provided public HTTPS URL/tunnel
3. not started
   - Warm memory / project documents
   - typed long-form docs with `documentType` + flat topic classification
   - Memory panel and Warm MCP tools

Current MCP platform queue:

1. keep the shipped stdio connector surface stable for `Claude Desktop`, `Claude Code`, and `Codex`
2. tighten shipped stdio verification semantics so `Connected` requires actual client proof, not just config detection or `tools/list`; keep the local protocol-correct probe as a health check and detail signal
3. the stdio verification probe should run:
   - exact configured launch command
   - `initialize`
   - `notifications/initialized`
   - `tools/list`
   - one safe read-only `tools/call`
4. the first safe stdio verification probe should use a read-only Backtick tool with no user-data mutation in temp storage; `get_started` is the current preferred candidate
5. keep Settings wording split between `Configured`, `Connected`, and `Needs attention`; do not imply Claude/Codex approval or automation success unless that exact client path ran
6. keep ChatGPT remote MCP clearly labeled as `experimental self-hosted`
7. tighten reconnect/reset/health UX for stale ChatGPT apps and OAuth state, but keep the user-visible surface limited to current state, one-line reason, and one next action; then freeze a named failure matrix with repeatable stress coverage
8. treat `Connected` as a stronger state than `Running`: only show it after Backtick has observed at least one successful protected remote `tools/call` from the current ChatGPT app setup, and keep the state surface-specific (`Connected on Web`, `Connected on macOS`)
9. add a short access-token TTL lane so expiry + refresh recovery can be verified deterministically instead of waiting an hour to discover the connector fell over
10. keep the minimal sleep/wake and tunnel-drift lane in place now: recheck local helper health on foreground / wake, and surface a single recovery state if the local or public endpoint stops responding; leave deeper automation and long-duration dogfooding for follow-up
11. do not let MCP work silently replace the remaining main product roadmap now that `R7C`, `R8`, and `R9` are already landed on `main`
12. lock the post-launch Warm memory contract so long Claude Desktop / ChatGPT discussions save into reviewed project documents with explicit `documentType` plus topic classification
13. keep ChatGPT on the advanced-user self-hosted track; do not open a hosted relay / managed distribution plan in the active roadmap
14. when Warm work starts, follow `docs/MCP-Platform-Expansion-Research.md` for the MCP tool surface and `docs/Mem0-Takeaways-for-Backtick.md` for scope control
15. the first Warm slice should stay minimal: `ProjectDocument` storage, two-tier retrieval (`list_documents` as lean discovery, `recall_document` as full recall), proactive tool descriptions, and human-reviewed Hot -> Warm promotion; do not jump to hybrid search, graph memory, or Backtick-owned inference

ChatGPT remote MCP reliability matrix:

| Failure class | Trigger | Required behavior | Coverage target |
| --- | --- | --- | --- |
| stale ChatGPT OAuth grant | ChatGPT keeps an older refresh token or dynamic client registration after Backtick state changes | Backtick exposes one reset path locally and tells the user to delete and recreate the ChatGPT app instead of implying a server outage | Settings reconnect UX + deterministic stale-grant regression |
| helper restart with persisted OAuth state | Backtick app restarts, helper is relaunched, or helper is killed and restarted | persisted dynamic client registration plus refresh-token flow still work without requiring a brand new authorization roundtrip | package regression + local stress harness |
| authorization code reuse | client retries a code exchange with a code that was already consumed | token endpoint rejects the second exchange with `invalid_grant` | package regression + local stress harness |
| invalid refresh token | client presents a bogus or stale refresh token | token endpoint rejects with `invalid_grant`; logs and UI should point to stale-app recovery rather than generic MCP failure | package regression + local stress harness |
| missing or invalid bearer token | client calls `/mcp` without a valid access token | helper returns `401` consistently | package regression + local stress harness |
| bad OAuth discovery base URL | OAuth mode is enabled with no valid public HTTPS base URL | app refuses to start remote helper and Settings explains why localhost is insufficient for ChatGPT OAuth discovery | runtime guard + Settings copy |
| public URL changed after app creation | ngrok domain / tunnel target changes while ChatGPT still holds the older connector URL | treat as a stale-app configuration problem and tell the user to recreate the ChatGPT app against the new URL | manual recovery flow, explicitly documented |
| no proven remote success yet | local helper is healthy, but ChatGPT has not actually completed a protected `tools/call` with the current app setup | keep the state at `Running`, not `Connected`, until Backtick sees a successful protected remote call from that surface | local runtime signal + targeted app/model regression |
| access token expires during a healthy session | time passes after the first successful setup and the current access token is no longer valid | old bearer token should fail with `401`, refresh should issue a new access token, and `/mcp` should recover without recreating the ChatGPT app | short-TTL regression + stress harness lane |
| Mac sleep / wake or tunnel suspension | app stays configured but the machine sleeps, wakes, or the tunnel briefly disappears | Backtick should re-evaluate helper/tunnel state and return to a single recovery path instead of silently pretending the connector is still healthy | wake/foreground local recheck + public probe landed; long-duration dogfood and deeper automation remain follow-up |

Reliability rule for this slice:

- do not treat ChatGPT remote MCP as "working" based only on one happy-path authorization
- do not treat ChatGPT remote MCP as `Connected` until the current ChatGPT app has actually completed a protected remote `tools/call` request
- every change in the experimental ChatGPT lane must be judged against the matrix above
- deterministic local stress coverage should exist for every failure class that does not require a third-party UI or an actual tunnel swap
- the local reliability lane for this matrix lives in `scripts/run_chatgpt_mcp_stress.sh`

User-facing UX rule for this slice:

- the connector surface should tell the user only three things: current state, one-line reason, and the next action
- each failure state should collapse to one primary recovery action instead of exposing multiple competing choices
- raw OAuth terms such as `invalid_grant`, refresh-token mismatch, discovery mismatch, or helper restart details belong to logs/tests, not the default Settings surface
- always-visible diagnostic rows are only allowed if they directly change the user's next action
- internal failure classes may expand in code and tests, but the visible state vocabulary should stay small and stable

Over-engineering guardrail for this slice:

- do not build a full diagnostics dashboard for an advanced-user connector
- do not surface helper PIDs, token timestamps, raw error payloads, or multi-row health telemetry in the default UI
- if a new status row does not shorten recovery time for a real failure, keep it out
- solve most reliability complexity in the state machine, stress harness, and recovery mapping rather than in persistent UI chrome

Why this rollout is required:

- transport alone is not enough user value if the user does not know how to attach `Claude Code` or `Codex`
- MCP is a connector feature from the user point of view, not just a local executable
- user-facing value is not just connection status; it is letting `Claude Desktop` or ChatGPT pull the important notes, summarize what matters, and write the distilled result back into Backtick
- the same surface should later support promoting multi-hour AI discussions into durable typed project documents, not just short-lived Stack notes
- prompt reuse is already partially solved in the shipped product through pinned cards; do not mix that shipped surface up with the not-yet-started Warm document model
- ChatGPT distribution remains intentionally narrow: advanced-user self-hosted only
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
| Decide update strategy and wire `Sparkle` if shipping direct | Release lead | Distribution decision | Yes | Auto-update path is documented or implemented | In progress via `docs/Sparkle-Integration-Plan.md`; runtime adoption deferred |
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
