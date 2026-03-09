# macOS Structural Audit

> Generated: 2026-03-09
> Scope: Full codebase structural analysis from macOS platform perspective

---

## Overview

Prompt Cue is a macOS menu-bar utility (LSUIElement) for capturing and organizing prompt snippets. Built with SwiftUI views hosted in AppKit NSPanels.

Architecture: `AppDelegate` → `AppCoordinator` → `AppModel` (@MainActor ObservableObject). Pure business logic isolated in `PromptCueCore` Swift Package.

---

## CRITICAL — Immediate Fix Required

### C-1. File Descriptor Leak in RecentScreenshotFileWatcher

**Location:** `RecentScreenshotDirectoryObserver.swift:164-197`

`open()` acquires fd, but if `DispatchSource.makeFileSystemObjectSource()` fails, the fd is never closed. `setCancelHandler` (which calls `close(fd)`) only runs if the source was successfully created.

**Fix:** Close fd in a guard/failure path before returning nil from init.

---

### C-2. Security-Scoped Resource Guard Missing

**Location:** `RecentScreenshotDirectoryObserver.swift:70-88`

`startAccessingSecurityScopedResource()` return value is stored but not guarded. If it returns `false`, the watcher is still created — violating sandbox expectations.

**Fix:** Guard on the return value; bail out and nil the directory URL on failure.

---

### C-3. Database Save Not Atomic

**Location:** `CardStore.swift:105-108`

`CardRecord.deleteAll()` followed by individual inserts in a loop without a wrapping transaction. App crash between delete and inserts causes complete data loss.

**Fix:** Wrap in `db.inTransaction { ... return .commit }`.

---

### C-4. Missing deinit — NSEvent Global Monitor Leak

**Location:** `CapturePanelController` and `StackPanelController` (both store `localMouseMonitor` / `globalMouseMonitor`)

Neither controller implements `deinit`. If deallocated without `close()`, global event monitors persist indefinitely — consuming memory and potentially firing on deallocated objects.

**Fix:** Add `deinit { removeDismissMonitors() }` to both controllers.

---

### C-5. Combine Subscriptions Not Cleaned on Dealloc

**Location:** `CapturePanelRuntimeViewController` — `cancellables: Set<AnyCancellable>`

Three Combine subscriptions stored in `cancellables` with no `deinit` cleanup. Subscriptions remain active after view controller deallocation.

**Fix:** Add `deinit { cancellables.removeAll() }`. Also cancel `imageLoadTask` in deinit.

---

### C-6. Unsafe Panel Reference in Animation Completion

**Location:** `StackPanelController.swift:67-76`

`NSAnimationContext.runAnimationGroup` completion handler captures `[weak self]` but accesses `panel` as a local variable — not weak-captured. If controller deallocates mid-animation, `panel` could be a dangling reference.

**Fix:** Capture `[weak self, weak panel]` in completion handler.

---

## HIGH — Priority Improvement

### H-1. Timer Race Condition After stop()

**Location:** `RecentScreenshotCoordinator.swift:395-414`

Timer callbacks schedule `@MainActor` tasks but don't check `isStarted`. After `stop()`, pending timer firings can still call `refreshState()` on stale state.

**Fix:** Add `guard isStarted else { timer.invalidate(); return }` inside timer callback.

---

### H-2. AppModel Timer Not Invalidated in deinit

**Location:** `AppModel.swift:98-102`

`cleanupTimer` (60s interval) is only invalidated in `stop()`. If AppModel is deallocated without `stop()` being called, the timer continues firing.

**Fix:** Add `deinit { cleanupTimer?.invalidate(); captureSubmissionTask?.cancel() }`.

---

### H-3. Session Struct Mutation Violates Immutability

**Location:** `RecentScreenshotCoordinator.swift:246-253, 291-298, 322-334`

`RecentScreenshotSession` (struct) is captured as `var`, fields mutated directly, then reassigned. Violates the project's immutability convention.

**Fix:** Create new session instance with updated fields instead of mutating.

---

### H-4. Clipboard Polling Performance

**Location:** `RecentClipboardImageMonitor.swift:68-89`

Polls clipboard every 0.25 seconds (4 reads/sec) with no debouncing or coalescing. Reads image data on every poll.

**Fix:** Increase interval to 0.5–1.0s, add debouncing for rapid changes.

---

### H-5. Accessibility Nearly Absent

**Location:** Entire UI layer

Only 2 `.accessibilityLabel()` calls in the entire codebase. No Dynamic Type support, no VoiceOver semantic grouping, no `.accessibilityHint()`, no keyboard navigation hints.

**Scope:** All interactive elements in `CaptureComposerView`, `CardStackView`, `CaptureCardView` need labels and traits.

---

## MEDIUM — Planned Improvement

### M-1. Shadow Modifiers Ignore Token Values

**Location:** `PromptCueShadowModifiers.swift:19-62`

`promptCueGlassShadow()` and `promptCuePanelShadow()` hardcode radius/y values instead of using `PrimitiveTokens.Shadow.*`. Token changes won't propagate.

---

### M-2. SearchFieldSurface Render Complexity

**Location:** `SearchFieldSurface.swift:33-140`

Light mode quiet style uses 6 overlays (material + fill + gradient + 3 masked strokes). Each overlay creates a layout pass. Problematic if used in scrolling contexts.

---

### M-3. CaptureCardView — 21 Color Conditionals Per Frame

**Location:** `CaptureCardView.swift:89-183`

Five computed properties with 21 total conditional branches for color selection, recomputed every frame. Should extract to a state-based style enum.

---

### M-4. No windowDidChangeScreen Handling

**Location:** `CapturePanelController`, `StackPanelController`

Neither controller implements `windowDidChangeScreen(_:)`. Panels don't reposition when external monitors connect/disconnect or when switching Spaces.

---

### M-5. StackPanel constrainFrameRect Bypass

**Location:** `StackPanelController.swift:242-244` (StackPanel subclass)

`constrainFrameRect(_:to:)` returns `frameRect` unchanged, completely disabling macOS screen boundary enforcement. Panel can be positioned entirely off-screen.

---

### M-6. Stale Bookmark Not Refreshed

**Location:** `ScreenshotDirectoryResolver.swift:187-210`

When security-scoped bookmark is detected as stale, the resolved URL is returned but fresh bookmark data is never written back to UserDefaults. Staleness accumulates.

---

### M-7. ExportFormatter Edge Cases Unhandled

**Location:** `ExportFormatter.swift:5-7`

Card text containing newlines breaks the bullet format. No escaping or handling. No tests for: empty array, multi-line text, special characters, single card.

---

### M-8. CardStackOrdering Semantic Ambiguity

**Location:** `CardStackOrdering.swift:16-19`, test at `PromptCueCoreTests.swift:69-91`

Sort uses `lhsCopiedAt < rhsCopiedAt` (older-copied first). Test name says "MovesCopiedCardsToBottom" but actual behavior moves *oldest-copied* above *newest-copied*. Intent vs implementation may be mismatched.

---

## LOW — Backlog

### L-1. NSStatusItem Not Cleaned in stop()

**Location:** `AppCoordinator.swift:51-56`

`statusItem` should be set to `nil` in `stop()` for explicit cleanup.

### L-2. Event Monitor Type Erasure

**Location:** `CapturePanelController`, `StackPanelController`

`localMouseMonitor: Any?` → should be `NSObjectProtocol?` for type safety.

### L-3. UserDefaults Keys Not Namespaced

**Location:** `ScreenshotDirectoryResolver.swift:4-7`

Key `"preferredScreenshotDirectoryBookmarkData"` lacks `com.promptcue.` prefix. Low collision risk but violates convention.

### L-4. DispatchQueue.main.asyncAfter in @MainActor

**Location:** `AppCoordinator.swift:39, 45`

Redundant — already on main thread. Could use `Task.sleep` for consistency with structured concurrency.

### L-5. CaptureCard JSON Codec Round-Trip Test Missing

**Location:** `Tests/PromptCueCoreTests/`

Custom `encode(to:)`/`init(from:)` on `CaptureCard` has no isolated codec test. Only tested indirectly through `CardStore` database round-trip.

---

## Strengths

- **@MainActor consistency** across entire app target for thread safety
- **Explicit lifecycle management** via `start()`/`stop()` pattern on all major components
- **Pure logic separation** — `PromptCueCore` package has zero platform dependencies
- **Immutable domain models** — `CaptureCard.markCopied()` etc. return new instances
- **Protocol-driven testability** — `RecentScreenshotCoordinating`, `AttachmentStoring`, etc.
- **Two-layer design token system** — Primitive → Semantic, adaptive light/dark
- **Test quality** — state machine coverage, boundary value testing, proper @MainActor test isolation
- **Consistent weak self captures** across all closure-heavy code
- **Lazy window controller initialization** — correct for app-lifetime objects

---

## Recommended Priority Order

1. **Stability** (C-1 through C-6): Resource leaks, crashes, data loss
2. **Quality** (H-1 through H-5): Race conditions, immutability, accessibility
3. **Maintainability** (M-1 through M-8): Token consistency, render performance, test coverage
4. **Cleanup** (L-1 through L-5): Conventions, type safety, minor improvements
