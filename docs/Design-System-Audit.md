# Backtick Design System Audit

## Purpose

This file is the fastest way to inspect what the current design system actually covers in code.

User-facing product identity is `Backtick`. Current repository paths and implementation names may still use `PromptCue`.

Use it to answer three questions:

1. What is documented?
2. What is implemented as tokens?
3. What is actually reused by components today?

## Source Of Truth

- Design principles and visual direction:
  - `docs/Design-System.md`
- Architecture and ownership boundaries:
  - `docs/Design-System-Architecture-Proposal.md`
- Primitive tokens:
  - `PromptCue/UI/DesignSystem/PrimitiveTokens.swift`
- Semantic tokens:
  - `PromptCue/UI/DesignSystem/SemanticTokens.swift`
- Shared shadow helpers:
  - `PromptCue/UI/DesignSystem/PromptCueShadowModifiers.swift`
- Reusable components:
  - `PromptCue/UI/Components/GlassPanel.swift`
  - `PromptCue/UI/Components/CardSurface.swift`
  - `PromptCue/UI/Components/PromptCueChip.swift`
  - `PromptCue/UI/Components/SearchFieldSurface.swift`
  - `PromptCue/UI/Components/PanelHeader.swift`
- Hard-coding guardrail:
  - `scripts/validate_ui_tokens.py`

## Design Principles In Force

These principles are documented and are intended to constrain implementation:

- minimal
- less invasive
- quiet ambient
- Spotlight-first capture
- capture now, act today, forget tomorrow
- capture mode = frictionless thought dump
- stack mode = execution queue
- AI belongs in Stack, not Capture
- ephemeral by design
- avoid useless text
- avoid redundant cues
- semantic tokens over local one-off styling

## Product Identity Alignment

The design system is expected to preserve this product posture:

- `Backtick` is an AI coding scratchpad and thought staging tool
- it is not a note-taking app
- capture should feel disposable and immediate
- stack should feel actionable and compressive
- UI should avoid archival or document-like cues

## Primitive Tokens Implemented

### Typography

The active type scale is:

- `capture`: `17`
- `body`: `15`
- `meta`: `13`
- `micro`: `11`
- `chip`: `12`

The active line-height scale is:

- `capture`: `22`
- `body`: `20`
- `meta`: `18`
- `micro`: `14`

Current Swift tokens:

- `Typography.captureInput`
- `Typography.panelTitle`
- `Typography.body`
- `Typography.bodyStrong`
- `Typography.meta`
- `Typography.metaStrong`
- `Typography.selection`
- `Typography.chip`
- `Typography.iconLabel`
- `Typography.accessoryIcon`
- `Typography.chipIcon`
- `Typography.emptyStateIcon`

### Layout

The active layout primitives include:

- spacing: `2, 4, 8, 12, 16, 20, 24, 32`
- radii: `12, 18, 26, 30`
- shadow values for panel and card surfaces
- component sizes such as chip height, thumbnail height, card spacing, and panel section spacing

## Semantic Tokens Implemented

The semantic layer is currently thin but real.

Implemented groups:

- `MaterialStyle`
- `Surface`
- `Text`
- `Border`
- `Accent`
- `Shadow`

What this means in practice:

- platform colors are centralized in one file
- components consume semantic colors instead of inline `Color(nsColor: ...)`
- shadows are centralized through semantic shadow color plus helper modifiers

## Reusable Components Implemented

### `GlassPanel`

Used for:

- floating stack panel shell

Provides:

- panel padding
- rounded shell
- semantic panel fill
- material layer
- subtle border
- shared panel shadow

### `CardSurface`

Used for:

- individual captured cards
- empty states

Provides:

- card padding
- default and selected fills
- selected and unselected borders
- shared card shadow

### `PromptCueChip`

Used for:

- screenshot chip
- selection chip

Provides:

- pill shape
- shared chip height
- configurable fill and border

### `SearchFieldSurface`

Used for:

- capture input shell

Provides:

- rounded input shell
- inner padding
- material-backed surface
- border and panel shadow

### `PanelHeader`

Used for:

- stack panel title/subtitle block

Provides:

- title and subtitle typography pairing

## Current Coverage In App UI

### Capture Surface

Covered by tokens/components:

- typography
- spacing
- radius
- material
- border
- shadow
- panel sizing constants

Notes:

- this is the most systematized part of the UI
- it now uses the `17 / 22` capture lane
- it should read as a raw dump surface, not a chat field or notebook editor

### Stack Panel

Covered by tokens/components:

- panel shell
- card shell
- chip shell
- title/body/meta typography

Notes:

- functionally tokenized
- visually less refined than capture surface
- it should continue moving toward an execution-queue feel rather than a note archive feel

### Settings

Covered by tokens/components:

- spacing
- layout constants

Notes:

- it is functional, but not yet a polished design-system showcase

## Hard-Coding Protection

The validator currently blocks these in UI files:

- inline `Color(nsColor: ...)`
- inline `.font(.system(...))`
- raw `cornerRadius`
- inline `.shadow(...)`
- raw numeric `padding`
- raw numeric `frame` sizing

This is enforced by:

- `scripts/validate_ui_tokens.py`

Current intent:

- new UI code should consume tokens
- design-system files themselves are allowed to contain raw source values

## What Is Good

- there is a real primitive token layer
- there is a semantic token layer
- there are shared surface components
- typography now has an explicit hierarchy instead of one-off sizes
- there is a validator to stop regression into hardcoded UI values
- the docs now define capture and stack as different behavioral modes, not just different windows

## What Is Still Incomplete

- semantic tokens are still shallow; they do not yet map every UI intent described in the design doc
- typography tokens exist, but not every view has been re-audited for ideal hierarchy and density
- materials and shadows are centralized, but not yet split into richer states such as focused, hover, inactive, or reduced-transparency variants
- there is no component gallery or preview screen yet
- stack panel design language is functional but not yet as resolved as the capture panel
- wording and affordance audits should continue checking that the product does not drift back toward note-taking language

## Verification Checklist

If you want to audit whether this is a real design system and not just a doc:

1. Open `docs/Design-System.md`
2. Open `PromptCue/UI/DesignSystem/PrimitiveTokens.swift`
3. Open `PromptCue/UI/DesignSystem/SemanticTokens.swift`
4. Open the reusable components under `PromptCue/UI/Components/`
5. Run `python3 scripts/validate_ui_tokens.py --all`
6. Confirm UI files are consuming tokens instead of raw values

## Honest Status

This is not yet a fully mature design system.

It is a working v1 system with:

- documented principles
- tokenized primitives
- tokenized semantics
- shared shells and chips
- typography hierarchy
- automated anti-hardcoding checks

What remains is refinement, broader semantic coverage, and a component gallery/previews so the system becomes easier to inspect visually.
