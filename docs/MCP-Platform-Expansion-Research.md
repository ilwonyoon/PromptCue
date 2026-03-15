# MCP Platform Expansion & Warm Memory Architecture

Research doc — 2026-03-15 (v3)

## Vision

Backtick = AI Second Brain. A memory layer that bridges ChatGPT, Claude, Claude Code, Codex — so that opening a new thread in any app doesn't mean starting from scratch. The product holds two types of information:

- **Hot (Stack):** Today's execution queue. Short cards, copied and done. Already built.
- **Warm (Memory):** Project documents that persist across sessions. Key conversations and decisions from AI chats, continuously updated. Not yet built.

Cold (secrets, permanent config) is out of scope — convenience, not core.

---

## Part 1: Connection Architecture

### Reference: Muninn's proven patterns

Muninn (`ilwonyoon/muninn`) validated the connection model. Key lessons:

| Client | Transport | How it connects |
|--------|-----------|-----------------|
| Claude Code CLI | stdio | `claude mcp add backtick -- <binary>` |
| Claude Desktop (Mac) | stdio | `claude_desktop_config.json` → spawns process |
| Codex CLI | stdio | `codex mcp add backtick -- <binary>` |
| ChatGPT Mac App | **HTTP localhost** | `http://127.0.0.1:<port>/` — no tunnel needed |
| Claude Web / Mobile | HTTP + tunnel | Cloudflare Tunnel or ngrok required |
| ChatGPT Web | HTTP + tunnel | Same as above |

**Key correction:** ChatGPT Mac App connects to localhost directly. No tunnel required for same-machine usage.

### Stability analysis

Muninn's localhost web dashboard was unstable. Why? Separate Python process that had to be manually started, could crash independently, port conflicts, no lifecycle management.

**How Backtick solves this:**

| Instability source | Backtick's advantage |
|---|---|
| Separate process to manage | Backtick app manages the MCP server lifecycle — starts on launch, restarts on crash |
| Port conflicts | App owns its port, configurable in Settings |
| No crash recovery | App can supervise the HTTP server (watchdog/respawn) |
| Manual startup | Backtick is a menu bar app — always running, auto-launches on login |
| stdio clients need config | Settings UI generates config + one-click install |

**Architecture: single binary, dual transport**

```
BacktickMCP (bundled in app)
├── stdio mode  → Claude Desktop, Claude Code, Codex (spawned per-client)
└── http mode   → ChatGPT Mac App, Claude Web, ChatGPT Web (long-running server)
```

The app runs the HTTP server as an in-process component (not a child process). This eliminates the "separate process" instability that plagued Muninn.

### Connection setup per client

#### Claude Desktop (stdio — no server needed)

Config: `~/Library/Application Support/Claude/claude_desktop_config.json`
```json
{
  "mcpServers": {
    "backtick": {
      "command": "/Applications/Backtick.app/Contents/Helpers/BacktickMCP",
      "args": []
    }
  }
}
```
Backtick Settings UI: detect Claude Desktop → generate config → one-click write.

#### ChatGPT Mac App (HTTP localhost)

1. Backtick starts HTTP server on `127.0.0.1:8321` (configurable)
2. ChatGPT: Settings > Apps > Advanced > Developer Mode
3. Add MCP server URL: `http://127.0.0.1:8321/`
4. Auth: Bearer token (generated in Backtick Settings, copied to ChatGPT)

Requires: ChatGPT Pro/Team/Enterprise/Edu plan for Developer Mode.

#### Claude Web / ChatGPT Web (HTTP + tunnel — future)

For accessing from phone or non-local machine:
1. Backtick HTTP server running locally
2. Cloudflare Tunnel or ngrok exposes it
3. Public URL registered in Claude Web or ChatGPT Web

This is Phase 2. Local-first (stdio + HTTP localhost) comes first.

### HTTP transport implementation

**Option A: Swift NIO embedded in BacktickMCP binary**
- Add Hummingbird or Vapor-lite as dependency
- BacktickMCP binary gains `--transport http --port 8321` flag
- Reuses existing JSON-RPC handler, wraps in HTTP

**Option B: Backtick app hosts HTTP server directly**
- No separate binary for HTTP mode
- App's main process runs the HTTP server
- Shares the same GRDB database connection (no concurrency issues)
- MCP requests handled in-process

**Recommendation: Option B.** The app is always running (menu bar). HTTP server is just another service the app hosts. BacktickMCP binary stays stdio-only (simple, stable). The app handles HTTP transport natively.

This means:
- stdio clients → BacktickMCP helper binary (existing)
- HTTP clients → Backtick app process (new)
- Both read/write the same SQLite database

### Auth for HTTP

Following Muninn's pattern:

```
Priority:
1. Bearer token (BACKTICK_API_KEY or generated in Settings)
2. No auth (localhost dev only, with warning)
```

Token generated once in Settings, displayed for user to copy into ChatGPT config. Stored in Keychain.

---

## Part 2: Warm Memory — Saving AI Conversations

### What gets saved

The core use case: AI finishes a meaningful conversation → saves a structured summary to Backtick. Next time any AI client starts a new thread, it recalls the project context.

**Examples of what AI saves:**

```markdown
## PromptCue — Session 2026-03-15

### Decisions
- MCP HTTP transport will be hosted by the app process, not the helper binary
- Warm documents use ProjectDocument model, separate from CaptureCard

### Done
- Added Claude Desktop config generation in Settings
- Implemented save_document / recall_document MCP tools

### Open questions
- Memory tab UX: inline viewer vs separate panel
- FTS indexing strategy for large documents

### Next
- Wire up HTTP server in AppDelegate
- Test ChatGPT localhost connection
```

This is **not** a full conversation transcript. It's a distilled project document that an AI (or human) can update incrementally.

### Data model

Two-level structure: Project (folder) → Documents (by topic).

```swift
public struct Project: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String              // "backtick" — unique key
    public var status: ProjectStatus     // active, paused, archived
    public var createdAt: Date
    public var updatedAt: Date           // latest across all docs
}

public struct ProjectDocument: Codable, Sendable, Identifiable {
    public let id: UUID
    public var project: String           // FK → Project.name
    public var topic: String             // "branding" — slug
    public var content: String           // markdown body
    public var createdAt: Date
    public var updatedAt: Date
}
// DB unique constraint: (project, topic)

public enum ProjectStatus: String, Codable, Sendable {
    case active
    case paused
    case archived
}
```

Database: `projects` table + `project_documents` table with FTS5 full-text search on content.

### MCP tools for Warm

Full CRUD + project management. Referencing Muninn's tool set but adapted for Backtick.

#### Muninn's tools (reference)

| Muninn tool | What it does |
|-------------|-------------|
| `muninn_save` | Replace entire project summary (full document swap) |
| `muninn_save_memory` | Append a progress entry to timeline (additive, not replacement) |
| `muninn_recall` | Read one project or list all active projects |
| `muninn_search` | FTS keyword search across all documents |
| `muninn_status` | List all projects with metadata (no content) |
| `muninn_manage` | Lifecycle: set_status, create_project, delete_project, set_github_repo |
| `muninn_sync` | Pull GitHub data (commits, issues, PRs) into memory |

#### Backtick Warm tools (proposed)

| Tool | Purpose | Notes |
|------|---------|-------|
| `save_document` | Create or **replace** a document | Upsert by `(project, topic)`. Full content swap. |
| `update_document` | **Partial update** — append, replace section, or remove section | Avoids rewriting entire doc. Key gap in Muninn. |
| `recall_document` | Read one document by `(project, topic)` | Returns full content for AI context |
| `list_documents` | List all topics in a project, or all projects | Lightweight: titles + status + updatedAt, no content |
| `delete_document` | Remove a specific topic document | Clean deletion |
| `search_documents` | Full-text search across all documents | FTS5 keyword search |
| `manage_project` | Create project, set status, rename, delete project (and all its docs) | Project lifecycle |

**Why `update_document` matters:** In Muninn, the only way to update was `muninn_save` which replaces the entire document. For a 2-page doc, AI has to recall the full text, modify it, and save it all back — expensive and error-prone. A partial update tool (append a section, replace a section by header, delete a section) makes incremental updates cheap.

```
// Append to branding doc:
update_document(project: "backtick", topic: "branding", action: "append",
  content: "## 2026-03-16 Color revision\nChanged primary to...")

// Replace a section in pricing doc:
update_document(project: "backtick", topic: "pricing", action: "replace_section",
  section: "Competitor Analysis", content: "- Raycast: free tier + $8/mo...")

// Remove resolved section:
update_document(project: "backtick", topic: "architecture", action: "delete_section",
  section: "Resolved Questions")
```

#### Document structure: project × topic

Muninn collapsed everything into one document per project. In practice this breaks — a project like Backtick has discussions about logo, pricing, website, architecture, launch that don't belong in one file.

**Solution: `project × topic` as the document unit.**

```
Project: backtick
├── branding       ← logo, colors, tone (accumulated across multiple conversations)
├── pricing        ← pricing model, competitor analysis
├── website        ← landing page, docs structure
├── architecture   ← MCP expansion, Hot/Warm design
└── launch         ← release plan, marketing
```

- **AI can classify by topic** — it knows a logo conversation is "branding". This is the right granularity for AI to handle.
- **Same topic updates across sessions** — discuss logo Monday, revisit Wednesday → branding doc gets updated, not duplicated.
- **Each doc stays bounded** — no single doc grows to unmanageable size.
- **Topic explosion prevention** — AI instruction: "fit into existing topics first, only create new topic if clearly distinct". If a project gets >10 topics, suggest consolidation.

**Addressing scheme:** `(project, topic)` is the unique key. Simple, flat, no nesting.

```swift
public struct ProjectDocument: Codable, Sendable, Identifiable {
    public let id: UUID
    public var project: String       // "backtick"
    public var topic: String         // "branding" — slug, kebab-case
    public var content: String       // markdown body
    public var status: DocumentStatus
    public var createdAt: Date
    public var updatedAt: Date
}
// DB unique constraint: (project, topic)
```

**Excluded from scope:** Coding session logs (git history already covers this). Warm is for **discussions and decisions** from ChatGPT/Claude conversations, not development progress from Codex/Claude Code.

#### AI workflow

```
Session start:
  → list_documents(project: "backtick")
  → ["branding", "pricing", "architecture", "launch"]
  → recall_document(project: "backtick", topic: "pricing")  // relevant to today's discussion

During session (2h pricing discussion):
  → update_document(project: "backtick", topic: "pricing", action: "replace_section",
       section: "Decision", content: "Freemium + $9/mo premium...")

New topic emerges:
  → save_document(project: "backtick", topic: "distribution",
       content: "## App Store vs Direct\n### Pros/Cons\n...")

Next day, different AI client, new thread:
  → list_documents(project: "backtick")
  → recall_document(project: "backtick", topic: "distribution")
  → Continues where yesterday left off
```

### UX: Memory panel

Warm documents need reading/editing, not glancing. Stack's narrow card-list UX doesn't fit long markdown. Memory gets its **own panel** — same pattern as Capture and Stack (separate NSPanel, own hotkey).

```
Menu bar icon
├── Cmd+`  → Capture panel (existing, Quick Capture)
├── Cmd+2  → Stack panel (existing, Hot)
└── Cmd+3  → Memory panel (new, Warm)
```

**One app, three panels.** Each optimized for its purpose.

#### Memory panel: project list → topic list → document viewer

```
┌──────────────────────────────────────────┐
│ Memory                            Cmd+3  │
├──────────────────────────────────────────┤
│                                          │
│  backtick                       active   │
│    branding · pricing · architecture     │  ← topic chips
│    website · launch                      │
│    Updated: 2 hours ago                  │
│                                          │
│  muninn                         paused   │
│    architecture · connection             │
│    Updated: 1 week ago                   │
│                                          │
│  + New Project                           │
└──────────────────────────────────────────┘

click topic chip → document detail:

┌──────────────────────────────────────────┐
│ ← backtick / pricing                    │
├──────────────────────────────────────────┤
│                                          │
│ ## Decision                              │
│ Freemium + $9/mo premium tier.           │
│ Free: 5 projects, Hot only.              │
│ Premium: unlimited, Warm memory, HTTP.   │
│                                          │
│ ## Competitor Analysis                   │
│ - Raycast: free + $8/mo                  │
│ - Paste: $1.99/mo                        │
│                                          │
│ ## Open Questions                        │
│ - Annual discount?                       │
│ - Student pricing?                       │
│                                          │
│ Updated: 3 hours ago            [Edit]   │
└──────────────────────────────────────────┘
```

**Why separate panel, not tab in Stack:**
- Stack stays untouched — zero risk to existing Hot UX
- Memory panel can be wider (documents need horizontal space)
- Both panels can be open simultaneously (Hot cards on one side, reading a doc on the other)
- Same pattern already established (Capture panel + Stack panel are separate)

---

## Architecture: Zero Regression on Capture & Stack

Memory is additive. Capture and Stack must not be touched, broken, or slowed down.

### Isolation boundaries

```
PromptCueCore (pure Swift package, no AppKit)
├── CaptureCard, CaptureDraft, ...        ← existing, UNCHANGED
├── CardStackOrdering, ContentClassifier  ← existing, UNCHANGED
├── Project, ProjectDocument              ← NEW models, own files
└── ProjectDocumentStore                  ← NEW service, own file

BacktickMCPServer (MCP JSON-RPC handler)
├── Hot tools (list/get/create/update/delete_note, ...) ← existing, UNCHANGED
└── Warm tools (save/recall/update/list/delete_document, ...) ← NEW, own file

Backtick app target
├── AppCoordinator         ← adds MemoryPanelController, same pattern as Stack
├── AppModel               ← gains @Published projectDocuments, no change to cards/draft
├── CapturePanelController ← UNCHANGED
├── StackPanelController   ← UNCHANGED
├── MemoryPanelController  ← NEW, own NSPanel, own window controller
└── MemoryViews/           ← NEW SwiftUI views, own directory
```

**Rules:**
1. No edits to `CapturePanelController`, `StackPanelController`, or their SwiftUI views
2. No changes to `CaptureCard`, `CaptureDraft`, `CardStore`, `CopyEventStore`
3. `AppModel` gains new `@Published` properties for projects/documents — existing properties untouched
4. `AppCoordinator` gains `MemoryPanelController` — same lifecycle pattern as existing panels
5. New DB tables (`projects`, `project_documents`) — no migration touches existing `cards` table
6. MCP: new tools registered in `BacktickMCPServerSession` — existing tool handlers untouched
7. All new files go in clearly separated directories (`MemoryViews/`, `MemoryServices/`)

### Design system compliance

Memory panel UI must follow the existing two-layer token system:

- **`PrimitiveTokens`** → `FontSize`, `LineHeight`, `Space`, `Radius`, `Shadow`
- **`SemanticTokens`** → `Surface`, `Text`, `Border`, `Accent`, `Shadow`, `MaterialStyle`

**Specifics for Memory panel:**
- Panel chrome: same `Surface.panel` + `MaterialStyle` as Stack panel
- Project list rows: use `Space`, `Radius`, `Text.primary`/`Text.secondary` tokens
- Topic chips: use `Accent` + `Radius.small` tokens
- Document viewer: `Text.primary` for body, `Text.secondary` for metadata
- Edit button: same button style tokens as Stack
- No hardcoded colors, spacing, radius, fonts, or shadows — enforced by `validate_ui_tokens.py`

**Validation:** `python3 scripts/validate_ui_tokens.py` must pass with Memory panel views included.

---

## Implementation Plan

| # | Task | Effort | What it unlocks |
|---|------|--------|-----------------|
| 1 | Claude Desktop stdio registration in Settings | S | Claude Desktop as MCP client |
| 2 | `Project` + `ProjectDocument` models + DB migration + services | M | Warm storage layer |
| 3 | MCP Warm tools (save/update/recall/list/delete/search/manage) | M | AI can save/recall project context |
| 4 | Memory panel (NSPanel, project list → topic list → doc viewer) | M | Human can review/edit documents |
| 5 | HTTP server in Backtick app process | L | ChatGPT Mac App connection |
| 6 | Auth (Bearer token) + Settings UI for HTTP | M | Secure HTTP connections |

**Phase 1 (stdio clients + Warm memory):** #1-4
→ Claude Desktop, Claude Code, Codex can save/recall project documents

**Phase 2 (HTTP transport):** #5-6
→ ChatGPT Mac App connects via localhost HTTP

**Phase 3 (remote access):** Tunnel setup for Claude Web / ChatGPT Web / Mobile
