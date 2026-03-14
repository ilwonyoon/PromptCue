# Plan: Restore Single-Copy-Closes-Panel Pattern

## Restore Point
- **Tag:** `restore-point/pre-single-copy-close` (`ea91511`)
- **Rollback:** `git reset --hard restore-point/pre-single-copy-close`

---

## Goal

Restore the previous UX pattern where:
- **Default mode:** Card click → copy single card to clipboard → close Stack panel immediately
- **Multi-copy mode:** Explicit entry (Cmd+click) → card clicks toggle selection → panel stays open → commit on close

Current behavior: every card click enters multi-select implicitly and panel never auto-closes.

---

## Regression Guard

All existing behaviors that MUST be preserved:
1. Multi-copy: `toggleMultiCopiedCard()` toggling, click-order clipboard, deferred commit on close
2. Copy Raw (context menu) → immediate markCopied + exit multi-select
3. `close(commitDeferredCopies: false)` → clears staging without marking
4. `close(commitDeferredCopies: true)` → commits staged cards
5. Cmd+click enters multi-select
6. Backdrop tap / Escape / window deactivate → close panel
7. Card visual states: `isSelected`, `isRecentlyCopied`, `selectionMode`
8. All 5 existing `StackMultiCopyTests` must pass
9. `CaptureCardRenderingTests` must pass

---

## Changes (4 files + 1 test file)

### Step 1: `AppModel.swift` — Add `copySingleCard(_:)`

Add a new method that copies a single card and marks it as copied immediately (like `copyRaw` but with formatted output):

```swift
@discardableResult
func copySingleCard(_ card: CaptureCard) -> String {
    let payload = ClipboardFormatter.string(for: [card])
    ClipboardFormatter.copyToPasteboard(cards: [card])
    markCopied(orderedIDs: [card.id])
    exitMultiSelectMode()
    return payload
}
```

This mirrors `copyRaw()` (line 304) but uses the formatted clipboard path (`copyToPasteboard` with screenshot support) instead of raw text.

**No existing methods are modified.** `toggleMultiCopiedCard`, `commitDeferredCopies`, `exitMultiSelectMode` all stay as-is.

### Step 2: `CardStackView.swift` — Add `onDismissAfterCopy` callback + split `onCopy` logic

**2a.** Add a new closure property:
```swift
let onDismissAfterCopy: () -> Void
```

Add to `init` with default `{}`.

**2b.** Modify `cardRow(for:)` `onCopy` callback (line 254-256):

Current:
```swift
onCopy: {
    _ = model.toggleMultiCopiedCard(card)
},
```

New:
```swift
onCopy: {
    if model.isMultiSelectMode {
        _ = model.toggleMultiCopiedCard(card)
    } else {
        _ = model.copySingleCard(card)
        onDismissAfterCopy()
    }
},
```

**2c.** `onCmdClick` callback stays as-is (already calls `toggleMultiCopiedCard` → enters multi-select).

**2d.** `onToggleSelection` stays as-is (only active when `selectionMode == true`).

### Step 3: `StackPanelController.swift` — Wire `onDismissAfterCopy`

In `makePanel()` (line 306), pass the new closure:

```swift
CardStackView(
    model: self.model,
    onBackdropTap: { [weak self] in
        self?.close()
    },
    onDismissAfterCopy: { [weak self] in
        self?.close(commitDeferredCopies: false)
    },
    onEditCard: { ... },
    onDeleteCard: { ... }
)
```

Uses `commitDeferredCopies: false` because `copySingleCard` already called `markCopied` + `exitMultiSelectMode`. The close just needs to dismiss the panel animation — no model work needed.

### Step 4: `CaptureCardView.swift` — No changes needed

`performPrimaryAction()` (line 543) already handles the split:
- `selectionMode == true` → `onToggleSelection()` (multi-select toggle)
- `selectionMode == false` → `performCopy()` → `onCopy()` (single copy)

The `onCopy` callback in CardStackView now handles the mode-aware branching. CaptureCardView remains a dumb view.

### Step 5: Tests — Add new tests, verify existing pass

**5a.** Add to `StackMultiCopyTests.swift`:

```swift
func testSingleCardCopyMarksCardCopiedImmediately() throws {
    // copySingleCard marks card, exits multi-select, returns formatted payload
}

func testSingleCardCopyDoesNotAffectOtherCards() throws {
    // Other cards remain active (lastCopiedAt == nil)
}

func testCmdClickEntersMultiSelectThenNormalClickToggles() throws {
    // Cmd+click first card → multi-select, normal click second → toggles, not single-copy
}
```

**5b.** All 5 existing tests must pass unchanged (they test `toggleMultiCopiedCard` and panel close paths that are not modified).

---

## Interaction Matrix (after change)

| State | Action | Result |
|---|---|---|
| Default (no multi-select) | Click card | `copySingleCard` → clipboard + markCopied + panel closes |
| Default | Cmd+click card | `toggleMultiCopiedCard` → enters multi-select, panel stays |
| Multi-select active | Click card | `toggleMultiCopiedCard` → toggles selection, panel stays |
| Multi-select active | Cmd+click card | `toggleMultiCopiedCard` → toggles selection, panel stays |
| Multi-select active | Escape / backdrop | `close(commitDeferredCopies: true)` → commit + panel closes |
| Multi-select active | Edit card | `close(commitDeferredCopies: false)` → discard + panel closes |
| Any | Context menu → Copy Raw | `copyRaw` → raw clipboard + markCopied + exits multi-select |

---

## Execution Order

1. Add `copySingleCard(_:)` to `AppModel.swift`
2. Add `onDismissAfterCopy` to `CardStackView.swift` init + wire in `onCopy`
3. Wire `onDismissAfterCopy` in `StackPanelController.swift`
4. Add new tests to `StackMultiCopyTests.swift`
5. Run `swift test` — verify all core tests pass
6. Run `xcodebuild build` — verify app builds
7. Run `xcodebuild test` — verify all app tests pass (including existing StackMultiCopyTests)
