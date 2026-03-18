# MCP Platform Expansion & Warm Memory Architecture

Research doc — 2026-03-15 (v4, updated 2026-03-17)

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
| ChatGPT Mac | Starts HTTP server + copies URL to clipboard + opens ChatGPT settings | **One click + paste URL** |

ChatGPT is the only one that can't be fully automated (ChatGPT doesn't provide an auto-registration API). But "click Connect → paste URL" is still zero-config for the user — no terminal, no JSON editing, no API keys to generate.

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

#### Tool description design — making AI proactive

Lesson from Muninn: Claude proactively asks "이거 저장할까요?" because the tool descriptions tell it to. The tool description IS the AI's behavioral instruction. This is the single most important design decision for **both Hot and Warm tools**.

**External research backing this claim:**

| Source | Finding |
|--------|---------|
| [Tenable: MCP Prompt Injection](https://www.tenable.com/blog/mcp-prompt-injection-not-just-for-evil) | Tool `description` field alone can force LLMs to call a tool before every other tool. Description = behavioral instruction, not documentation. |
| ["Smelly Descriptions" (arXiv:2602.14878)](https://arxiv.org/abs/2602.14878) | 97.1% of MCP tools have description defects. Adding **Guidelines** (when/why to use) improves task success +5.85pp. But all 6 components = 67% more tokens → **Guidelines + Purpose only** is the sweet spot. |
| [MCP Memory Server](https://github.com/modelcontextprotocol/servers/tree/main/src/memory) | Anthropic's official pattern: minimal tool description + companion system prompt ("Always begin by retrieving all relevant information"). |
| [Anthropic: Writing effective tools](https://www.anthropic.com/engineering/writing-tools-for-agents) | "Treat descriptions as prompt engineering." Namespace related tools. Return human-readable context. |
| Cursor Memories failure (v2.1.x removed) | Auto-accumulated facts → unpredictable behavior → rolled back to static Rules files. Lesson: human review loop is essential. |

**⚠️ Opus 4.6 caveat**: Anthropic warns newer models are significantly more proactive. Descriptions that worked for older models may cause over-triggering. Always include an "ask the user before saving" gate for write operations.

**Principles (learned from Muninn + external research):**

| Principle | Tool description pattern | Why |
|-----------|------------------------|-----|
| Proactive recall | "When user mentions a project, recall immediately — do not wait to be asked" | Prevents re-explaining context |
| Proactive save | "At session end, offer to save key decisions and context" | User doesn't have to remember to save |
| Recall before save | "Always recall_document first, merge new info, then save back" | Prevents overwriting existing content |
| Fit existing topics | "Check list_documents first. Fit into existing topic if possible. Only create new topic if clearly distinct" | Prevents topic explosion |
| Structured content | "Content MUST be markdown with ## headers. Never save a single-line summary. Minimum 200 characters" | Ensures readable documents |
| Exclude noise | "Do NOT save: code snippets, test results, function names, raw conversation logs. Save: decisions, reasoning, status, open questions" | Keeps documents useful |

**Draft tool descriptions:**

```
recall_document:
  "Load a project topic document. Call proactively when user
   mentions a project — do not wait to be asked. Proactive
   recall prevents context re-explanation."

save_document:
  "Save or replace a project topic document. At session end,
   proactively offer to save key decisions and context. ALWAYS
   call recall_document first to avoid overwriting existing
   content. Content must be full markdown with ## section
   headers — never a single-line summary."

list_documents:
  "List all topics in a project, or all projects. Call before
   save_document to check if a matching topic already exists.
   Fit new content into existing topics when possible."

update_document:
  "Partially update a document — append, replace, or remove
   a section. Prefer this over save_document for small changes.
   Always specify section header for replace/delete actions."
```

#### Hot (Stack) tool description improvements — immediate action

The same principles apply to existing Hot tools. Current descriptions are functional but lack Guidelines (when to call). This is Phase 1 work — zero cost, high leverage.

**Current vs. improved:**

| Tool | Current description | Problem | Improved description |
|------|-------------------|---------|---------------------|
| `list_notes` | "List Stack notes grouped by category: pinned, active, and copied." | No trigger guidance — AI doesn't know when to call | "List the user's Stack notes from Backtick. **Call this at the start of a new task, when the user mentions a project or topic that might have prior notes, or when you need background before making a recommendation.** Notes contain prompts, decisions, and action items saved from previous AI sessions." |
| `create_note` | "Create a Stack note directly in Backtick storage." | No proactive save guidance | "Save important context, decisions, or action items to Backtick for use in future AI sessions. **Call this when the conversation produces reusable knowledge — project decisions, task outcomes, or anything the user might need in a different tool or session. Ask the user before saving.**" |
| `get_note` | "Fetch one Stack note and its copy-event history." | OK — naturally follows list | No change needed |
| `update_note` | "Update Stack note text or metadata without copying it." | OK | No change needed |
| `delete_note` | "Delete a Stack note directly from Backtick storage." | OK | No change needed |
| `mark_notes_executed` | "Mark Stack notes executed by recording copied state..." | OK | No change needed |

**Three-layer retrieval design** (redundant — any one layer working = retrieval happens):

1. **MCP resource** (Phase 2): Expose "active note titles" as MCP resource → passive injection at session start, no tool call needed
2. **Tool description** (Phase 1): `list_notes` description says "call at task start, when project mentioned"
3. **Rules file** (Phase 2): Auto-generate CLAUDE.md/.cursorrules snippet: "At session start, check Backtick for prior context"

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
  → AI: "오늘 가격 모델이랑 배포 방식 정리했는데, 저장할까요?"
  → User: "응"
  → save_document / update_document

Next day, different AI client, new thread:
  → list_documents(project: "backtick")
  → recall_document(project: "backtick", topic: "distribution")
  → Continues where yesterday left off (human-verified version)
```

#### Client-specific behavioral design — how each AI learns to use Backtick

같은 MCP 도구를 제공해도 클라이언트마다 AI의 행동을 유도하는 메커니즘이 다르다. 이를 3개 레이어로 정리하고, 각 클라이언트가 어떤 레이어를 사용할 수 있는지 매핑한다.

**Three behavioral layers:**

| Layer | 메커니즘 | 누가 작성 | 언제 적용 |
|-------|---------|----------|----------|
| L1: Tool description | MCP tool의 `description` 필드 | Backtick 개발자 | AI가 tool 목록을 받을 때 (매 세션) |
| L2: System prompt / Project instructions | 클라이언트의 system prompt 또는 project instruction | 사용자 (Backtick이 생성해주는 문구를 붙여넣기) | AI 세션 시작 시 |
| L3: Rules file | CLAUDE.md, .cursorrules 등 프로젝트 레벨 파일 | Backtick이 자동 생성 (사용자 승인 후) | AI가 프로젝트 폴더를 열 때 |

**Client × Layer 지원 매트릭스:**

| Client | L1: Tool description | L2: System prompt | L3: Rules file | 비고 |
|--------|---------------------|-------------------|----------------|------|
| **ChatGPT** (Mac App, HTTP) | ✅ MCP tool descriptions | ✅ **ChatGPT Projects custom instructions** — 프로젝트별 system prompt 설정 가능 | ❌ 파일 시스템 접근 없음 | L2가 핵심 레이어. Projects 기능에서 "Custom instructions"에 Backtick 문구를 붙여넣는 방식 |
| **Claude Desktop** (stdio) | ✅ MCP tool descriptions | ⚠️ Claude Projects system prompt는 웹 전용. Desktop에서는 tool description만 | ❌ | L1이 유일한 레이어. Tool description 품질이 가장 중요 |
| **Claude Code** (stdio) | ✅ MCP tool descriptions | ❌ | ✅ **CLAUDE.md** — 프로젝트 루트의 파일을 매 세션 로드 | L3가 핵심 레이어. CLAUDE.md에 Backtick 사용 지침 자동 삽입 |
| **Codex CLI** (stdio) | ✅ MCP tool descriptions | ❌ | ✅ **AGENTS.md** — Codex가 읽는 에이전트 지침 파일 | L3 (AGENTS.md) |

**핵심 인사이트**: ChatGPT는 L2(Project instructions)가, Claude Desktop은 L1(tool description)이, Claude Code/Codex는 L3(rules file)가 각각 가장 결정적인 레이어다. 세 레이어 모두에 Backtick 행동 지침을 넣으면 어떤 클라이언트에서든 최소 하나는 작동한다.

**L2: ChatGPT Projects custom instructions — 제공할 문구:**

```
You have access to Backtick, a cross-platform project memory tool.

When I mention a project or topic:
→ Call list_notes to check for existing context before responding.

When our conversation produces important decisions, action items, or context
that I'd want in a future session:
→ Ask me "이거 Backtick에 저장할까요?" before saving.
→ Use save_document with the right project and topic.

When saving:
→ Call list_documents first to check existing topics.
→ Fit into an existing topic if possible. Only create a new topic if clearly distinct.
→ Content must be markdown with ## headers. Never save a single line.

At the end of a long session:
→ Offer to save a summary of key decisions and open questions.
```

사용자가 ChatGPT Projects의 "Custom instructions"에 이 문구를 붙여넣는다. Backtick Settings에서 "Copy ChatGPT Instructions" 버튼으로 클립보드에 복사.

**L1: Tool description — Claude Desktop이 의존하는 유일한 레이어:**

Claude Desktop은 system prompt 커스터마이징이 불가능하므로, tool description 자체가 system prompt 역할을 한다. 따라서 Warm tool descriptions에는 반드시 다음이 포함되어야 한다:

1. **Purpose** (무엇을 하는 도구인지)
2. **Guidelines** (언제 호출해야 하는지 — 이게 핵심)
3. **Constraint** (저장 전 사용자 확인, 기존 토픽 우선)

Hot tool도 동일하게 적용 (1c 참고).

**L3: CLAUDE.md / AGENTS.md — Claude Code/Codex용 자동 생성:**

```markdown
## Backtick Integration

This project uses Backtick for cross-session memory. MCP tools are available.

- At session start: call `list_notes` to load prior Stack context
- When user mentions a feature/decision: call `list_documents` then `recall_document`
- When producing decisions or action items: offer to save via `create_note` (short-term)
  or `save_document` (long-term). Always ask the user first.
- When saving to Memory: check existing topics first. Fit into existing topic if possible.
```

Backtick Settings에서 "Add to CLAUDE.md" 버튼 → 프로젝트 루트의 CLAUDE.md에 위 블록을 자동 추가 (사용자 승인 후).

#### Project/topic classification — AI가 어떻게 분류하는지

"AI가 알아서 분류한다"는 희망 사항이 아니라 구체적 설계가 필요하다. 분류 로직은 tool description + save_document의 입력 스키마로 구현한다.

**분류의 두 가지 시점:**

| 시점 | 무엇을 | 어떻게 |
|------|--------|--------|
| **Session start** | 현재 대화가 어떤 프로젝트에 관한 것인지 판별 | AI가 `list_documents()` 호출 → 프로젝트 목록 반환 → 대화 맥락과 매칭 |
| **Save time** | 저장할 내용이 어떤 토픽에 속하는지 판별 | AI가 `list_documents(project: "X")` 호출 → 토픽 목록 + 각 토픽의 1줄 요약 반환 → 기존 토픽에 맞추거나 새 토픽 제안 |

**프로젝트 식별 규칙 (tool description에 포함):**

```
Project identification:
1. If user explicitly names a project → use that name (exact match against list_documents)
2. If conversation context implies a project (e.g., discussing pricing for an app
   the user is building) → call list_documents to find matching project
3. If no match found → ask user: "이거 어떤 프로젝트에 저장할까요? [기존 목록] / 새 프로젝트"
4. Never guess a project name. Always confirm with user if ambiguous.
```

**토픽 분류 규칙 (tool description에 포함):**

```
Topic classification:
1. Call list_documents(project) to get existing topics with summaries
2. If content fits an existing topic (>70% relevance) → update that topic
   Example: "로고 색상 바꾸자" → existing "branding" topic
3. If content spans multiple topics → save to the primary topic,
   cross-reference others in the content body
   Example: "가격을 바꾸면 랜딩 페이지도 수정해야" → save to "pricing",
   mention "see also: website" in body
4. If content doesn't fit any existing topic → propose new topic name to user
   "이 내용은 기존 토픽에 안 맞는 것 같은데, 'distribution'이라는 새 토픽 만들까요?"
5. Topic names: kebab-case, 1-2 words, noun-based (branding, pricing, launch, architecture)
6. Maximum 10 topics per project. If approaching limit, suggest consolidation.
```

**분류 실패 방지 — fallback chain:**

```
AI tries to classify
    │
    ├→ Exact match on project + topic → save directly
    │
    ├→ Project match, no topic match → propose new topic (ask user)
    │
    ├→ No project match → ask user which project
    │
    └→ User says "그냥 저장해" (no classification) → save to Stack as Hot note
       (user can later promote to Warm manually via Memory panel)
```

마지막 fallback이 중요하다: 분류를 모르겠으면 그냥 Stack에 넣는다. Stack은 분류가 필요 없다 (flat list). 나중에 사용자가 Memory panel에서 수동으로 프로젝트/토픽을 지정해서 Warm으로 옮길 수 있다.

**분류 정확도를 높이는 설계 결정:**

| 결정 | 근거 |
|------|------|
| `list_documents` 응답에 토픽별 1줄 요약 포함 | AI가 토픽 이름만 보면 "architecture"가 앱 아키텍처인지 MCP 아키텍처인지 모름. 요약이 있어야 정확한 매칭 가능 |
| 사용자에게 항상 확인 | "branding에 저장할게요"가 아니라 "이거 branding 토픽에 추가할까요?" → 사용자가 "아니, website에 넣어" 할 수 있음 |
| 새 토픽은 AI가 제안, 사용자가 승인 | AI가 마음대로 만들면 topic explosion. 사용자 승인 게이트 필수 |
| 분류 불가 시 Stack으로 fallback | 분류 때문에 저장을 포기하는 것보다, 일단 Stack에 넣고 나중에 정리하는 게 낫다 |

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
| 1a | ChatGPT Mac App HTTP connection | L | **✅ DONE** (2026-03-18) | ChatGPT as MCP client via localhost HTTP |
| 1b | Pin feature — permanent prompt cards | M | **✅ DONE** (commit `28ee95f`, 2026-03-17) | Pinned cards never expire, horizontal carousel UI |
| 1c | Hot tool description optimization | S | Not started | AI proactively retrieves/saves Stack notes |
| 1d | `list_notes` summary field | S | Not started | Two-tier retrieval — save context window tokens |

Claude Desktop connector: one-click config write to `claude_desktop_config.json`, no CLI required. Includes `usesDirectConfig` guard, error logging, and full test coverage.

#### 1c detail: Hot tool description optimization

**What**: Update `list_notes` and `create_note` descriptions in `BacktickMCPServerSession.swift` to include Guidelines (when to call) alongside Purpose (what it does). See "Hot (Stack) tool description improvements" section above for exact text.

**Why**: Tool description is the highest-leverage, zero-cost change. Research shows Guidelines component alone improves task success +5.85pp (arXiv:2602.14878). Tenable research proves description text directly controls LLM behavior.

**File**: `Sources/BacktickMCPServer/BacktickMCPServerSession.swift` — `list_notes` (line ~198), `create_note` (line ~228)

**Verification**: Manual test — connect Claude Desktop, start new conversation, mention a project name → AI should call `list_notes` without being asked. Ask AI to summarize a decision → AI should offer to `create_note`.

**⚠️ Opus 4.6 guard**: `create_note` must include "Ask the user before saving" to prevent over-triggering.

#### 1d detail: `list_notes` summary field

**What**: Add a `summary` field (1-line, ≤100 chars) to `list_notes` response. Currently returns full text, which wastes context window when there are many notes.

**Why**: Two-tier retrieval pattern (validated by Mem0, Felix/OpenClaw). AI reads summaries → picks relevant notes → calls `get_note` for full text.

**Files**: `BacktickMCPServerSession.swift` (response formatting), possibly `CaptureCard.swift` (if summary is a stored field vs. computed truncation).

**Decision needed**: Stored summary (AI generates at creation) vs. computed truncation (first N chars). Computed is simpler for Phase 1; stored is better long-term.

**Post-launch Phase 1 (Warm memory via stdio):**

| # | Task | Effort | Status | What it unlocks |
|---|------|--------|--------|-----------------|
| 2 | `Project` + `ProjectDocument` models + DB migration + services | M | Not started | Warm storage layer |
| 2b | `supersededBy` pointer in data model | S | Not started | Immutable history — never overwrite, always append |
| 3 | MCP Warm tools (save/update/recall/list/delete/search/manage) | M | Not started | AI can save/recall project context |
| 3b | MCP resource: active note/doc title list | S | Not started | Passive context injection at session start |
| 3c | CLAUDE.md / .cursorrules auto-generation | S | Not started | Rules file layer for proactive retrieval |
| 4 | Memory panel (NSPanel, project list → topic list → doc viewer/editor) | M | Not started | Human can review/edit AI-saved documents |
| 4b | MCP connection health monitor + menu bar status | M | Not started | Detect/alert on connection drops |
| 4c | Hot → Warm auto-promotion with review loop | M | Not started | TTL-expiring notes get structured into Memory |

→ Claude Desktop, Claude Code, Codex can save/recall project documents. Human reviews in Memory panel.

#### 2b detail: Immutable history (`supersededBy`)

**What**: When AI updates a Warm document, create a new record and point old record's `supersededBy` field to the new one. Never overwrite in place.

**Why**: Mem0's memory corruption bug (github.com/mem0ai/mem0/issues/3322) is caused by in-place overwrites. Felix's `supersededBy` pattern prevents this. Enables "time travel" — see what a document looked like last week.

#### 3b detail: MCP resource for passive context

**What**: Expose "active note/doc titles" as an MCP resource (not a tool). Clients that support resources auto-inject this into context at session start.

**Why**: Resources don't require AI to "decide" to call anything — the client injects them. This is Layer 1 of the three-layer retrieval design. Currently most clients have limited resource support, so this supplements (not replaces) tool description guidance.

**Fallback**: For clients that don't support MCP resources, the tool description layer (Layer 2) and rules file layer (Layer 3) cover retrieval.

#### 3c detail: CLAUDE.md / .cursorrules auto-generation

**What**: When user connects a client, offer to add a snippet to their project's rules file:
```
When the user mentions a project, feature, or topic, check Backtick
(list_notes / list_documents) for related context before responding.
At session start, list active Backtick notes to load prior context.
When producing important decisions or action items, offer to save
them to Backtick (create_note / save_document) for cross-session persistence.
```

**Why**: This is the MCP Memory Server's companion prompt pattern (Anthropic's official approach). Rules files are the most deterministic way to control AI behavior — even if tool descriptions are ignored, rules files are loaded every session.

#### 4c detail: Hot → Warm auto-promotion

**What**: When a Stack note approaches TTL expiry (8h), offer to promote it to Warm Memory instead of deleting.

**Why**: Mem0's auto-extraction is valuable but must include human review (Cursor Memories failed without it). Flow: AI generates structured Warm document draft → user reviews in Memory panel → approved version persists.

**⚠️ Cursor Memories lesson**: Auto-accumulation without review = unpredictable behavior. Always show the user what's being promoted and let them edit/reject.

**Post-launch Phase 2 (HTTP transport — ChatGPT connection):**

| # | Task | Effort | Status | What it unlocks |
|---|------|--------|--------|-----------------|
| 5 | HTTP server in Backtick app process | L | **✅ DONE** (2026-03-18) | ChatGPT Mac App connection via localhost |
| 5b | Long-lived connection stability testing | S | Not started | Verify HTTP connection stays alive over hours/days without dropping |
| 6 | Auth (Bearer token) + Settings UI for HTTP | M | Not started | Secure HTTP connections |

→ ChatGPT Mac App connects via localhost HTTP. Hot tools already functional. Warm tools available once Phase 1 ships. Open issue: long-running connection stability needs verification (does the HTTP connection survive sleep/wake, hours of idle, ChatGPT app restarts?).

**Post-launch Phase 3 (remote access):**
Tunnel setup for Claude Web / ChatGPT Web / Mobile. Only if demand exists. Not started.
