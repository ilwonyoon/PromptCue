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

```swift
public struct ProjectDocument: Codable, Sendable, Identifiable {
    public let id: UUID
    public var projectName: String           // unique key for upsert
    public var summary: String               // markdown body
    public var tags: [CaptureTag]
    public var status: DocumentStatus        // active, paused, archived
    public var createdAt: Date
    public var updatedAt: Date
}

public enum DocumentStatus: String, Codable, Sendable {
    case active
    case paused
    case archived
}
```

Database: `project_documents` table with FTS5 full-text search.

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
| `save_document` | Create or **replace** a project's document | Upsert by projectName. Full document swap. |
| `update_document` | **Partial update** — append, replace section, or remove section | Avoids rewriting entire doc for small changes. Key gap in Muninn. |
| `recall_document` | Read one project's document, or list all active projects | AI calls at session start for context |
| `delete_document` | Remove a document (or entire project) | Clean deletion with confirmation |
| `search_documents` | Full-text search across all documents | FTS5 keyword search |
| `list_projects` | List all projects with status + last updated (no content) | Lightweight inventory, like `muninn_status` |
| `manage_project` | Create project, set status (active/paused/archived), rename | Project lifecycle management |

**Why `update_document` matters:** In Muninn, the only way to update was `muninn_save` which replaces the entire document. For a 2-page doc, AI has to recall the full text, modify it, and save it all back — expensive and error-prone. A partial update tool (append a section, replace a section by header, delete a section) makes incremental updates cheap.

```
// Append a new session log:
update_document(project: "PromptCue", action: "append", content: "## Session 2026-03-16\n...")

// Replace a specific section:
update_document(project: "PromptCue", action: "replace_section", section: "Next", content: "- New task 1\n- New task 2")

// Remove a section:
update_document(project: "PromptCue", action: "delete_section", section: "Resolved Issues")
```

#### Multi-document per project: the hard problem

Muninn intended multiple documents per project (folder concept) but it was too hard to build well, so everything collapsed into one summary document.

**Why it's hard:**
- AI needs to know which document to read/write → requires naming/addressing scheme
- Document discovery: AI asks "what docs exist?" → needs listing per project
- Cross-document references: "the architecture doc mentions X" → search scope
- UX: displaying multiple docs per project in a menu bar panel

**Pragmatic start:** One document per project (same as Muninn's landing point). The `update_document` partial-update tool compensates — a single doc with `## sections` is effectively multiple documents in one file. If a document grows too large, that's the signal to revisit multi-doc.

**Future path if needed:** Project becomes a folder, documents become pages within it. `save_document` gains a `title` parameter to address specific pages. But don't build this until the single-doc model breaks.

#### AI workflow

```
Session start (any client, any thread):
  → list_projects()
  → recall_document(project: "PromptCue")
  → AI has full project context

During session:
  → update_document(project: "PromptCue", action: "replace_section",
       section: "Status", content: "Working on HTTP transport...")

Session end:
  → update_document(project: "PromptCue", action: "append",
       content: "## Session 2026-03-15\n### Done\n- ...")
  → Context persists for next session, any client
```

### UX: Memory tab

Warm documents need reading/review, not just glancing. Stack's card list UX doesn't fit. Options explored:

**Chosen approach: Tab switcher in Stack panel**

```
┌─────────────────────────────┐
│ [Stack]  [Memory]           │  ← segment control
├─────────────────────────────┤
│                             │
│  PromptCue          active  │  ← project list
│  muninn             paused  │
│  client-project     active  │
│                             │
└─────────────────────────────┘

tap project → detail view:

┌─────────────────────────────┐
│ ← Back    PromptCue         │
├─────────────────────────────┤
│ ## Session 2026-03-15       │
│ ### Decisions               │
│ - HTTP transport in app...  │
│ ### Done                    │
│ - Claude Desktop config...  │
│ ### Next                    │
│ - Wire up HTTP server...    │
│                        Edit │
│                             │
│ Updated: 2 hours ago        │
└─────────────────────────────┘
```

Can graduate to a separate wider panel later if the narrow panel proves insufficient for long documents. Start simple.

---

## Implementation Plan

| # | Task | Effort | What it unlocks |
|---|------|--------|-----------------|
| 1 | Claude Desktop stdio registration in Settings | S | Claude Desktop as MCP client |
| 2 | `ProjectDocument` model + DB migration + services in PromptCueCore | M | Warm storage layer |
| 3 | MCP Warm tools (save/recall/search/manage_document) | M | AI can save/recall project context |
| 4 | Memory tab UI in Stack panel | M | Human can review/edit documents |
| 5 | HTTP server in Backtick app process | L | ChatGPT Mac App connection |
| 6 | Auth (Bearer token) + Settings UI for HTTP | M | Secure HTTP connections |

**Phase 1 (stdio clients + Warm memory):** #1-4
→ Claude Desktop, Claude Code, Codex can save/recall project documents

**Phase 2 (HTTP transport):** #5-6
→ ChatGPT Mac App connects via localhost HTTP

**Phase 3 (remote access):** Tunnel setup for Claude Web / ChatGPT Web / Mobile
