# Memory + Settings UI Freeze

## Purpose

This document freezes the current visual target for the `Memory` and `Settings`
windows before any structural refactor work begins.

The goal is simple:

- preserve the current look
- stop additional visual drift
- give the next refactor a fixed rendering contract

This is a `visual truth` document, not an implementation guide.

## Freeze Baseline

The current frozen baseline is:

- `Memory` restored to the known-good Tahoe-aligned layout from commit `3d71231`
- `Settings` content surface alignment from commit `bc29b26`
- `Settings` sidebar background rendering restored in the current working tree

Until a follow-up freeze commit is created, treat the current working tree as the
source of truth for the `Settings` first-column shell.

## Global Rule

During the next phase:

- no visual redesign
- no spacing exploration
- no typography restyling
- no token experimentation outside the explicit stabilization plan

Refactor work is only allowed if the resulting UI is visually equivalent to the
frozen state described below.

## Settings Freeze

### Column 1

The `Settings` first column must keep these properties:

- painted sidebar shell
- custom background fill plus top tint plus bottom shade
- selected row remains a strong blue selection pill
- sidebar icon tiles remain present
- no attempt to make the entire first column read as a new glass experiment

Implementation owner today:

- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/PromptCueSettingsView.swift)
- [SettingsSemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Settings/SettingsSemanticTokens.swift)

### Content Pane

The `Settings` detail pane must keep these properties:

- same base content surface family as the `Memory` second and third columns
- grouped settings sections remain visually distinct from the background
- separators and borders remain visible enough to preserve section readability

Allowed future structural work:

- token extraction
- component decomposition
- naming cleanup

Not allowed during stabilization:

- re-tinting section cards
- changing group density
- changing page header placement

## Memory Freeze

### Column 1

The `Memory` first column must keep these properties:

- liquid-glass-like shell behavior as currently rendered
- sidebar row selection remains neutral fill with tinted foreground
- no extra floating inner card
- no extra trailing refresh or collapse experiments

### Column 2

The `Memory` second column must keep these properties:

- project title and document count at the top
- trailing `+` glass control
- divider position and total header height as currently rendered
- selected document row appearance and spacing

### Column 3

The `Memory` third column must keep these properties:

- top-right action cluster
- title block and metadata placement as currently rendered
- divider ownership and position as currently rendered
- markdown body spacing and typography unchanged

Implementation owner today:

- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift)
- [MemoryWindowController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers/MemoryWindowController.swift)

## Explicit Visual Contracts

These contracts must not change during the structural pass:

- `Memory` column 2 and column 3 share the same header-height contract
- `Memory` column 3 title starts from the current anchored position relative to column 2
- `Memory` chrome controls remain `36pt` hit targets
- `Settings` first-column background remains custom-painted, not replaced with a new glass interpretation
- `Settings` detail background remains aligned to the `Memory` content surface family

## Out of Scope During Freeze

The following ideas are deferred:

- removing or redesigning settings icon tiles
- redesigning settings groups to become flatter or more card-like
- reintroducing toolbar experiments in `Memory`
- changing sidebar collapse behavior
- experimenting with different macOS Tahoe interpretations

## Verification Standard

Any stabilization change after this point should be judged against:

- current visual output in the running app
- this document
- targeted build verification only

Recommended verification:

- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Optional but useful:

- compare `Settings` first column and `Memory` first column side by side
- compare `Settings` detail background and `Memory` second or third column background

