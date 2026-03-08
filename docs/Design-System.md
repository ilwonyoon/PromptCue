# Prompt Cue Design System

## Purpose

This document defines the design system for Prompt Cue as a native macOS utility app. The target feel is:

- quiet
- ambient
- fast to parse
- Spotlight-first
- optional Liquid Glass, never decorative by default

The design system should make the app feel like it belongs on macOS while still reading as a focused developer tool rather than a generic productivity app.

## Core Principles

1. Summon, do one thing, disappear.
2. Default to the smallest useful surface; minimal beats explanatory.
3. The panel should feel present, not loud, and less invasive than the app behind it.
4. Spotlight-first capture wins: the cursor and primary content come before titles, labels, and chrome.
5. Avoid useless text; every visible word must change comprehension, confidence, or action.
6. Avoid redundant cues; do not explain with copy what focus, layout, chips, or keycaps already make clear.
7. Quiet ambient behavior is the baseline in idle, open, hover, and dismiss states.
8. Information density is good when hierarchy stays obvious.
9. Motion should confirm state, not entertain.
10. Materials should support focus and depth, not become the visual subject.
11. Semantic tokens must drive implementation; components should not invent local styles.
12. If a value will appear twice, it should usually become a token.

## Product Feel

### Quiet Ambient

- The UI should sit lightly over the current workspace.
- The UI should interrupt as little as possible; lower visual volume is the default choice.
- Surfaces should use soft contrast, not harsh black-on-white or white-on-black.
- Background treatments should imply depth through material, shadow, and edge separation instead of saturated color.
- Idle surfaces should avoid status chatter, persistent coaching, or decorative framing.

### Spotlight-First

- The capture surface should borrow from Spotlight and Raycast patterns: centered intention, minimal chrome, strong text focus, immediate keyboard readiness.
- The first readable thing should be the insertion point or the primary content, not decorative framing.
- Actions should feel implicit: `Enter` saves, `Esc` dismisses, click copies.
- Prefer no title row, no descriptive subtitle, and no footer instructions in the default capture state.

### Optional Liquid Glass

- Liquid Glass is an optional visual layer, not a product identity.
- When enabled, use translucent shells, soft edge highlights, and restrained inner reflections.
- The app must still look correct in a non-vibrant or reduced-transparency environment.

## Visual Direction

### Base Palette

Use a cool-neutral palette with a restrained icy accent.

- Base neutral: graphite and fog, not pure black
- Secondary neutral: warm-cool mixed gray for readable depth
- Accent: muted ice blue or soft cyan
- Positive state: desaturated mint
- Warning state: restrained amber
- Destructive state: muted coral red

Avoid:

- purple-heavy startup aesthetic
- neon accents
- full-bleed gradients inside productivity surfaces
- deep shadow stacks that feel like iOS marketing art

## Primitive Tokens

Primitive tokens are the raw ingredients. Semantic tokens must reference these.

### Spacing

| Token | Value |
| --- | --- |
| `space-2` | `2` |
| `space-4` | `4` |
| `space-6` | `6` |
| `space-8` | `8` |
| `space-10` | `10` |
| `space-12` | `12` |
| `space-14` | `14` |
| `space-16` | `16` |
| `space-20` | `20` |
| `space-24` | `24` |
| `space-28` | `28` |
| `space-32` | `32` |

Usage:

- `2-6`: micro spacing inside chips, borders, badges
- `8-12`: default internal spacing
- `14-20`: component padding
- `24-32`: panel margins and large grouping

### Radius

| Token | Value |
| --- | --- |
| `radius-6` | `6` |
| `radius-8` | `8` |
| `radius-10` | `10` |
| `radius-12` | `12` |
| `radius-14` | `14` |
| `radius-16` | `16` |
| `radius-20` | `20` |
| `radius-pill` | `999` |

Usage:

- `radius-8`: chips, inline badges
- `radius-10`: input internals
- `radius-12`: cards
- `radius-16`: panel shells
- `radius-20`: large glass shells only

### Typography

Use native macOS typography first.

| Token | Style |
| --- | --- |
| `font-capture-input` | `SF Pro Text Regular 17/22` |
| `font-panel-title` | `SF Pro Text Semibold 15/20` |
| `font-body` | `SF Pro Text Regular 15/20` |
| `font-body-medium` | `SF Pro Text Medium 15/20` |
| `font-meta` | `SF Pro Text Regular 13/18` |
| `font-meta-medium` | `SF Pro Text Medium 13/18` |
| `font-caption` | `SF Pro Text Regular 11/14` |
| `font-caption-medium` | `SF Pro Text Semibold 11/14` |
| `font-mono` | `SF Mono Regular 11/14` |
| `font-mono-medium` | `SF Mono Medium 11/14` |

Rules:

- The capture surface is the only `17pt` lane in the app.
- Card copy and panel content use `15pt` as the primary reading size.
- Metadata, timestamps, helper copy, and chips use `13pt`.
- `11pt` is the floor for dense labels and shortcut-style metadata.
- Prefer `22pt` line height for the `17pt` capture lane.
- Prefer `20pt` line height for `15pt` reading copy.
- Prefer `18pt` line height for `13pt` secondary copy.
- Use `SF Mono` only for shortcuts, keycaps, or code-like metadata.

### Opacity

| Token | Value |
| --- | --- |
| `opacity-08` | `0.08` |
| `opacity-12` | `0.12` |
| `opacity-18` | `0.18` |
| `opacity-24` | `0.24` |
| `opacity-32` | `0.32` |
| `opacity-48` | `0.48` |
| `opacity-64` | `0.64` |
| `opacity-88` | `0.88` |

Usage:

- `08-18`: hairline overlays, subtle fills
- `24-32`: hover/focus states
- `48-64`: secondary text and disabled icon layers
- `88`: strong foreground on translucent surfaces

### Motion

| Token | Value |
| --- | --- |
| `motion-fast` | `0.12s` |
| `motion-standard` | `0.18s` |
| `motion-slow` | `0.26s` |
| `curve-standard` | `easeOut` |
| `curve-emphasized` | `spring(response: 0.28, dampingFraction: 0.86)` |

Rules:

- Panel show/hide: `motion-standard`
- Hover: `motion-fast`
- Selection and chip state: `motion-fast`
- Avoid bounce except for explicit drop or attach interactions

### Elevation

| Token | Value |
| --- | --- |
| `elevation-0` | no shadow |
| `elevation-1` | y `4`, blur `16`, alpha `0.10` |
| `elevation-2` | y `10`, blur `28`, alpha `0.14` |
| `elevation-3` | y `18`, blur `44`, alpha `0.18` |

Rules:

- Most content uses `elevation-0` or `elevation-1`
- Floating panels use `elevation-2`
- Reserve `elevation-3` for one active shell, never nested card stacks

### Materials

| Token | Intent |
| --- | --- |
| `material-clear` | transparent fallback |
| `material-panel` | utility panel shell |
| `material-input` | slightly denser input backing |
| `material-pop` | selection badge or active chip backdrop |

Rules:

- Material should be applied at container level, not every child.
- If blur is used, border and text contrast must still work in reduced transparency mode.

## Semantic Tokens

Semantic tokens are what components consume.

### Capture Panel Shell

- `shell.capture.background`
- `shell.capture.border`
- `shell.capture.shadow`
- `shell.capture.material`
- `shell.capture.padding`
- `shell.capture.radius`

Recommended values:

- background: cool neutral with material
- border: 1px high-alpha inner border
- shadow: `elevation-2`
- radius: `radius-16`
- padding: `space-16`

### Stack Panel Shell

- `shell.stack.background`
- `shell.stack.border`
- `shell.stack.shadow`
- `shell.stack.material`
- `shell.stack.radius`

Recommended values:

- slightly denser than capture shell
- right-side panel may feel heavier than Spotlight-style capture surface

### Input Surface

- `input.background`
- `input.border.default`
- `input.border.focused`
- `input.text`
- `input.placeholder`
- `input.selection`
- `input.caret`
- `input.radius`
- `input.padding-x`
- `input.padding-y`

Rules:

- Focused border should change before the shadow does.
- Placeholder must remain readable on translucent material.
- Text editor background should not be fully transparent.

### Text Roles

- `text.primary`
- `text.secondary`
- `text.tertiary`
- `text.inverse`
- `text.accent`
- `text.warning`
- `text.destructive`
- `text.disabled`

Rules:

- Primary text should remain readable at a glance over material.
- Secondary text should support timestamps and supporting explanations.
- Tertiary text is for helper chrome only.

### Chips And Keycaps

- `chip.background`
- `chip.background.active`
- `chip.border`
- `chip.text`
- `chip.text.active`
- `keycap.background`
- `keycap.border`
- `keycap.text`

Usage:

- screenshot attached status
- selected count
- shortcut hints
- empty-state suggestions

### Selection

- `selection.background`
- `selection.border`
- `selection.text`
- `selection.glow`

Rules:

- Selection must be visible even with vibrancy disabled.
- Avoid using only color fill; pair fill with border or accent edge.

### Borders

- `border.subtle`
- `border.default`
- `border.strong`
- `border.focus`
- `border.destructive`

Rules:

- Border hierarchy should be stronger on glass surfaces than on opaque cards.
- Use 1px default. Use 0.5px only for separators on scale-aware surfaces.

### Shadows

- `shadow.panel`
- `shadow.card`
- `shadow.selection`
- `shadow.none`

Rules:

- Cards should rely more on fill separation than on heavy shadow.
- Panels can use wider, softer shadows than internal elements.

### States

- `state.hover.overlay`
- `state.pressed.overlay`
- `state.focus.ring`
- `state.disabled.opacity`
- `state.empty.border`

State guidance:

- Hover should feel ambient, not button-like.
- Pressed state can slightly reduce opacity and compress scale by 1-2%.
- Focus ring should be calmer than default iOS-style blue unless the system focus ring is intentionally used.

## Reusable Component Inventory

### Panel Shell

Purpose:

- Outer chrome for capture and stack panels

Contains:

- material layer
- border
- shadow
- internal padding
- optional title row

### Capture Input

Purpose:

- primary text entry for quick capture

Requirements:

- immediate focus on open
- supports multiline
- accepts `Enter` submit and `Esc` dismiss logic from shell
- shows optional screenshot attachment chip

### Attachment Chip

Purpose:

- communicates presence of a recent screenshot

Requirements:

- compact
- removable
- includes icon + label
- can show hover removal affordance

### Card Tile

Purpose:

- one stored note in the stack

Requirements:

- clear selected and hover states
- supports optional thumbnail
- timestamp is secondary but visible
- click copies
- modifier-based selection remains legible

### Card Stack

Purpose:

- vertically ordered list of cards

Requirements:

- newest first
- stable spacing
- supports empty state
- supports grouped copy affordance when selection exists

### Footer Utility Row

Purpose:

- low-emphasis utility actions and status

Contains:

- selected count
- TTL message
- optional settings or permission hint

### Keycap Hint

Purpose:

- inline shortcut display

Requirements:

- use mono typography
- neutral fill
- clear border on translucent surfaces

### Empty State

Purpose:

- explain what to do without feeling like onboarding

Requirements:

- minimal copy
- single primary hint
- optional shortcut reminder

## Copy Minimization

### Rules

- UI copy must earn its space. If removal does not change user action or confidence, remove it.
- Prefer one short label over a sentence, and silence over filler.
- Do not restate built-in behavior such as capture focus, `Enter` submit, `Esc` dismiss, or click-to-copy when the interaction already follows the product pattern.
- Do not narrate obvious state that is already visible in structure or controls.
- Keep empty states to one primary hint plus one optional shortcut reminder only when it materially improves first use.
- Secondary and tertiary text should stay exceptional, not default.

### Helper Text Is Forbidden When

- the placeholder, field label, chip, selection state, or layout already communicates the same meaning
- the text only describes standard keyboard behavior or obvious affordances
- the text repeats nearby metadata, icons, or button labels
- the UI is in a normal, non-blocked state with no error, permission issue, or destructive consequence to explain
- the copy exists only to make the panel feel friendlier, fuller, or more self-explanatory

Helper text is allowed only when it prevents a real mistake, explains a blocked permission state, or clarifies a non-obvious consequence.

## Capture Subtraction Test

Before shipping any capture UI addition, remove it and check the panel again.

- If capture still works with the element removed, keep it removed.
- If the element duplicates a placeholder, keycap hint, chip, focus state, or layout cue, cut it.
- The default capture surface should usually succeed with only the shell, focused input, and optional attachment state.
- Headers, subtitles, status rows, helper footers, and decorative badges must justify themselves against this test every time.

## Hardcoding Rules

Do not hardcode in component bodies:

- colors
- opacity values
- radii
- shadows
- spacing
- font size and weight
- animation durations
- border widths unless they are true one-off separators

Hardcoding is acceptable only when:

- a value is required by a system API and cannot be tokenized cleanly
- the value is temporary in a prototype spike
- the value is purely structural and has no design meaning

If a hardcoded value is introduced, it should be documented and reviewed before reuse.

## Implementation Guidance For SwiftUI

### Token Shape

Use typed token access instead of string lookup where possible.

```swift
enum DS {
    enum Space {
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 12
        static let panel: CGFloat = 16
    }
}
```

### Semantic Layer

Wrap semantic roles in `Color`, `Material`, and style helpers.

```swift
enum SurfaceStyle {
    static let captureMaterial: Material = .sidebar
}
```

### View Composition

- Prefer container modifiers that encode shared surface styles.
- Build `PanelShellStyle`, `CardTileStyle`, and `PromptCueTextFieldStyle` once, then reuse.
- Keep animation attached to state transitions, not nested subviews.

### Reduced Transparency

- Test with reduced transparency enabled.
- Every material-backed surface needs an opaque fallback color token.

## Implementation Guidance For AppKit

### Panels

- Apply material at the panel content or backing view level, not child-by-child.
- Use a single shell view to own shadow, border, corner radius, and blur.
- Ensure panel visuals work with `NSPanel` translucency and custom titlebar settings.

### Color Bridging

- Define tokens so they can bridge between `Color` and `NSColor`.
- Keep semantic roles identical across SwiftUI and AppKit wrappers.

### Focus And Selection

- Native focus behavior should still read as Prompt Cue, not as a random custom control set.
- If AppKit controls are wrapped, override only what is necessary for alignment with tokens.

## Accessibility And Comfort

- Minimum readable body text is `13pt`.
- Do not encode important state with color alone.
- Selection, focus, and disabled states must remain distinguishable in reduced transparency and increased contrast modes.
- Motion should remain subtle enough that repeated summon/dismiss cycles never feel tiring.

## Review Checklist

- Does the panel feel calm when opened over a busy app?
- Is the first readable thing the cursor or primary content?
- Is the default capture state minimal, less invasive, and free of useless text?
- Are there any redundant cues or helper lines that fail the subtraction test?
- Do selected cards read clearly without becoming loud?
- Does the system still look intentional with vibrancy disabled?
- Are all reusable components consuming semantic tokens instead of local values?
- Would the UI still look native if all blur were removed?

## Summary

Prompt Cue should feel like a native ambient utility, not a brand showcase. The system should emphasize clarity, soft depth, and keyboard-first utility. Materials and glass are supporting layers; the real visual identity is speed, restraint, and legibility.
