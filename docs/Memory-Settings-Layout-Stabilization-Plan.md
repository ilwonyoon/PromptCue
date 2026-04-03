# Memory + Settings Layout Stabilization Plan

## Purpose

This document defines the structural refactor that should happen *after* the UI
freeze. The refactor must preserve the frozen rendering while making the code
more stable and less likely to regress.

This is not a redesign plan. It is a `same output, stronger structure` plan.

## Why This Is Needed

The current `Memory` window is visually close to the desired result, but the
layout is still driven by a cluster of tightly coupled metrics and local view
assumptions.

Examples:

- shared header height is implicit across multiple values
- divider position and title position are related, but enforced indirectly
- visual alignment depends on metric combinations instead of explicit layout
  ownership

The `Settings` window is less fragile, but now shares some surface-token intent
with `Memory`, so the project needs a clearer separation between:

- shared panel-family tokens
- panel-specific composition rules

## Refactor Goal

Keep the same pixels while improving:

- metric ownership
- header contract clarity
- future edit safety
- view decomposition
- semantic naming

## Non-Goal

This refactor must not:

- alter the frozen layout
- change icon placement
- change header heights visually
- change section card density
- change selection appearance
- re-open token tuning

## Current Risk Areas

### Memory Header Math

Current risk area:

- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift)

The most fragile contract currently lives in `MemoryPaneMetrics`, especially:

- `sharedChromeHeaderHeight`
- `documentsHeaderTopInset`
- `documentsHeaderDividerSpacing`
- `detailHeaderTopInset`
- `detailHeaderTextTopInset`
- `detailHeaderContentBottomInset`

These values are visually correct now, but the relationship between them is not
obvious enough for future edits.

### Mixed Ownership in Memory

The `Memory` view still contains multiple responsibilities in one file:

- shell layout
- header layout contracts
- action button rendering
- row styling
- document content rendering

This is workable, but fragile.

### Shared Surface Intent Across Windows

The project now has a real shared visual intent between:

- `Settings` detail background
- `Memory` content backgrounds

But the code does not yet clearly separate:

- shared surface family
- settings-only card/group rules
- memory-only chrome/header rules

## Proposed Structural End State

### 1. Freeze Shared Contracts Explicitly

Create explicit named contracts in code for:

- shared memory chrome header height
- shared memory divider line placement
- shared memory title anchor

The point is to make it clear which values are:

- source-of-truth
- derived
- optical-only adjustments

### 2. Decompose Memory Header Pieces

Break the current `Memory` layout into smaller units while preserving metrics:

- column 2 chrome
- column 2 text block
- column 2 divider
- column 3 chrome
- column 3 title/meta block
- column 3 divider

Each unit should consume explicit layout inputs instead of recomputing local
spacing.

### 3. Separate Shared Panel Tokens From Panel-Specific Tokens

Shared family should own:

- sidebar/content base surfaces
- separators
- primary and secondary text roles

Settings-only should own:

- group fill
- sidebar icon tile shading
- settings row separators inside cards

Memory-only should own:

- chrome/header metrics
- document title/meta spacing
- markdown body rendering

### 4. Add Guardrails

At minimum:

- comments that explain which metrics are coupled
- comments that explain which metrics are optical adjustments only
- comments that warn against changing shared header height without retuning both
  columns

If practical later:

- previews that pin `Settings`
- previews that pin `Memory`

## Suggested Execution Order

1. Introduce comments and semantic naming for the current metrics
2. Extract `Memory` header sections into subviews with the same inputs
3. Move derived metric formulas next to their owning contract
4. Only after stabilization, consider any further token cleanup

## Review Checklist

Before landing the structural pass, verify:

- `Memory` column 2 header looks unchanged
- `Memory` column 3 title and divider look unchanged
- `Memory` action cluster spacing looks unchanged
- `Settings` first column background looks unchanged
- `Settings` right-side surface still matches the intended content family

## Minimum Verification

- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Optional visual verification:

- compare against the current freeze screenshots
- compare against the freeze document, not memory or intuition

