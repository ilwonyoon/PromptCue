# Backtick Engineering Preflight

## Purpose

This document defines the setup and release baseline that should be in place before Backtick moves into full implementation. The goal is to avoid late-stage churn around signing, permissions, packaging, and distribution.

Backtick is a native macOS utility app with:

- user-facing name: `Backtick`
- code-facing app target name: `PromptCue`
- code-facing core module name: `PromptCueCore`
- primary release lane: direct distribution through Gumroad
- secondary release lane: Mac App Store compatibility later

For now, keep `PromptCue` and `PromptCueCore` as technical names in the repo and Xcode project. Product and planning language should use `Backtick`.

## 1. Product And Platform Baseline

### Product Shape

- Standard macOS utility app, not a macOS App Extension
- `LSUIElement` background utility app with menu bar presence
- SwiftUI for view composition
- AppKit for panel windowing, focus behavior, and system integration

### UX Baseline

- `Cmd + \`` opens quick capture by default
- `Cmd + 2` opens the stack panel by default
- both shortcuts are user-configurable in Settings
- `Enter` saves
- `Esc` dismisses
- One card equals one thought
- Capture is a frictionless dump, not a note editor
- Stack is an execution queue, not an archive
- AI compression happens in Stack, not in Capture
- Export is clipboard-first, not terminal-integrated

## 2. Repository And Project Setup

### Project Structure

- `project.yml`
  - XcodeGen source of truth for the app project
- `PromptCue/`
  - app target code
- `Sources/PromptCueCore/`
  - pure business logic used by tests and later shared by the app
- `Tests/PromptCueCoreTests/`
  - package-level automated tests
- `docs/`
  - product, implementation, release, and operational docs

### Tooling Baseline

- `XcodeGen`
  - generate the Xcode project deterministically
- `Swift Package Manager`
  - manage package dependencies and testable core modules
- `swift test`
  - fast feedback loop for business logic
- `xcodebuild`
  - app target build verification

### Recommended Near-Term Additions

- `xcconfig` files for environment separation
- `swift-format` or `SwiftLint`
- a simple `Makefile` or `justfile` for repeatable build/test/release commands

## 3. Naming And Identifier Setup

### Naming Rules

- Product name: `Backtick`
- App target: `PromptCue`
- Core package: `PromptCueCore`
- Bundle identifiers should be stable and lowercase

### Recommended Bundle IDs

- main app: `com.promptcue.promptcue`
- login item helper, if added later: `com.promptcue.promptcue.launcher`
- App Store SKU and Gumroad listing names should use `Backtick`

### Versioning

- semantic marketing version, for example `0.1.0`
- monotonically increasing build number
- keep direct-distribution and App Store lanes on the same app version scheme, even if they ship at different times

## 4. Signing, Certificates, And Team Setup

### Apple Developer Setup

- Apple Developer Program enrollment
- confirmed Team ID
- App IDs created in Apple Developer portal
- signing certificates available on the release machine or CI

### Direct Distribution Requirements

- `Developer ID Application` certificate
- notarization credentials
  - App Store Connect API key is preferred over app-specific password
- code signing verification built into release scripts

### App Store Requirements

- `Mac App Store` signing identity
- sandbox-compatible entitlements
- App Store Connect record and metadata

### Secrets Handling

- never commit certificates, `.p12` files, private keys, or notarization tokens
- store CI secrets in GitHub Actions secrets or a local secure store
- document who owns release credentials

## 5. Build Configuration Strategy

### Recommended Config Split

- `Debug`
  - local development
  - verbose logging enabled
- `DevSigned`
  - stable signed local runs
  - near-production local QA and TCC smoke
- `Release`
  - signed and notarized distribution build
- optional `AppStore`
  - separate configuration if sandbox behavior diverges

### Recommended `xcconfig` Files

- `Config/Base.xcconfig`
- `Config/Debug.xcconfig`
- `Config/DevSigned.xcconfig`
- `Config/Release.xcconfig`
- `Config/AppStore.xcconfig`

### Things To Define In Config

- bundle identifier suffixes if needed
- app category
- logging flags
- update feed URL for direct distribution
- feature flags for licensing or `DevSigned`-only diagnostics

## 6. Entitlements And Permission Planning

### Direct Distribution Baseline

- no sandbox by default unless a strong reason appears
- use standard file access and user-selected folder behavior for screenshot ingestion
- login item entitlement only if the helper path is used

### App Store Baseline

- App Sandbox enabled
- user-selected read-only or read-write file access, depending on final screenshot flow
- security-scoped bookmark persistence for the screenshot folder
- any background behavior must remain within MAS policy

### Entitlement Strategy

Keep two entitlement lanes in mind from day one:

- direct lane
  - optimize for fewer restrictions and faster iteration
- App Store lane
  - optimize for explicit permissions and sandbox-safe file access

Do not let direct-distribution shortcuts make the app architecture impossible to sandbox later.

## 7. Screenshot Folder And Bookmark Strategy

### Required Behavior

- user chooses the screenshot folder explicitly
- app stores a security-scoped bookmark
- app rehydrates bookmark on launch
- app watches the folder and checks the newest eligible screenshot on capture open

### Why This Matters

- it keeps behavior understandable
- it works for future App Store compatibility
- it avoids hidden scanning of user files

### Implementation Notes

- store bookmark data in Application Support or user defaults, depending on size and structure
- validate bookmark staleness on launch
- fail safely if bookmark resolution breaks
- surface a clear “Reconnect screenshot folder” state

## 8. Global Hotkey Strategy

### Baseline Decision

- use a native wrapper such as `KeyboardShortcuts` or an equivalent Carbon-backed implementation

### Requirements

- reliable across apps
- minimal permission surprises
- supports two primary shortcuts:
  - quick capture
  - stack panel

### Setup Checklist

- document the default shortcuts and the fact that users can change them in Settings
- allow remapping later, but not in the first implementation slice
- verify behavior with common developer tools:
  - Terminal
  - iTerm2
  - Cursor
  - Chrome
  - Xcode

## 9. Panel And Window Behavior Spec

### Capture Panel

- opens near instantly
- small footprint
- keyboard focus lands in the input field
- `Enter` submits
- `Esc` dismisses
- optionally shows a pending screenshot thumbnail
- behaves like a fast scratchpad entry point, not like a composed note surface

### Stack Panel

- anchored to the right side
- consistent width
- newest cards first
- card click updates the grouped copy payload immediately
- grouped selection should not feel modal or heavy
- the stack should stay open while grouped copy is being assembled
- acts as the execution queue where selection, export grouping, and AI compression can happen

### Windowing Checklist

- decide whether the panel activates the app or behaves as a utility overlay
- verify space/full-screen behavior
- verify multi-monitor behavior
- verify z-order when other apps are frontmost
- verify panel dismissal on outside click if desired

## 10. Local Storage And Data Lifecycle

### Recommended Storage

- `SQLite + GRDB`

### Why

- migrations are explicit
- attachment metadata is easier to manage than with ad hoc JSON growth
- TTL cleanup and future search/indexing stay possible without a rewrite

### Data Domains

- cards
- screenshot attachment records
- settings
- bookmark metadata
- future telemetry counters, if added locally

### Attachment Policy

- import selected screenshots into app-managed storage
- do not depend on external file paths after save
- remove imported attachments when cards expire or are deleted

## 11. Logging And Diagnostics

### Logging Baseline

- use `os.Logger`
- categories:
  - `app`
  - `hotkey`
  - `storage`
  - `screenshot`
  - `windowing`
  - `release`

### What To Log

- hotkey registration success or failure
- bookmark resolution failures
- persistence migration failures
- TTL cleanup events
- panel open/close anomalies

### What Not To Log

- raw card text by default
- screenshot contents
- personally sensitive local file paths beyond what is operationally necessary

## 12. Testing Automation Setup

### Current Baseline

- package-level core logic target: `PromptCueCore`
- package tests: `PromptCueCoreTests`
- GitHub Actions workflow runs `swift test` on macOS

### Required Next Layer

- add `xcodebuild` app-target build validation
- add core service unit tests once storage and watcher logic move into shared testable modules
- add smoke-style app tests for:
  - launch
  - capture flow
  - stack open
  - relaunch persistence

### Test Pyramid For Backtick

- package tests
  - draft validation
  - export formatting
  - TTL rules
  - attachment metadata
- service tests
  - storage
  - migrations
  - bookmark resolution
  - screenshot eligibility logic
- integration and smoke tests
  - hotkeys
  - panel behavior
  - launch-at-login path

## 13. CI Setup

### Minimum CI

- run `swift test` on pull requests
- run `swift test` on pushes to protected branches

### Recommended CI Expansion

- generate Xcode project with `xcodegen generate`
- run `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug build`
- archive release candidates on tags
- lint release artifacts before upload

## 14. Direct Distribution Strategy

### Primary Lane

- Gumroad storefront
- downloadable DMG containing the signed and notarized app

### Release Artifact Checklist

- versioned app bundle
- signed app
- notarized app
- stapled ticket
- versioned DMG
- checksum file
- release notes

### Recommended User Delivery

- Gumroad product page
- DMG download after purchase or for free checkout
- concise install instructions
- changelog or release notes link

## 15. DMG Packaging Checklist

### DMG Expectations

- app icon and branding match Backtick
- `/Applications` shortcut included
- drag-to-install layout is obvious
- background is lightweight and not distracting
- volume name includes app name and version

### Technical Checklist

- build signed `.app`
- notarize `.app`
- staple notarization
- package DMG
- verify DMG on a clean machine
- verify Gatekeeper prompt behavior

### Recommended Tooling

- `create-dmg` or a custom `hdiutil` script
- release script should be deterministic and version-aware

## 16. Gumroad Sales Considerations

### Early Recommendation

Start simple:

- free or paid download
- no account requirement inside the app
- no blocking license enforcement in v1

### Why

- Backtick is a utility tool
- friction at install or launch directly fights the product promise
- early users are better served by easy access than DRM

### If Paid Enforcement Is Added Later

- keep activation optional for free tier or trial
- do not block local notes if a network check fails
- separate storefront logic from app core
- never tie core capture reliability to license validation latency

## 17. App Store Compatibility Strategy

### Treat As A Separate Lane

The App Store should not be the first ship target for Backtick. It should be planned as a compatibility lane with its own acceptance checklist.

### Main Constraint Areas

- App Sandbox
- screenshot folder access
- bookmark persistence
- helper or login item setup
- update path changes because `Sparkle` is not used for MAS

### MAS Readiness Checklist

- entitlement set reviewed
- screenshot flow proven with user-selected folder access
- no assumptions about unrestricted filesystem reads
- startup behavior compliant with MAS rules
- release pipeline can produce MAS-signed builds separately

## 18. Sparkle And Updates

### Direct Distribution

- `Sparkle` is a good later addition once release cadence justifies it
- wire it only after signing and notarization are already reliable

### App Store

- no `Sparkle`
- updates come through the App Store

## 19. Release Ownership

### Suggested Owners

- product/architecture
  - naming
  - UX contract
  - distribution decisions
- platform owner
  - hotkeys
  - entitlements
  - bookmark flow
  - launch-at-login
- release owner
  - certificates
  - notarization
  - DMG packaging
  - Gumroad upload checklist
- test owner
  - CI
  - smoke checks
  - regression gates

## 20. Pre-Implementation Checklist

Before serious feature implementation, confirm all of the following:

- app name is `Backtick` everywhere user-facing
- bundle identifier strategy is locked
- Apple team and signing identities are available
- XcodeGen is the source of truth for project generation
- direct-distribution lane is the default release lane
- App Store lane is documented as a later compatibility target
- screenshot folder permission flow is designed
- bookmark persistence strategy is designed
- global hotkey approach is selected
- panel behavior checklist is written down
- `SQLite + GRDB` is the chosen storage path
- logging categories are defined
- package tests and CI are green
- release secrets storage plan is documented
- DMG packaging plan exists
- Gumroad listing and asset requirements are listed

## 21. Immediate Next Actions

1. Add `xcconfig` environment files and release-oriented build settings.
2. Generate the Xcode project from `project.yml` and confirm the renamed `PromptCue` target.
3. Continue moving shared pure app logic toward `PromptCueCore` so tests cover real code, not duplicated code.
4. Add `xcodebuild` build verification to CI.
5. Draft release scripts for signing, notarization, and DMG creation before beta distribution starts.
