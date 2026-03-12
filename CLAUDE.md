# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Brand Context

- User-facing product name: **Backtick**
- Code-level names (`PromptCue`, `PromptCueCore`) are temporary technical identifiers, not product-direction cues
- Interaction model: Capture = frictionless dump, Stack = execution queue, AI compression happens in Stack not Capture

## Build & Test Commands

```bash
# Regenerate Xcode project (required after any project.yml change)
xcodegen generate

# Run pure-logic package tests (fast, no Xcode required)
swift test

# Run a single core test (by name filter)
swift test --filter PromptCueCoreTests.ContentClassifierTests

# Build app target (no signing)
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build

# Run app-target tests
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test

# Run a single app-target test (by class or method)
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PromptCueTests/CardStoreTests

# Run BacktickMCP server tests
swift test --filter BacktickMCPServerTests

# Validate design tokens
python3 scripts/validate_ui_tokens.py
```

**Minimum verification for any change:** `swift test` + `xcodegen generate`. Add `xcodebuild build` when touching app-target code.

### Build Configurations

- **Debug** — used for tests (`CODE_SIGNING_ALLOWED=NO`)
- **DevSigned** — used for `run` scheme (local dev signing via `scripts/sign_dev_app.sh`)
- **Release** — production builds

### QA Environment Flags

```bash
PROMPTCUE_OPEN_CAPTURE_ON_START=1      # auto-open capture panel
PROMPTCUE_OPEN_STACK_ON_START=1        # auto-open stack panel
PROMPTCUE_OPEN_DESIGN_SYSTEM=1         # open design system preview
PROMPTCUE_QA_DRAFT_TEXT=<text>         # seed draft text
PROMPTCUE_LOG_EDITOR_METRICS=1         # log editor metrics to stderr
```

## Architecture

Backtick (PromptCue) is a macOS menu-bar utility (LSUIElement) for capturing and organizing prompt snippets. Built with SwiftUI views hosted in AppKit NSPanels.

### Three-target structure

- **`Sources/PromptCueCore/`** — Pure Swift package (swift-tools-version 6.0). Domain models (`CaptureCard`, `CaptureDraft`), formatting, ordering logic. No AppKit/SwiftUI. Tested via `swift test` (`Tests/PromptCueCoreTests/`).
- **`PromptCue/`** — macOS app target. Services, UI, window controllers. Tested via xcodebuild (`PromptCueTests/`).
- **`Sources/BacktickMCP/` + `Sources/BacktickMCPServer/`** — MCP server executable exposing the Stack database via JSON-RPC 2.0 (list/get/create/update/delete notes, mark executed). Bundled into the app by post-build script (`scripts/build_backtick_mcp_helper.sh`). Tested via `swift test --filter BacktickMCPServerTests`.

Move logic to `PromptCueCore` early if it has no platform dependency.

### App lifecycle

`AppDelegate` → `AppCoordinator` (owns panels, hotkeys, status item, model) → `AppModel` (@MainActor ObservableObject, single source of truth for all shared state).

NSWindowController subclasses (`CapturePanelController`, `StackPanelController`) manage NSPanel lifecycle. SwiftUI views receive `AppModel` via `@ObservedObject`.

### Key patterns

- **Immutability**: Domain models return new values (`markCopied()`, `updatingSortOrder()`), never mutate in place
- **Protocol-driven services**: `RecentScreenshotCoordinating`, `AttachmentStoring`, `RecentScreenshotObserving` for testability
- **`@MainActor` everywhere** in app target; `Sendable` on all domain models
- **State machines via enums**: e.g. `RecentScreenshotState` (`.idle` → `.detected` → `.previewReady` → `.consumed`/`.expired`)
- **Test module name**: `@testable import Prompt_Cue` (space maps to underscore)
- **Test helpers**: `drainMainQueue()` runs `RunLoop.main.run(until:)` to settle async state

### Design system (two-layer tokens)

All colors, spacing, radius, fonts, shadows must go through the token system — never hardcode values in component bodies.

- `PrimitiveTokens.swift` — Raw values: `FontSize`, `LineHeight`, `Space`, `Radius`, `Shadow`, etc.
- `SemanticTokens.swift` — Role-based, adaptive light/dark: `Surface`, `Text`, `Border`, `Accent`, `Shadow`, `MaterialStyle`

### Dependencies

| Package | Version | Purpose |
|---|---|---|
| GRDB.swift | 7.8.0 | SQLite persistence |
| KeyboardShortcuts | 2.3.0 | Global hotkey registration |

### Storage

SQLite via GRDB at `~/Library/Application Support/PromptCue/PromptCue.sqlite`. Default card TTL = 8 hours.

## Project Configuration

- **Source of truth**: `project.yml` (XcodeGen) — never hand-edit `project.pbxproj`
- **Bundle ID**: `com.promptcue.promptcue`
- **Deployment target**: macOS 14.0
- **Default shortcuts**: `Cmd + backtick` = Quick Capture, `Cmd + 2` = Toggle Stack

### Key scripts

| Script | Purpose |
|---|---|
| `scripts/build_backtick_mcp_helper.sh` | Post-build: compile and bundle BacktickMCP into app |
| `scripts/sign_dev_app.sh` | Post-build: apply dev code signing for local runs |
| `scripts/validate_ui_tokens.py` | Verify token system consistency |
| `scripts/qa_capture_input.sh` | Simulate capture panel input for QA |

## Critical Rules

1. Run `xcodegen generate` after changing `project.yml` — never hand-edit `.pbxproj`
2. File ownership: `AppCoordinator.swift`, `AppDelegate.swift`, `PromptCueApp.swift`, `project.yml`, `docs/Master-Board.md` require master review before editing
3. UI subtraction test: if a capture UI element can be removed and capture still works, remove it
4. All UI values must flow through `PrimitiveTokens` → `SemanticTokens` — no hardcoded colors, spacing, radius, fonts, or shadows
5. See `AGENTS.md` for multi-agent coordination rules, file ownership guidance, and planning discipline
