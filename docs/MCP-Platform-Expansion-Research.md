# MCP Platform Expansion & Information Temperature Architecture

Research doc — 2026-03-15

## Part 1: MCP Platform Expansion

### Current State

BacktickMCP is a **stdio-only** JSON-RPC 2.0 server bundled into the app at `Contents/Helpers/BacktickMCP`. It exposes 8 tools (list/get/create/update/delete/mark_executed/classify/group notes) and 4 prompt templates.

**Supported clients today:**

| Client | Transport | Status |
|--------|-----------|--------|
| Claude Code (CLI) | stdio | Supported |
| Codex (OpenAI CLI) | stdio | Supported |

### Target Platforms

| Platform | Transport Required | Feasibility |
|----------|-------------------|-------------|
| **Claude Desktop (Mac)** | stdio | Trivial — same transport, just needs `claude_desktop_config.json` registration |
| **Claude Web / Mobile** | Remote MCP (HTTP/SSE) | Requires new transport layer + auth |
| **ChatGPT Desktop (Mac)** | HTTP (SSE / Streamable HTTP) | Supported since Sep 2025 via Developer Mode |
| **ChatGPT Web** | HTTP (SSE / Streamable HTTP) | Same as Desktop — Developer Mode MCP client |
| **ChatGPT via Codex CLI** | stdio | Already works |

> **Note:** ChatGPT Developer Mode MCP support requires Pro/Team/Enterprise/Edu plan.
> ChatGPT calls MCP connectors "apps" (renamed Dec 2025).
> Settings > Apps > Advanced > Developer Mode to add MCP server URL.

### Expansion Plan

#### Phase 1: Claude Desktop (Low effort)

Claude Desktop reads `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

**Work needed:**
- Add Claude Desktop detection in `MCPConnectorInspector` (check for `~/Library/Application Support/Claude/` directory)
- Generate config snippet for `claude_desktop_config.json`
- Add one-click setup button in Settings > MCP Connector
- Validate that the bundled helper path is stable across app updates

#### Phase 2: Remote MCP (HTTP Transport) for Claude Web/Mobile

Claude Pro/Max/Team/Enterprise users can connect to remote MCP servers via HTTP+SSE or Streamable HTTP.

**Architecture decision: Local server + tunnel vs. Cloud deployment**

Recommended: **Dual transport mode** on the local server.

```
BacktickMCP --transport stdio          # existing (Claude Code, Codex, Claude Desktop)
BacktickMCP --transport http --port 8321  # new (Claude Web via tunnel)
```

**Work needed:**
1. Add lightweight HTTP server to BacktickMCP (Swift NIO or built-in `HTTPServer`)
2. Implement MCP SSE endpoint (`/sse` for connection, `/message` for requests)
3. Add authentication (API key or token-based)
4. Document tunnel setup (Cloudflare Tunnel / ngrok)
5. Settings UI: "Enable Remote Access" toggle with generated auth token

**Considerations:**
- Mac must be running for remote access to work
- Security: auth token + localhost binding + optional tunnel
- SQLite concurrent access: current GRDB setup supports WAL mode for multi-reader

#### Phase 2b: ChatGPT Integration (Same HTTP transport)

ChatGPT has **native MCP client support** since September 2025 (Developer Mode). It uses the same HTTP transport as Claude Web/Mobile — so Phase 2's HTTP work directly enables ChatGPT.

**Connection path:** Settings > Apps > Advanced > Developer Mode > Add MCP server URL

**Proven pattern:** `ilwonyoon/muninn` already connects to ChatGPT Mac App via HTTP transport using FastMCP (Python). BacktickMCP can follow the same approach in Swift.

**Requirements:**
- SSE or Streamable HTTP endpoint (same as Phase 2)
- Auth token (same as Phase 2)
- Tunnel for remote access (ngrok/Cloudflare) OR localhost if ChatGPT Desktop on same Mac
- ChatGPT Pro/Team/Enterprise/Edu plan for Developer Mode

**Key difference from Claude Web:** ChatGPT cannot connect to localhost directly — tunnel is always required even for local servers. Claude Desktop can use stdio (no tunnel needed).

---

## Part 2: AI Second Brain — Hot + Warm Memory Architecture

### Context

The journey: Muninn (project memory, but unstable localhost-only + unclear what to store) → Backtick (nailed Hot: short-lived execution queue). Now the goal is to combine both into one product — an AI Second Brain that holds project context across all AI clients and threads.

**The core problem:** AI conversations are scattered across ChatGPT, Claude, Claude Code, Codex. Even within the same app, opening a new thread loses all context. There is no persistent memory layer that bridges these tools.

**Scope:** Hot + Warm only. Cold (secrets, permanent config) is a convenience feature, not core — excluded for now.

### Hot vs Warm: Fundamentally Different UX

| | Hot (Stack — exists) | Warm (new) |
|---|---|---|
| **Unit** | Short card (1-3 lines) | Long document (markdown, sections, pages) |
| **Lifespan** | Hours (8h TTL) | Days → weeks → months |
| **Primary action** | Copy → paste → done | Read / review / update |
| **Input** | Human captures quickly | AI saves via MCP (+ human edits) |
| **Consumption** | Glance (scan a list) | Scroll / expand / deep read |
| **Mutation** | Rarely edited | Continuously updated |
| **Identity** | Disposable (no title needed) | Named per project/topic |

**Key insight:** Warm items cannot be cards in a list. A document that's 3 pages long needs a viewer, not a card slot. The UX for Warm is closer to a notes app than a clipboard manager.

### Data Model

#### Warm documents: separate from CaptureCard

Hot cards and Warm documents are different enough to warrant distinct models rather than overloading CaptureCard with a `tier` field.

```swift
// New model in PromptCueCore
public struct ProjectDocument: Codable, Sendable, Identifiable {
    public let id: UUID
    public var projectName: String           // e.g. "PromptCue", "muninn"
    public var summary: String               // markdown body (can be long)
    public var tags: [CaptureTag]
    public var status: DocumentStatus        // active, paused, archived
    public var createdAt: Date
    public var updatedAt: Date
}

public enum DocumentStatus: String, Codable, Sendable {
    case active     // current work
    case paused     // on hold
    case archived   // done, kept for reference
}
```

**Database:** New `project_documents` table alongside existing `cards` table.

```sql
CREATE TABLE project_documents (
    id TEXT PRIMARY KEY NOT NULL,
    projectName TEXT NOT NULL,
    summary TEXT NOT NULL,
    tagsJSON TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    createdAt DATETIME NOT NULL,
    updatedAt DATETIME NOT NULL
);
CREATE INDEX idx_project_documents_projectName ON project_documents(projectName);
CREATE VIRTUAL TABLE project_documents_fts USING fts5(projectName, summary);
```

#### Inheriting from Muninn

Muninn's document-first model (`projects.summary` = one markdown doc per project) is the right abstraction for Warm. The key improvements over Muninn:

1. **Native macOS UI** instead of localhost web dashboard
2. **Bundled into Backtick** — single app, single process
3. **Shared MCP server** — one server exposes both Hot and Warm tools
4. **Stable transport** — stdio for local clients, HTTP for remote

### MCP Tool Design

Existing Hot tools remain unchanged. New Warm tools added to the same server:

| Tool | Purpose |
|------|---------|
| `save_document` | Create or update a project document (upsert by projectName) |
| `recall_document` | Retrieve one project's document, or list all active projects |
| `search_documents` | Full-text search across all project documents |
| `manage_document` | Set status (active/paused/archived), rename, delete |

**Naming convention:** `*_note` = Hot (existing), `*_document` = Warm (new). Clear separation for AI clients.

**AI usage pattern:**
```
// Claude Code finishing a session:
save_document(projectName: "PromptCue", summary: "## Session 2026-03-15\n### Done\n- Added HTTP transport...\n### Next\n- Wire up auth...")

// ChatGPT starting a new thread:
recall_document(projectName: "PromptCue")
// → Gets full project context, continues where the last session left off
```

### UX: How Warm Fits Into Backtick

#### Option A: Drawer/sidebar within Stack panel

```
┌─────────────────────────────┐
│ [Stack]  [Memory]           │  ← tab/segment switcher
├─────────────────────────────┤
│                             │
│  PromptCue          active  │  ← project row (collapsed)
│  muninn             paused  │
│  client-project-x   active  │
│                             │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  + New Project              │
└─────────────────────────────┘

click on project row → expands inline or opens detail view:

┌─────────────────────────────┐
│ ← Back    PromptCue         │
├─────────────────────────────┤
│ ## Session 2026-03-15       │
│ ### Done                    │
│ - Added HTTP transport      │
│ - Fixed auth flow           │
│ ### Next                    │
│ - Wire up tunnel setup      │
│ - Test ChatGPT connection   │
│                             │
│ Updated: 2 hours ago        │
│ [Edit]                      │
└─────────────────────────────┘
```

**Pros:** Single panel, familiar location. Tab switch is low friction.
**Cons:** Long documents in a narrow panel may feel cramped.

#### Option B: Separate Memory panel (like Stack has its own panel)

A second NSPanel, wider, optimized for reading. Hotkey: `Cmd + 3`.

**Pros:** More room for long documents. Reading-optimized layout.
**Cons:** Another window to manage. May feel disconnected from Stack.

#### Option C: Stack panel with popover/sheet for document detail

Project rows appear in Stack (below Hot cards or in a collapsible section). Clicking opens a popover or sheet overlay for the full document.

**Pros:** One panel, documents feel connected to the daily workflow.
**Cons:** Popover size limits. Complex interaction model.

**Recommendation:** Start with **Option A** (tab switcher in Stack panel). It keeps everything in one place, matches the "single app" goal, and the detail view can expand to fill the panel. If reading experience is insufficient, graduate to Option B later.

### Information Flow

```
AI conversation (any client, any thread)
    │
    ├── create_note(text: "run migration")     → Hot (Stack, today)
    │
    └── save_document(projectName: "X",        → Warm (Memory, persists)
         summary: "## Context\n...")
              │
              ├── Next session: recall_document("X") → AI has full context
              └── Human: opens Memory tab → reads/reviews/edits
```

**Hot → Warm promotion:** A Stack card can be promoted to a document (append to project summary). But this is a nice-to-have, not launch-critical.

---

## Implementation Priority

| # | Task | Effort | Dependencies |
|---|------|--------|-------------|
| 1 | Claude Desktop stdio registration in Settings | Small | None |
| 2 | `ProjectDocument` model + DB migration + CRUD services | Medium | None |
| 3 | MCP Warm tools: save/recall/search/manage_document | Medium | #2 |
| 4 | Memory tab UI in Stack panel (list + detail view) | Medium | #2 |
| 5 | HTTP transport for BacktickMCP (enables ChatGPT + Claude Web) | Large | None |
| 6 | Auth + tunnel documentation | Medium | #5 |

**Phase 1 (ship together):** Tasks 1-4. Backtick becomes Hot + Warm, accessible from Claude Desktop + Claude Code + Codex via stdio.

**Phase 2:** Tasks 5-6. HTTP transport unlocks ChatGPT and Claude Web/Mobile.
