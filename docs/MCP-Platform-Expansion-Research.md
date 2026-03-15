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

Memory panel UI must follow the existing two-layer token system AND the system-inherit theme model.

#### Token layers

- **`PrimitiveTokens`** → `FontSize`, `LineHeight`, `Space`, `Radius`, `Shadow`, `Size`, `Stroke`, `Opacity`, `Motion`, `Typography`
- **`SemanticTokens`** → `Surface`, `Text`, `Border`, `Accent`, `Shadow`, `MaterialStyle`, `Classification`
- **`PanelBackdropFamily`** → Panel-specific shell fills, strokes, highlights (light/dark variants)
- **`SettingsSemanticTokens`** → Settings-specific tokens (if Memory settings needed)

#### System-inherit theme model (latest)

The app no longer has a user-facing Light/Dark/Auto toggle. It inherits macOS system appearance via `NSApp.appearance = nil`.

**What Memory panel must implement:**
1. **`adaptiveColor(light:, dark:)`** — All new semantic colors must use this helper, which resolves at runtime based on `NSAppearance.bestMatch()`. Never use static `Color.white`/`Color.black`.
2. **`refreshForInheritedAppearanceChange()`** — `MemoryPanelController` must implement this method (same as `StackPanelController`). Called by `AppCoordinator` when system theme flips. Must: set `panel.appearance = nil`, invalidate shadows, clear cached layer contents, force re-render.
3. **`@Environment(\.colorScheme)`** — SwiftUI views that need appearance-conditional logic use this environment value, not manual appearance checks.
4. **`PanelBackdropFamily`** — Memory panel needs its own backdrop entry (or reuses Stack's if visually identical). Light/dark fill + stroke + highlight variants.
5. **`AppleInterfaceThemeChangedNotification`** — Already observed by `AppCoordinator`. Just add `memoryPanelController.refreshForInheritedAppearanceChange()` to the existing handler.

**Key files to reference:**
- `SemanticTokens.swift` — `adaptiveColor()` helper, all semantic color definitions
- `PanelBackdropFamily.swift` — Panel backdrop light/dark variants
- `StackPanelController.swift` — Reference implementation of `refreshForInheritedAppearanceChange()`
- `AppCoordinator.swift` (lines 32-47, 223-248) — Theme change observer

#### Specifics for Memory panel

- Panel chrome: `PanelBackdropFamily` backdrop (define Memory variant or reuse Stack's)
- Project list rows: `Space`, `Radius`, `Text.primary`/`Text.secondary`
- Topic chips: `Accent` + `Radius.small`
- Document viewer: `Text.primary` for body, `Text.secondary` for metadata, `Typography` for markdown heading styles
- Edit button: same button style tokens as Stack
- Status badges (active/paused/archived): `Classification` tokens
- No hardcoded colors, spacing, radius, fonts, or shadows

**Validation:** `python3 scripts/validate_ui_tokens.py` must pass with all new Memory panel views included.

---

## Competitive Analysis & Positioning

### Landscape: Who's solving AI memory?

#### 1. Mem0 / OpenMemory MCP — "Developer Infrastructure"

Memory layer for AI coding agents. Stores atomic facts ("user prefers dark mode") in vector DB. Requires Docker + Postgres + Qdrant + OpenAI API key.

- **Target:** Developers building AI agents
- **Weakness:** [Memory corruption bugs](https://github.com/mem0ai/mem0/issues/3322) (names stripped from facts), [Claude Desktop compatibility issues](https://github.com/mem0ai/mem0/issues/3400), no consumer UX, stores memory fragments not readable documents
- **Gap:** Normal people can't install this. And atomic facts ≠ project context.

#### 2. Pluro — "Consumer Memory Aggregator"

Unifies ChatGPT/Claude/Gemini conversations via auto-indexing. Vector embeddings for search. Local encryption.

- **Target:** Consumers
- **Weakness:** Early stage (not in [Top 10 AI Memory Products 2026](https://medium.com/@bumurzaqov2/top-10-ai-memory-products-2026-09d7900b5ab1)), auto-collects everything (no curation), unclear if MCP-based, no native app
- **Gap:** Collects conversations but doesn't structure them. Information overload without organization.

#### 3. Obsidian + Claude Code — "DIY Knowledge Base"

Local markdown files + Claude Code reads `CLAUDE.md` + `memory.md`. [Popular setup](https://www.whytryai.com/p/claude-code-obsidian).

- **Target:** Developers who use Obsidian
- **Weakness:** ChatGPT not connected, fully manual maintenance, requires technical literacy, not an app but a workflow
- **Gap:** Only works with Claude Code. Manual curation is the user's job.

#### 4. Amir Klein / Lenny's Newsletter — "Manual Second Brain"

[PM at monday.com dumps project context into ChatGPT Projects](https://www.lennysnewsletter.com/p/how-to-build-your-pm-second-brain). Manual copy-paste from Slack, Notion, Google Docs.

- **Target:** PMs, non-technical power users
- **Weakness:** 100% manual, no cross-platform sync (ChatGPT Project ≠ Claude Project), doesn't scale past 5 projects
- **Gap:** The pain is real (his article went viral), but the solution is brute-force.

#### 5. MCP Memory Keeper / mcp-memory-service — "Coding Agent Tools"

SQLite/semantic memory for coding assistants. CLI-only.

- **Target:** Coding agents exclusively
- **Gap:** Not relevant to non-developers.

#### 6. Platform-native memory (ChatGPT Memory, Claude Memory)

Built-in memory features in each platform.

- **Target:** Everyone
- **Weakness:** Siloed within each platform, auto-extracted (user can't control what's saved), no cross-platform sharing, saves preferences not project documents
- **Gap:** Won't solve cross-tool context. Each vendor has no incentive to share with competitors.

### Gap map

```
                    Developer ←——————————→ Consumer
                       │                      │
  Structured docs      │                      │
  (project/topic)      │    ← EMPTY →         │
                       │                      │
  Memory fragments     │  Mem0                │
  (atomic facts)       │                      │
                       │                      │
  Auto-collected       │              Pluro   │
  (everything)         │                      │
                       │                      │
  Manual dump          │       Obsidian  Amir │
                       │       +Claude  Klein │
```

**The empty quadrant:** Structured, readable project documents × consumer/prosumer UX. No product occupies this space.

### Target user: Vibe-coding solopreneurs

Not developers at tech companies (they have scoped work, limited context switching). The target is **non-developer vibe coders building their own products** — people who:

- Use ChatGPT for business decisions (pricing, branding, marketing)
- Use Claude for writing and research
- Use Claude Code / Codex for vibe-coding their product
- Run 3-5 projects simultaneously, each with wildly different context
- Context-switch constantly because they're solo — no team to delegate to
- Have no engineering background to set up Docker, Postgres, or manage config files

**Why this user needs Backtick specifically:**

1. **Most context switching of anyone** — A solopreneur building a SaaS discusses logo in ChatGPT, debates pricing in Claude, vibe-codes the feature in Claude Code, drafts marketing copy in ChatGPT — all in one day, across 4 different AI clients
2. **Can't use developer tools** — Mem0 requires Docker. Obsidian+Claude Code requires terminal literacy. These users install .app files, not run `docker-compose up`
3. **Manual dump doesn't scale** — Amir Klein's approach works for 1-2 projects. A solopreneur with 3 side projects and a freelance gig has 4+ active contexts
4. **Needs both Hot and Warm** — "deploy the fix" (Hot, today) AND "we decided on freemium pricing" (Warm, persists) live in the same workflow

### Backtick's positioning

**"AI가 정리하고, 사람이 확인하는 프로젝트 메모리"**

| Dimension | Mem0 | Pluro | Obsidian+CC | Manual dump | **Backtick** |
|---|---|---|---|---|---|
| Install | Docker+DB | Easy? | Medium | None | **One .app** |
| Info unit | Memory fragment | Auto-collected chat | Markdown file | Copy-paste | **project × topic doc** |
| Curation | AI auto-extracts | AI auto-collects | Human manual | Human manual | **AI saves + human reviews** |
| ChatGPT | Limited | Yes | No | ChatGPT only | **MCP (HTTP)** |
| Claude | Buggy | Yes | Claude Code only | Claude only | **MCP (stdio+HTTP)** |
| Native app | No (web dashboard) | Web? | Obsidian | None | **macOS native** |
| Today's tasks | No | No | No | No | **Stack (Hot)** |
| Target | Developers | Consumers | Dev+Obsidian | PMs | **Vibe-coding solopreneurs** |

**One-liner:** Backtick is the project memory for people who build with AI but aren't engineers.

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
