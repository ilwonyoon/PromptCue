# MCP Platform Expansion & Warm Memory Architecture

Research doc — 2026-03-15 (v4, updated 2026-03-17)

ChatGPT transport note — 2026-03-17:

- this doc previously assumed ChatGPT Mac App could attach to `http://127.0.0.1:<port>/`
- current OpenAI docs now describe ChatGPT custom MCP as a remote-server flow, not a local localhost flow
- treat all ChatGPT sections below as `web-first remote MCP` unless explicitly marked historical
- do not plan product work around localhost-only ChatGPT registration

## Vision

Backtick is the project memory for people who build with AI but aren't engineers. It bridges ChatGPT, Claude, Claude Code, Codex — so that opening a new thread in any app doesn't mean starting from scratch.

Two places, two types of information:

- **Stack:** Today's prompts. Use and discard. Already built.
- **Memory:** Project docs that persist across sessions. Key conversations and decisions from AI chats, continuously updated. Not yet built.

> **Stack for today. Memory for everything else.**

Internal terminology (dev docs only): Hot = Stack, Warm = Memory, Cold = out of scope.
Full terminology system: see `docs/Terminology.md`.

---

## Part 1: Connection Architecture

### Reference: Muninn's proven patterns

Muninn (`ilwonyoon/muninn`) validated the connection model. Key lessons:

| Client | Transport | How it connects |
|--------|-----------|-----------------|
| Claude Code CLI | stdio | `claude mcp add backtick -- <binary>` |
| Claude Desktop (Mac) | stdio | `claude_desktop_config.json` → spawns process |
| Codex CLI | stdio | `codex mcp add backtick -- <binary>` |
| ChatGPT (web-first) | **Remote HTTP MCP** | public HTTPS endpoint registered in ChatGPT Developer Mode |
| Claude Web / Mobile | HTTP + tunnel | Cloudflare Tunnel, ngrok, or Backtick-hosted remote endpoint |
| ChatGPT mobile / desktop apps | Account/app rollout dependent | do not assume parity from the initial connector flow |

**Current correction:** treat ChatGPT as remote-only for product planning. Localhost experiments may have worked historically, but current official docs do not describe localhost MCP as a supported ChatGPT path.

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
└── http mode   → Claude Web, ChatGPT Web, and any future app surfaces that inherit remote MCP connectors
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

#### ChatGPT (remote MCP — experimental future)

1. Backtick exposes an HTTP MCP server locally while the app is running
2. User provides a public HTTPS URL that forwards to that local service, or Backtick hosts the remote endpoint directly
3. ChatGPT Developer Mode registers that public URL as a custom connector
4. Auth is mandatory
5. Start with web-only expectations; app/mobile behavior is a secondary outcome, not the setup baseline

Requires:

- a ChatGPT plan and rollout that actually exposes custom MCP connectors
- a public HTTPS endpoint
- Backtick running continuously if the endpoint is still backed by the local Mac

#### Claude Web / ChatGPT Web (HTTP remote)

For remote use:
1. Backtick HTTP server running locally or a Backtick-hosted remote service
2. Public HTTPS URL exposed through tunnel, relay, or hosted service
3. Public URL registered in Claude Web or ChatGPT web settings

This is a separate remote-MCP track. It should not be framed as a localhost follow-up to the current stdio connector work.

### Connection UX — what the user actually sees

The user never sees "MCP", "stdio", or "HTTP". They see Connect buttons.

```
┌─ Backtick Settings ─────────────────────────────┐
│                                                  │
│  AI Connections                                  │
│                                                  │
│  Claude Desktop         [Connected ✓]            │
│  Claude Code            [Connected ✓]            │
│  Codex                  [Connect]                │
│  ChatGPT                [Connect]                │
│                                                  │
└──────────────────────────────────────────────────┘
```

| Platform | What "Connect" does | User effort |
|---|---|---|
| Claude Desktop | Writes `claude_desktop_config.json` automatically | **One click** |
| Claude Code | Runs `claude mcp add` automatically | **One click** |
| Codex | Runs `codex mcp add` automatically | **One click** |
| ChatGPT | Starts or exposes a remote MCP endpoint, then hands the user a URL and auth flow for ChatGPT web | **Experimental setup** |

ChatGPT is the only connector here that should be treated as a separate remote setup track. Do not promise zero-config onboarding until Backtick owns the remote endpoint and auth flow.

**Principle: the app absorbs the complexity.** Same MCP protocol underneath, but the user never touches it.

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
1. OAuth or Bearer token for remote MCP
2. no-auth localhost only for internal development, never for user-facing ChatGPT setup
```

Any ChatGPT-facing remote path must require auth. If Backtick ships a self-hosted experimental mode, store the secret in Keychain and present clear risk copy before exposing any public URL.

---

## Part 2: Warm Memory — Saving AI Conversations

### What gets saved

The core use case is no longer "AI silently turns a long thread into final docs." The safer default is:

1. AI notices that durable context may be worth saving
2. AI proposes **what** should be stored
3. User reviews or confirms that proposal
4. Only then does AI call `save_document` or `update_document`

Next time any AI client starts a new thread, it recalls the reviewed project context.

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
- Test ChatGPT remote MCP connection against a public HTTPS endpoint
```

This is **not** a full conversation transcript. It's a distilled project document that an AI (or human) can update incrementally after review.

### Default save flow: proposal → review → confirm → write

Muninn showed that "classify a huge thread perfectly at the end" is unreliable. Backtick should therefore treat direct whole-thread saving as a fallback, not the default.

**Default behavior for meaningful conversations:**

1. `list_documents` to see what already exists
2. `recall_document` if a likely matching doc exists
3. propose one of:
   - update an existing doc
   - save one new `discussion` doc
   - save a small reviewed split across a few docs
4. user confirms what should be kept
5. call `save_document` / `update_document`

**Key rule:** automatic multi-document splitting should not be the baseline for a long mixed thread. If the conversation mixes exploration, decisions, and next steps, the safest default is one reviewed `discussion` doc first, then later promotion into `decision`, `plan`, or `reference` as needed.

**Long-thread salvage is fallback behavior.** If a thread is already huge or near context limits, AI may still need to rescue it into one or more docs. But that path should be treated as second-best because classification quality drops sharply once both the user and the model have lost track of what was actually important.

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
    public var documentType: DocumentType // discussion, decision, plan, reference
    public var topic: String             // "branding" — slug
    public var content: String           // markdown body
    public var createdAt: Date
    public var updatedAt: Date
}
// Locked Warm-document key: `(project, topic, documentType)`.

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

#### Backtick Warm tools (phase 1)

| Tool | Purpose | Notes |
|------|---------|-------|
| `save_document` | Create or **supersede** one document version | Addressed by `(project, topic, documentType)`. Full content save. |
| `update_document` | **Partial update** — append, replace section, or remove section | Avoids rewriting the whole document. Key gap in Muninn. |
| `recall_document` | Read one document by `(project, topic, documentType)` | Returns full content for AI context |
| `list_documents` | List active documents in a project, or all projects | Lightweight: summaries only, no full content |

**Later consideration, not phase 1:** `delete_document`, `search_documents`, and project-management helpers. The immediate lane stays small: list, recall, save, and update.

#### Backtick Warm tools (next planning slice)

To support human-reviewed saving as the default behavior, the next toolset planning slice should add a **read-only proposal step** before write tools fire.

| Tool | Purpose | Notes |
|------|---------|-------|
| `propose_document_saves` | Propose 1..N candidate saves or updates for the current discussion | Read-only. Returns topic, `documentType`, whether to create/update, rationale, and a short preview. |

`propose_document_saves` should exist to solve the hardest problem in Warm: **classification under uncertainty**. Instead of forcing the model to save immediately, it lets the model show its proposed split and lets the human choose what is actually worth storing.

Design goals:

- default to **one** proposed `discussion` doc when the thread is long or mixed
- prefer existing topics when an update looks plausible
- only propose multi-doc splits when the boundaries are actually clear
- make the user choose before any write happens

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

#### Document structure: project × topic, with explicit document type

Muninn collapsed everything into one document per project. In practice this breaks — a project like Backtick has discussions about logo, pricing, website, architecture, launch that don't belong in one file.

**Solution: typed project documents, classified by flat topic.**

```
Project: backtick
├── branding       ← logo, colors, tone (accumulated across multiple conversations)
├── pricing        ← pricing model, competitor analysis
├── website        ← landing page, docs structure
├── architecture   ← MCP expansion, Hot/Warm design
└── launch         ← release plan, marketing
```

- **AI can classify by topic** — it knows a logo conversation is "branding". This is the right granularity for AI to handle.
- **Doc type separates shape, topic separates subject** — a long discussion summary, a durable decision doc, and a reusable reference doc should not be forced into one bucket just because they share a topic.
- **Same topic updates across sessions** — discuss logo Monday, revisit Wednesday → branding doc gets updated, not duplicated.
- **Each doc stays bounded** — no single doc grows to unmanageable size.
- **Topic explosion prevention** — AI instruction: "fit into existing topics first, only create new topic if clearly distinct". If a project gets >10 topics, suggest consolidation.

**Addressing scheme:** keep it flat. The Warm-document key is locked as `(project, topic, documentType)`.

```swift
public struct ProjectDocument: Codable, Sendable, Identifiable {
    public let id: UUID
    public var project: String       // "backtick"
    public var documentType: DocumentType // discussion, decision, plan, reference
    public var topic: String         // "branding" — slug, kebab-case
    public var content: String       // markdown body
    public var status: DocumentStatus
    public var createdAt: Date
    public var updatedAt: Date
}
// DB unique constraint for active docs: (project, topic, documentType)
```

**Excluded from scope:** Coding session logs (git history already covers this). Warm is for **discussions and decisions** from ChatGPT/Claude conversations, not development progress from Codex/Claude Code.

#### User-language patterns → document shape

People usually do not say "save a reviewed `decision` document." They say things like:

- "Turn this conversation into a PRD"
- "Write down the latest decisions only"
- "Make a project brief from what we just decided"
- "Save an architecture summary for later"

Backtick should **not** add a separate tool for each phrase. The cross-client contract stays tool-first, and those user asks map into the existing Warm document types:

| User ask | Preferred `documentType` | Preferred tool flow | Why |
|----------|---------------------------|---------------------|-----|
| "Turn this conversation into a PRD" / "Write an implementation brief" | `plan` | `list_documents` → `recall_document` if a matching plan exists → `propose_document_saves` → `save_document` or `update_document` after user confirmation | PRD is a shape of durable execution planning, not a new type |
| "Summarize the latest decisions only" / "Document what we decided" | `decision` | `list_documents` → `recall_document` if a matching decision doc exists → `propose_document_saves` → usually `update_document` after user confirmation | "Latest decisions" is usually a delta against an existing durable decision doc |
| "Save a recap of this discussion" / "Capture what we explored" | `discussion` | `list_documents` → `propose_document_saves` → `save_document` or `update_document` after user confirmation | Discussion docs should preserve options, rationale, and open questions |
| "Save a project brief / architecture summary / constraints" | `reference` or `plan` depending on execution intent | `list_documents` → `recall_document` if matching doc exists → `propose_document_saves` → save after user confirmation | Durable context/constraints are reference; actionable execution framing is plan |

**PRD is not a document type.** It is usually a `plan`-shaped output. "Latest decisions" is usually a `decision` update, not a new doc type.

**Cross-client rule:** keep the core contract tool-first. Claude-side MCP prompts may later expose explicit workflows like `/save-prd` or `/save-latest-decisions`, but ChatGPT Developer Mode currently relies more directly on tool descriptions and argument schemas. Prompt-style shortcuts should be an additive Claude optimization, not the baseline Warm-memory contract.

For manual dogfooding and prompt-based evaluation, use `docs/Warm-MCP-Eval-Plan.md`.

#### Tool description design — making AI proactive

Lesson from Muninn: tool descriptions strongly shape when models recall and save durable context. This is one of the most important design decisions for Warm tools.

After revisiting Muninn more closely, the stronger lesson is that good behavior did not come from tool descriptions alone. Muninn combined:

- **server-wide MCP instructions** that every client received at initialization
- **tool descriptions** for per-tool routing
- optional client-specific workflows later

Backtick should follow the same layering. Warm behavior should not rely on `save_document` wording alone.

**Principles (learned from Muninn):**

| Principle | Tool description pattern | Why |
|-----------|------------------------|-----|
| Context-first recall | "When the current discussion clearly depends on prior saved project context, recall it first" | Prevents re-explaining context |
| Explicit save intent | "Use save only when the user asks to save, preserve, turn into a document, or summarize into durable project context" | Prevents over-eager writes |
| Proposal before write for mixed sessions | "If the thread is long, mixed, or classification is uncertain, propose what to store first and let the user confirm before any write" | Prevents bad end-of-thread auto-classification |
| Recall before save | "Always recall_document first, merge new info, then save back" | Prevents overwriting existing content |
| Fit existing topics | "Check list_documents first. Fit into existing topic if possible. Only create new topic if clearly distinct" | Prevents topic explosion |
| Default to `discussion` under uncertainty | "If preserving a mixed session without clear typed extraction, save one reviewed `discussion` doc first" | Prevents forced multi-doc splits that mix decision/plan/reference badly |
| Pick the smallest durable doc type | "Save long discussion summaries as `discussion`, settled conclusions as `decision`, execution breakdowns as `plan`, and reusable background as `reference`" | Prevents one-topic documents from becoming incoherent catch-alls |
| Translate user language into the right doc shape | "PRD / implementation brief → `plan`; latest decisions → `decision`; discussion recap → `discussion`; architecture summary / durable background → `reference` unless it is clearly an execution plan" | Lets natural user asks map into a stable storage contract |
| Structured content | "Content MUST be markdown with ## headers. Never save a single-line summary. Minimum 200 characters" | Ensures readable documents |
| Exclude noise | "Do NOT save: code snippets, test results, function names, raw conversation logs. Save: decisions, reasoning, status, open questions" | Keeps documents useful |
| Name the surface explicitly | "When speaking to the user, say Backtick (or 백틱 in Korean), not generic memory" | Avoids confusion with ChatGPT/Claude built-in memory |
| Proactive save ask without silent writes | "When a meaningful decision or wrap-up appears, ask whether it should be saved to Backtick. Never save silently." | Recreates the helpful Muninn feel without black-box auto-save |

#### Behavior layers

Warm behavior should be designed in three layers:

1. **Server-wide instructions**
   - set the default attitude for recall and save behavior across all clients
   - examples:
     - project mentioned → recall first
     - meaningful decision reached → ask whether to save to Backtick
     - never save silently
     - call it Backtick / 백틱, not generic memory

2. **Tool descriptions**
   - define routing and argument discipline per tool
   - examples:
     - `save_document` is user-confirmed write behavior
     - `update_document` wins over full save for narrow deltas
     - `discussion` is the fallback when classification is uncertain

3. **Client-specific prompts/workflows**
   - optional optimization layer
   - Claude-side prompt shortcuts may later improve the experience, but the baseline should already work from server instructions + tool descriptions

This layering matters because the pleasant Muninn behavior on Claude Mac / iPhone came from the MCP instructions surface, not from Claude Code hooks.

**Draft tool descriptions:**

```
propose_document_saves:
  "Review the current discussion and propose what, if anything,
   should be stored in Backtick. Use this before writing when the
   conversation is long, mixed, or classification is uncertain.
   Prefer one reviewed `discussion` doc by default unless the
   boundaries between `decision`, `plan`, or `reference` docs are
   clearly separated. Return candidate topic, documentType,
   create-vs-update recommendation, rationale, and a short preview.
   Do not write anything."

recall_document:
  "Load a project topic document when the current discussion
   clearly depends on prior saved project context. Recall
   before answering when durable context is likely to matter."

save_document:
  "Save or replace a project topic document. Use this only
   when the user asks to save, preserve, turn a conversation
   into a document, or summarize it into durable project
   context, and preferably after the user confirms a proposed
   save. Do not directly split a long mixed thread into
   multiple typed docs by default. If classification is
   uncertain, propose first or save one reviewed `discussion`
   doc. PRD / implementation brief usually maps to `plan`;
   latest settled choices usually map to `decision`; discussion
   recap maps to `discussion`; durable background or
   constraints map to `reference`. ALWAYS list or recall first
   so you do not overwrite the wrong document. Content must be
   full markdown with ## section headers — never a single-line
   summary."

list_documents:
  "List all topics in a project, or all projects. Call before
   save_document to check if a matching topic already exists.
   Use this first when the project is known but the right
   topic or documentType is unclear."

update_document:
  "Partially update a document — append, replace, or remove
   a section. Prefer this over save_document for small changes,
   such as latest-decision deltas or one section of an existing
   plan/reference/doc. Always specify section header for
   replace/delete actions."
```

#### Content quality rules

What AI should save:
- Key decisions with reasoning ("chose freemium because...")
- Project status and direction changes
- Open questions and unresolved debates
- Agreed-upon specs or requirements

What AI should NOT save:
- Code, function names, test results (git history covers this)
- Raw conversation transcripts
- Implementation details that change daily
- Anything already in the repo (CLAUDE.md, README, etc.)

#### Human review is essential

AI-saved content needs verification. The Memory panel exists for this:

```
AI saves document via MCP
    │
    ├→ Document appears in Memory panel
    │  (user sees "Updated 2 min ago" badge)
    │
    ├→ User opens, reads, edits if needed
    │  (fix wrong decisions, add missing context, delete noise)
    │
    └→ Next AI session recalls the human-verified version
```

The review loop is what makes this different from Mem0 (black box, user can't see what's stored) and Pluro (auto-collected, no curation).

**Refinement after dogfooding:** review should happen **before** write when possible, not only after. The best default is:

- AI proposes what to save
- user confirms or trims the proposal
- AI writes the confirmed subset
- Memory panel remains the later correction surface, not the first line of defense

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

Session end:
  → AI: "오늘 가격 모델 쪽은 기존 `decision` 문서를 업데이트하고, 배포 쪽은 새 `discussion` 문서로 저장하는 게 맞아 보여요. 저장할까요?"
  → User: "가격만 저장해"
  → update_document(project: "backtick", topic: "pricing", ...)

Next day, different AI client, new thread:
  → list_documents(project: "backtick")
  → recall_document(project: "backtick", topic: "distribution")
  → Continues where yesterday left off (human-verified version)
```

### Customer-facing terminology

Full terminology system documented in `docs/Terminology.md`. Key decisions:

#### Places (two, no more)

| Internal | User-facing | What it is |
|----------|------------|-----------|
| Hot | **Stack** | Short-term prompt queue. Auto-expires. |
| Warm | **Memory** | Long-term project documents. Persists across sessions. |

#### Objects (different words signal different nature)

| Place | Objects called | Example header |
|---|---|---|
| Stack | **prompts** | `4 prompts` |
| Memory | **docs** | `3 docs` |

"prompts" = short, disposable. "docs" = long, structured. Different words prevent "what's the difference?" confusion.

#### States (label the exception, not the norm)

| State | Label | Meaning |
|---|---|---|
| Default (uncopied prompt) | _(no label)_ | Just a prompt. No special state. |
| After copy | **Copied** | Moves to collapsed Copied section. |

"On Stage" / "Off Stage" retired. Default state doesn't need a name — only label the action that happened.

#### Stack panel simplification

Filter (All / On Stage / Off Stage) removed entirely. Unnecessary complexity.

```
┌─────────────────────────────┐
│  4 prompts        [Copy ⊕] │  ← uncopied count + action
├─────────────────────────────┤
│  [prompt]                   │
│  [prompt]                   │
├─────────────────────────────┤
│  Copied  2           [▼]   │  ← collapsible, delete-all
└─────────────────────────────┘
```

#### Naming principles

1. First-time user must understand the word without explanation
2. Internal concepts (Hot/Warm/Cold, Card, Stage) stay in code — never in UI
3. When in doubt, use fewer words

**Brand line:** "Stack for today. Memory for everything else."

Alternatives considered for Memory:

| Name | Why not |
|------|---------|
| Notes | Too generic. Confused with Apple Notes. |
| Vault | Security connotation. Obsidian already owns this. |
| Brain | Overused by competitors. Overpromises. |
| Docs | Google Docs association. (But "docs" lowercase as object name is fine.) |
| Log | Developer-facing. |

### UX: Memory panel

Warm documents need reading/editing, not glancing. Stack's narrow card-list UX doesn't fit long markdown. Memory gets its **own panel** — same pattern as Capture and Stack (separate NSPanel, own hotkey).

#### Design references

| App | What to learn | Link |
|-----|--------------|------|
| [Meny](https://apps.apple.com/us/app/meny/id1671366999?mt=12) | Menu bar → markdown panel. WYSIWYG rendering. Minimal chrome. Closest reference for document detail view. | App Store |
| [FiveNotes](https://www.apptorium.com/fivenotes) | 5 notes, color dot switcher (→ topic chips). Pin button for floating. Intentional constraint as UX. | apptorium.com |
| [NotesBar](https://github.com/aman-senpai/NotesBar) | Obsidian notes from menu bar. File list → hover preview. Search built-in. Closest reference for list → detail navigation. | GitHub |

**What to borrow:**
- **From NotesBar:** List → preview 2-step navigation. Built-in search. File browser feel.
- **From FiveNotes:** Topic switcher via chips (instead of file tree). Pin/float mode. Constraint-driven simplicity.
- **From Meny:** Clean markdown rendering in a narrow panel. Edit-in-place without mode switch.

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

## Lessons from Muninn (ilwonyoon/muninn)

109 commits over 3 weeks. Peak ~3,900 LOC → stripped to ~1,800 LOC. The project's evolution is a masterclass in what to build and what to cut.

### Timeline

| Phase | Period | What happened |
|-------|--------|---------------|
| Foundation | Feb 24-25 | 5 MCP tools, SQLite+FTS5, depth hierarchy, 73 tests |
| Over-engineering | Feb 25-27 | Added OAuth, semantic search, Docker, graph UI, 8 categories |
| Aggressive rollback | Feb 27 | Removed ~2,200 LOC. "These features don't serve single-user stdio." |
| Hardening | Feb 28-Mar 3 | 9 security fixes, 12 stability fixes, 17 perf improvements |
| Turso mistake | Feb 28-Mar 5 | Tried libSQL cloud replication → "database is locked" → reverted to pure local SQLite |
| Document-first pivot | Mar 3-5 | Removed atomic memory CRUD from tools. One document per project. **Most important change.** |

### What worked — bring to Backtick

| Pattern | Why it worked | Backtick application |
|---------|--------------|---------------------|
| **Document-first design** | One structured doc per project > scattered fragments. LLM knows what to update. | ProjectDocument model. `save_document` replaces whole doc, not fragments. |
| **Tool docstrings as AI instructions** | Docstrings shape LLM behavior. Examples improve compliance ~40%. | Warm tool descriptions with examples, format rules, proactive behavior hints. |
| **Per-operation DB connections** | Persistent connections caused "database is locked" when multiple clients ran. | GRDB's `db.write { }` / `db.read { }` blocks already do this. Don't hold connections. |
| **Explicit transactions** | Multi-statement writes without BEGIN/COMMIT → partial commits. | `db.inTransaction { }` for all multi-step mutations. |
| **Keyword search (FTS5)** | Semantic/vector search was removed — keyword search was sufficient and simpler. | FTS5 on `project_documents` table. Don't add embeddings unless keyword fails. |
| **Format validation in tool layer** | Reject empty/unstructured content immediately. Return error string, never crash. | MCP tools validate markdown headers, min length, return error messages. |
| **Frozen/immutable models** | Thread-safe across concurrent clients. Prevents accidental mutation. | Swift structs (already the pattern in PromptCueCore). |
| **Character budgets on recall** | Prevents context window overflow when loading documents. | `recall_document` should respect budget, paginate if needed. |
| **Integration tests with real SQLite** | Temp database per test. No mocks for DB layer. | Already the pattern in BacktickMCPServerTests. |

### What failed — don't repeat

| Mistake | What happened | Backtick lesson |
|---------|--------------|-----------------|
| **Semantic search / embeddings** | 320 LOC added then removed. Users search by keyword, not intent. Vector drift caused false positives. | **Don't add.** FTS5 keyword search is enough. |
| **OAuth 2.0** | 420 LOC for multi-user auth. Single-user app doesn't need federation. | **Bearer token only.** Generated in Settings, stored in Keychain. |
| **Turso / cloud DB** | libSQL cloud replication caused WAL checkpoint blocking. "database is locked" everywhere. | **Pure local SQLite.** Don't add cloud sync for a local-first app. |
| **Persistent DB connections** | Multiple clients (CLI, Desktop, HTTP) holding connections → deadlocks. | **Per-operation connections.** GRDB handles this natively. |
| **Atomic memory CRUD** | LLMs created 10 fragments per session instead of one coherent document. Unusable. | **Document-first.** save_document replaces whole doc. update_document edits sections. No create_memory. |
| **Complex depth/category hierarchy** | 8 categories, L0-L3 depth levels. LLMs couldn't consistently classify. | **Flat structure.** project × topic only. No depth levels. |
| **Graph UI** | Visual tree navigation. Users used search instead. Never navigated hierarchy. | **List + search.** No tree views. |
| **Building infra before validating core** | OAuth, Docker, graph UI before confirming "do LLMs maintain memory coherence?" | **Ship Stack first (done). Validate Warm with real usage before adding HTTP/tunnel.** |
| **Vercel serverless attempt** | Duplicated 500+ LOC Python→TypeScript for Next.js API routes. | **One runtime.** BacktickMCP is Swift. Don't duplicate logic. |
| **Soft-deleted records never cleaned** | Superseded memories accumulated indefinitely. | **Add cleanup policy.** Archived documents can be purged after N days. |

### The document-first pivot — critical lesson

Before: LLMs called `create_memory(content, depth, tags)` → 10 fragments per session. Incoherent.

After: LLMs call `save_document(project, content)` → One structured markdown doc. Must have `##` headers. Replaces previous version.

**This is the single most important architectural decision for Warm.** Backtick's `save_document` / `update_document` tools must enforce:
1. Full markdown with `##` headers (reject plain text)
2. Minimum content length (reject single-line saves)
3. recall before save (prevent overwriting existing content)
4. One document per (project, topic) — not fragments

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

### Product pitch

#### For consumers

Every time you open a new ChatGPT thread or start a new Claude conversation, you start from scratch. "I'm building this app, the pricing model is freemium, we decided on this color palette last week..." — every. single. time.

Backtick fixes this. Cmd+` to dump a thought. Your AI tools pick it up instantly via Stack. Important decisions and project context get saved to Memory — so next week, in a different AI app, in a brand new thread, your AI already knows.

**Stack for today. Memory for everything else.**

No setup. No API keys. No terminal commands. Install the app, click Connect, done.

#### For investors

**Category:** Cross-platform AI memory — consumer product, not infrastructure.

**Market observation:**
- LLMs are stateless. Every session starts from zero.
- Users switch between 3-4 AI tools daily (ChatGPT, Claude, Codex, Cursor...)
- Each platform's built-in memory is siloed — ChatGPT Memory doesn't talk to Claude Projects.
- The cross-platform memory layer is an empty category.

**Backtick's position:**

```
  ChatGPT ──┐
  Claude  ──┼── Backtick ── user's context
  Codex   ──┘     (MCP)
```

**Competitive moat:** Not technology (MCP is an open protocol) — **UX.** The only product where a non-developer can install a .app file, click "Connect to Claude", and have cross-platform AI memory running in under a minute. Every competitor requires Docker, API keys, config files, or terminal literacy.

**Target:** AI-native solopreneurs — non-developers building products with AI. This segment is growing fast and is underserved by developer-focused tools.

---

## Deep Dive: Felix (OpenClaw) — Autonomous AI Agent Memory

Research date: 2026-03-15. Felix is the most visible example of an autonomous AI agent with persistent memory. Not a direct competitor (different category), but the memory architecture has lessons for Backtick.

### What Felix is

Felix is an "AI CEO" persona built on **OpenClaw** (open-source autonomous AI agent framework, Peter Steinberger, 187K+ GitHub stars). Created by Nat Eliason (nateliason.com — content marketer, author of *Crypto Confidential* and *Husk*). Runs on a Mac Mini, $400/month (Claude Max + Codex Max). Claims ~$134K+ revenue from PDF sales, Claw Mart marketplace fees, and $FELIX crypto token.

Felix codes (via Codex in tmux), handles email, posts to X/Twitter, manages sub-agents (Iris for support, Remy for sales), and runs autonomously for 4-6 hours on task lists.

### Three-Layer Memory Architecture

**Not RAG. Not vector DB. Plain markdown files on local filesystem.**

| Layer | Storage | Purpose |
|---|---|---|
| **Knowledge Base** | `~/life/` folder (PARA structure: projects/areas/resources/archives) | Entity folders. Each entity: `summary.md` (current state, 3-5 sentences) + `items.json` (append-only fact history) |
| **Daily Notes** | `memory/YYYY-MM-DD.md` | Raw timeline of each day's conversations. Fallback if extraction misses something |
| **Tacit Knowledge** | `SOUL.md` + `USER.md` | Communication preferences, workflow rules, personality. Injected into system prompt every session |

#### Entity creation threshold

Create entity folder only if: mentioned 3+ times, has direct relationship to user, or is a significant project/company. Otherwise facts stay in daily notes. **Prevents knowledge base bloat.**

#### Temporal decay

Exponential multiplier on search scores based on age. Default half-life: 30 days. Recent memories rank higher, old ones fade but are never deleted. Tiers: Hot (last 7 days, auto-loaded) → Warm (consolidated from daily notes) → Cold (searchable but not auto-loaded).

#### Consolidation cadence

- **Heartbeat (every 30 min):** Cron job scans recent conversations, extracts "durable facts" (decisions, new people, status changes). Skips casual chat. Uses cheap model (~$0.005/day).
- **Nightly review:** Felix writes a diary, updates SOUL.md, re-examines and reprograms sub-agents (Iris, Remy), consolidates daily notes into entity files.
- **Not a wholesale rebuild** — incremental extraction. Stale summaries refreshed, completed projects archived.

#### Graceful degradation — the key design insight

```
Knowledge Base summary stale?  → items.json has full fact history
Heartbeat extraction missed it? → Daily notes have the raw timeline
Daily notes incomplete?         → Conversation history itself is preserved
```

Every layer is a fallback for the layer above. Data is never lost even when individual layers fail.

#### Search backend

Default: SQLite-based indexing of markdown files. Optional upgrade: QMD (local-first BM25 + vector embeddings + reranking). Markdown stays source of truth either way.

### Technical stack

| Component | Detail |
|---|---|
| Framework | OpenClaw (open source, local-first) |
| LLM (conversation) | Claude Pro Max ($200/month) |
| LLM (coding) | Codex Max ($200/month) |
| Communication | Telegram (primary), X/Twitter (public) |
| Coding | tmux sessions + "Ralph loops" (execution harnesses for Codex/Claude Code) |
| Memory | Plain markdown + JSON, local filesystem, SQLite indexing |
| Scheduling | OpenClaw cron jobs (heartbeat 30 min, nightly reviews) |
| Personality | SOUL.md injected into system prompt every message |

### What Backtick should learn

| Felix pattern | Backtick application | Priority |
|---|---|---|
| **Graceful degradation** | If a Memory doc is stale, show "last updated X ago" warning. AI recalls + offers to update. Data never lost. | High — design principle |
| **Entity creation threshold** | Topic explosion prevention: "fit existing topics first, create new only if clearly distinct" — already in our tool descriptions. Validated by Felix's 3-mention rule. | High — already planned |
| **Temporal decay** | `updatedAt`-based weighting in `search_documents` results. Recent docs rank higher. 30-day half-life is a pragmatic default. | Medium — add to search |
| **Markdown as source of truth** | Felix validates that plain text + FTS is sufficient. No vector DB needed. Our SQLite + FTS5 approach is correct. | High — confidence boost |
| **Tool descriptions as behavior instructions** | Felix's SOUL.md = Backtick's MCP tool descriptions. Same mechanism, different form factor. Both shape AI behavior proactively. | High — already planned |

### What Backtick should NOT adopt

| Felix pattern | Why it doesn't fit |
|---|---|
| Heartbeat (30-min autonomous execution) | Backtick is a user tool, not an autonomous agent. No self-initiated actions. |
| Sub-agent management (Iris, Remy) | Out of scope. Backtick is memory, not an agent orchestrator. |
| PARA folder hierarchy | Over-structured for our use case. Flat `project × topic` is simpler and sufficient. |
| Cron-based extraction | Backtick saves in real-time via MCP tool calls. No need for batch extraction. |
| SOUL.md personality file | Backtick has no persona. Tool descriptions carry the behavioral instructions. |
| Nightly self-review / diary | Requires agent autonomy. Backtick's "review loop" is the human checking Memory panel. |

### Felix vs Backtick — fundamental difference

| | Felix | Backtick |
|---|---|---|
| **What** | AI that works for you | Tool you work with |
| **Memory purpose** | Agent remembers its own context | User's project context shared across AI tools |
| **Storage** | Markdown files (local) | SQLite + FTS5 (local) |
| **Consolidation** | 30-min heartbeat + nightly review (autonomous) | Real-time via MCP tool calls (user-triggered) |
| **Quality control** | Nat occasionally checks | **Required** — Memory panel for human review |
| **Target** | Delegate business to AI | Build with AI yourself |
| **Cost** | $400/month | Free app (uses user's existing AI subscriptions) |

### Key takeaway

Felix's memory works because **every layer degrades gracefully into the layer below**. The three-layer structure is overkill for a user tool, but the degradation principle applies directly: Backtick should never lose data, and stale data should be visibly flagged so the user (or AI) can refresh it.

The revenue claims ($134K+) should be viewed with caution — crypto token activity, self-reported numbers, and Bankless/crypto audience amplification muddy the picture. The technical approach is legitimate regardless.

### Sources

- [Nat Eliason X thread: Inside Felix](https://x.com/nateliason/status/2024953009524932705)
- [Nat Eliason X thread: Agentic PKM with PARA and QMD](https://x.com/nateliason/status/2017636775347331276)
- [Bankless podcast: Building a Million Dollar Zero Human Company](https://www.bankless.com/podcast/building-a-million-dollar-zero-human-company-with-openclaw-nat-eliason)
- [CreatorEconomy.so full tutorial](https://creatoreconomy.so/p/use-openclaw-to-build-a-business-that-runs-itself-nat-eliason)
- [OpenClaw docs: memory](https://docs.openclaw.ai/concepts/memory)
- [OpenClaw docs: heartbeat](https://docs.openclaw.ai/gateway/heartbeat)
- [Felix on Claw Mart](https://www.shopclawmart.com/listings/felix-04f42dee)
- [BetterClaw: OpenClaw Memory Fix](https://www.betterclaw.io/blog/openclaw-memory-fix)

---

## Implementation Plan

### Critical constraint: Warm must not block app launch

Capture + Stack (Hot) is the shipping product. Warm (Memory) is a post-launch feature track. Zero code from Warm work may touch Capture/Stack files. If a Warm task creates risk for launch, it gets deferred.

### Phasing

**Pre-launch (ship Capture + Stack):**

| # | Task | Effort | Status | What it unlocks |
|---|------|--------|--------|-----------------|
| 1 | Claude Desktop stdio registration in Settings | S | **✅ DONE** (PR #58, 2026-03-17) | Claude Desktop as MCP client for existing Hot tools |
| 1b | Pin feature — permanent prompt cards | M | **✅ DONE** (commit `28ee95f`, 2026-03-17) | Pinned cards never expire, horizontal carousel UI |

Claude Desktop connector: one-click config write to `claude_desktop_config.json`, no CLI required. Includes `usesDirectConfig` guard, error logging, and full test coverage.

**Post-launch Phase 1 (Warm memory via stdio):**

| # | Task | Effort | Status | What it unlocks |
|---|------|--------|--------|-----------------|
| 2 | `Project` + `ProjectDocument` models + DB migration + services | M | Not started | Warm storage layer |
| 3 | MCP Warm tools (save/update/recall/list/delete/search/manage) | M | Not started | AI can save/recall project context |
| 4 | Memory panel (NSPanel, project list → topic list → doc viewer/editor) | M | Not started | Human can review/edit AI-saved documents |

→ Claude Desktop, Claude Code, Codex can save/recall project documents. Human reviews in Memory panel.

**Post-launch Phase 2 (HTTP transport):**

| # | Task | Effort | Status | What it unlocks |
|---|------|--------|--------|-----------------|
| 5 | HTTP server in Backtick app process | L | **✅ DONE (experimental, 2026-03-18)** | Remote MCP foundation for ChatGPT / Claude web |
| 6 | Auth (OAuth or Bearer) + Settings UI for HTTP | M | **✅ DONE (experimental, 2026-03-18)** | Secure remote MCP connections |

→ This now unlocks an experimental self-hosted ChatGPT connector on `main`. The current path is advanced-user only: Backtick must stay running, the user brings a public HTTPS URL/tunnel, and ChatGPT web completes OAuth approval. Do not assume localhost registration or app/mobile parity.

**Post-launch Phase 3 (stability only):**
Keep the current self-hosted ChatGPT / Claude Web path usable for advanced users. `BYO tunnel` is now started through `ngrok`-guided self-hosted setup in Settings, but reconnect/reset/health UX remains incomplete. Hosted relay / managed distribution is not part of the current roadmap.

**Read-this-first scope split:**

- **Shipped on `main` today:** Stack note MCP for `Claude Desktop`, `Claude Code`, and `Codex`, plus pinned prompt cards in Stack
- **Experimental on `main` today:** self-hosted ChatGPT remote MCP over HTTP + OAuth
- **Research / post-launch only:** Warm memory documents, `documentType` contract, Memory panel, and Warm MCP tools

This matters because the broader research below includes both shipped Stack MCP work and future Warm-memory ideas. Do not read every section as current implementation scope.
