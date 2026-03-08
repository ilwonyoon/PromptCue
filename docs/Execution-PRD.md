# Prompt Cue Execution PRD

## Overview

Prompt Cue is a native macOS utility app for developers working in AI-assisted coding loops. It provides a frictionless buffer for capturing thoughts while an LLM is working, then exporting those thoughts into the next prompt with minimal interruption.

This document updates the product concept into an implementation-ready PRD. The core product remains the same, but the delivery shape is now explicit: Prompt Cue is a background macOS utility, not a note app, and not a macOS App Extension.

## Target User And Job To Be Done

### Primary User

- Developers who spend long stretches in Cursor, Claude Code, Copilot, terminals, browsers, and local apps while an AI agent is generating or modifying code

### Core Job

- “While the AI is busy, give me the fastest possible way to capture what I notice, then let me paste it into the next prompt without losing flow.”

### User Conditions

- Multiple app contexts open at once
- Frequent prompt-test-prompt cycles
- High volume of small bugs, ideas, and follow-up notes
- Low tolerance for organizational overhead

## Product Principles

1. Capture friction must be near zero.
2. Export friction must be near zero.
3. The product is ephemeral, not archival.
4. The interface should feel invisible until summoned.
5. Native macOS behavior is more important than cross-platform reuse.

## Architecture Decision

### Locked Decision

Prompt Cue will be built as a native macOS utility app using a `SwiftUI + AppKit hybrid` stack.

### What It Is

- A standard macOS app process
- Runs as an `LSUIElement` background utility
- Uses a status item for discoverability and fallback access
- Uses floating panels for quick capture and review/export

### What It Is Not

- Not a macOS App Extension
- Not a Flutter-first desktop shell
- Not a general-purpose note-taking app

### Why Not App Extension

The product needs a persistent process, global shortcuts, local persistence, menu bar presence, and custom floating UI over other apps. That behavior matches a standard utility app, not Apple’s extension model.

### Why Not Flutter-First

Flutter can ship a macOS desktop app, but Prompt Cue's hardest problems are macOS-native:

- global shortcuts
- panel window behavior
- status item integration
- screenshot folder access
- startup behavior
- sandbox and permission edge cases

For this product, long-term maintainability is better when those concerns live directly in AppKit/Swift rather than through a growing plugin bridge.

## UX Patterns To Adopt

The intended feel is closer to Alfred and Raycast than to Apple Notes.

- Global hotkey is the primary entry point.
- The UI appears over the current context instead of forcing an app switch.
- `Enter` is the main action for capture.
- `Esc` dismisses immediately.
- The review surface is dense, minimal, and keyboard-friendly.
- One card equals one thought.
- Status bar presence is secondary, not primary.
- Privacy-sensitive behavior like screenshot access and retention must be explicit.

## Functional Scope

### MVP

- Quick capture via `Cmd + \`` by default
- Review/export panel via `Cmd + 2` by default
- Both shortcuts are user-configurable in Settings
- One note per card
- Newest-first card stack
- Single-card click-to-copy
- Multi-card selection and grouped clipboard export
- Optional screenshot attachment when a recent screenshot is detected
- Local-only storage with automatic expiration

### Post-MVP

- Configurable screenshot folder
- Configurable TTL
- Launch at login
- Keyboard navigation across cards
- Better copy formatting modes
- Optional pinning

## Non-Goals

- Cloud sync
- AI API integration
- Automatic terminal targeting
- Search-heavy knowledge management
- Project/task management
- Rich document editing
- Cross-platform parity in v1

## Technical Architecture

### App Shell

- `SwiftUI` for view composition
- `AppKit` for system integration and window management
- `NSPanel` for quick capture and right-side stack surfaces
- `NSStatusItem` or equivalent menu bar surface for fallback access

### Recommended Stack

- App shell: `SwiftUI + AppKit hybrid`
- Persistence: `SQLite + GRDB`
- Clipboard: `NSPasteboard`
- Launch at login: `SMAppService`
- Logging: `os.Logger`
- Packaging and updates: signed + notarized direct app, optional `Sparkle` later
- Project tooling: `Swift Package Manager` and project generation tooling such as `XcodeGen`

### Core Services

- Global shortcuts routed through a native shortcut layer
- Clipboard export through `NSPasteboard`
- Screenshot discovery via folder-based lookup and watcher logic
- Local persistence through `SQLite + GRDB` in Application Support
- TTL cleanup handled in the data layer so expiration stays consistent across relaunches
- App lifecycle hooks for startup, cleanup, and panel coordination

### Data Model

Each card should minimally contain:

- identifier
- text body
- created timestamp
- optional screenshot attachment reference
- expiration behavior tied to TTL

### Screenshot Attachment Strategy

- On capture open, check the configured screenshot folder for the most recent eligible image.
- If a screenshot is recent enough, show it as a pending attachment in the capture UI.
- On save, import a copy into app-managed storage rather than relying on the original external path.
- Delete imported attachments when the owning card expires.

### Folder Access Model

Screenshot auto-attach must be designed around a user-approved folder. The app should persist access using a security-scoped bookmark so the behavior remains stable across relaunches.

### Recommended Supporting Libraries

- `GRDB` for local persistence and migrations
- `KeyboardShortcuts` or an equivalent native wrapper for global hotkey registration
- `Sparkle` later, only if direct distribution needs in-app updates

## Privacy And Security

- Local-first by default
- No cloud dependency in MVP
- No background scraping of arbitrary folders
- Screenshot access should be folder-scoped and user-controlled
- Retention is intentionally short to reduce sensitive data accumulation
- Sensitive behavior should be surfaced in settings, not hidden

## Distribution Strategy

### Default Path

- Direct download first, with Gumroad as the primary storefront for free or paid distribution
- Ship a signed, notarized `.app` inside a branded `.dmg`
- Signed, notarized macOS app
- Auto-update path can be added later if needed

### Deferred Path

- Mac App Store support is deferred

### Reason

The App Sandbox introduces extra complexity around screenshot folder access and automatic attachment behavior. That is not a good constraint for v1 if the product goal is speed and reliability.

### Commerce And Packaging Notes

- Gumroad requires a predictable downloadable artifact, so release automation should produce a versioned DMG and checksums.
- The DMG should include the app, `/Applications` shortcut, a short install instruction, and brand-safe background/layout polish.
- If license enforcement is added later, it should stay separate from core capture flow so offline usage remains reliable.
- App Store packaging should be treated as a separate release lane because sandbox and entitlement constraints differ materially from direct distribution.

## Success Metrics

### Primary

- Daily captures per active user

### Secondary

- Capture-to-save time under 2 seconds
- Percentage of saved cards later exported to clipboard
- Number of prompt cycles supported per day
- Retention without card accumulation becoming clutter

## MVP Acceptance Criteria

- User can summon capture with the configured global shortcut from any normal working context.
- User can type a note and save it in under 2 seconds.
- User can summon the stack with the configured global shortcut and see newest cards first.
- User can click a card to copy it immediately.
- User can select multiple cards and copy a grouped payload.
- Cards expire automatically after the configured TTL without manual cleanup.
- Screenshot attachment behavior is deterministic and understandable.

## Technical Risks

- Global shortcut behavior can be brittle if implemented with the wrong system approach.
- Floating panel focus behavior can feel wrong if activation rules are not tuned carefully.
- Screenshot auto-attach can become confusing if folder permission and detection rules are vague.
- Direct distribution requires signing, notarization, and update strategy discipline.
- App Store compatibility will require a stricter sandbox story later.

## Decision Log

- `2026-03-07`: Locked product shape as native macOS utility app.
- `2026-03-07`: Rejected App Extension architecture.
- `2026-03-07`: Rejected Flutter-first implementation for v1 and long-term baseline.
- `2026-03-07`: Chose direct distribution as the default release path.
- `2026-03-07`: Made screenshot attachment permission-aware by design.

## References

- Apple App Extension Overview: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html
- Apple MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- Apple macOS App Programming Guide: https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/CoreAppDesign/CoreAppDesign.html
- Apple App Sandbox: https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/
- Apple NSPasteboard: https://developer.apple.com/documentation/appkit/nspasteboard/general
- Apple SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Flutter Desktop Docs: https://docs.flutter.dev/platform-integration/desktop
- Flutter macOS Docs: https://docs.flutter.dev/platform-integration/macos/building
- Raycast Hotkey Manual: https://manual.raycast.com/hotkey
- Raycast Action Panel: https://manual.raycast.com/action-panel
- Alfred General Help: https://www.alfredapp.com/help/general/
- Alfred Clipboard Help: https://www.alfredapp.com/help/features/clipboard/
