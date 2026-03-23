# Backtick Execution PRD

## Overview

Backtick is a native macOS utility app for developers working in AI-assisted coding loops. It is an AI coding scratchpad and thought staging tool: capture what you notice now, stage it for action, then let it disappear.

This document updates the product concept into an implementation-ready PRD. The product definition is explicit:

- user-facing product name: `Backtick`
- current repository and code-facing names may still use `PromptCue`
- product shape: background macOS utility
- product category: AI coding scratchpad / thought staging tool
- not a note-taking app
- not a macOS App Extension

Core product line:

- `Capture now. Act today. Forget tomorrow.`

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
3. The product is ephemeral by design, not archival.
4. The interface should feel invisible until summoned.
5. Native macOS behavior is more important than cross-platform reuse.
6. Capture mode is for frictionless thought dumping, not polishing.
7. Stack mode is for execution: compress thoughts into tasks, prompts, and next actions.
8. AI belongs in Stack, not Capture.
9. The product should help users act today and forget tomorrow.

## Product Identity

Backtick is not a notebook and not a personal knowledge base.

Backtick is:

- a fast scratchpad for AI-assisted coding work
- a staging surface between noticing something and telling the AI what to do next
- a temporary execution aid for prompts, bugs, tasks, and follow-ups

Backtick is not:

- a note archive
- a writing tool
- a documentation tool
- a task manager with long-lived structure

The mental model stays simple:

- `Capture mode`: dump the thought now
- `Stack mode`: decide what to do with it
- then let old material disappear

## Architecture Decision

### Locked Decision

Backtick will be built as a native macOS utility app using a `SwiftUI + AppKit hybrid` stack.

### What It Is

- A standard macOS app process
- Runs as an `LSUIElement` background utility
- Uses a status item for discoverability and fallback access
- Uses floating panels for quick capture and review/export

### What It Is Not

- Not a macOS App Extension
- Not a Flutter-first desktop shell
- Not a general-purpose note-taking app
- Not a long-term memory product

### Why Not App Extension

The product needs a persistent process, global shortcuts, local persistence, menu bar presence, and custom floating UI over other apps. That behavior matches a standard utility app, not Apple’s extension model.

### Why Not Flutter-First

Flutter can ship a macOS desktop app, but Backtick's hardest problems are macOS-native:

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

## Mode Definitions

### Capture Mode

Capture mode is a frictionless thought dump.

Rules:

- open instantly
- type immediately
- do not ask the user to organize
- do not ask the user to think in prompt structure yet
- avoid AI behavior, summarization, or transformation inside capture

Capture mode should feel like:

- a temporary mental landing pad
- one fast thought at a time
- low-chrome and low-commitment

### Stack Mode

Stack mode is an execution queue.

Rules:

- turn raw observations into the next useful export
- support compression into tasks, prompts, grouped clipboard payloads, and action bundles
- allow users to review, prioritize, copy, and discard
- this is the right place for AI-adjacent assistance, formatting, and export shaping

Principle:

- AI belongs in Stack, not Capture

### Long Card Rule

Stack cards should remain scannable even when the saved text is unusually long.

Rules:

- default card height must be capped
- very long cards should not blow out the stack layout
- overflow should remain understandable
- users should be able to read the full card on demand without turning Stack into a document reader
- copied-stack summaries should obey the same overflow rules and stay visually stable
- Stack must use its own resting long-text cap instead of reusing Capture editor height
- active Stack cards should collapse once body text exceeds the resting scan limit, then expose `+N lines`
- the resting scan limit should be line-based so future Capture sizing changes do not silently change Stack behavior

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
- Local-only storage with optional automatic expiration
- Capture mode remains raw and unstructured
- Stack mode remains the place where export shaping happens
- Stack cards cap default height and expose overflow deliberately instead of expanding without limit

### Post-MVP

- Configurable screenshot folder
- Configurable auto-expiration
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
- Long-term note retention or archival organization

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
- Retention is user-controlled; auto-expiration is available but disabled by default
- Sensitive behavior should be surfaced in settings, not hidden
- Temporary material should be easy to forget and safe to discard

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
- Evidence that capture stays raw while Stack drives action

## MVP Acceptance Criteria

- User can summon capture with the configured global shortcut from any normal working context.
- User can type a note and save it in under 2 seconds.
- User can summon the stack with the configured global shortcut and see newest cards first.
- User can click a card to copy it immediately.
- User can select multiple cards and copy a grouped payload.
- When auto-expiration is enabled, cards expire automatically after the configured TTL without manual cleanup.
- Screenshot attachment behavior is deterministic and understandable.
- Capture mode does not require titles, tags, folders, or prompt formatting.
- Stack mode is the place where saved thoughts become exportable execution material.
- Very long cards do not break stack layout; overflow remains readable and discoverable.

## Connector Verification Contract

For Settings-based MCP connectors, product status must separate `Configured`, `Connected`, and `Needs attention` where useful.

- `Configured` means Backtick found a client config entry that points that client at a Backtick MCP launch command.
- `Connected` means Backtick has proof that the relevant client path is actually working now.
  - For stdio clients, that requires actual client proof, not only a local helper launch or `tools/list`.
  - For ChatGPT remote, that remains surface-specific and requires a real protected `tools/call` from that surface.
- `Needs attention` means a configured or previously connected path is stale, unreachable, or otherwise needs user action.
- Settings must not imply a connector is connected based only on config presence, process launch, or `tools/list`.
- Settings must not imply client-specific approval or automation flows are proven unless those flows were actually exercised from that client or surface.

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
