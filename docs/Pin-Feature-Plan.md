# Pin Feature Plan

## Why Pin Exists

### Vibe Coder Behavioral Research (요약)

4,753개 Reddit 포스트 분석(PainIndex March 2026) + 커뮤니티 관찰 결과:

**핵심 루프:** 의도 떠오름 → AI에 프롬프트 → 결과 복사 → 다른 도구에 붙여넣기 → 반복

**가장 큰 고통 3가지:**

1. **세션 간 컨텍스트 소실** — 새 채팅 = 백지. 매번 프로젝트 다시 설명
2. **도구 간 컨텍스트 단절** — Cursor에서 한 결정을 Claude가 모름. 수동으로 `.cursorrules` 업데이트
3. **클립보드가 유일한 다리** — 메타데이터 없고, TTL로 사라지고, 프롬프트/코드/비밀번호 구분 없음

**현재 해결책:** `CLAUDE.md`, `.cursorrules` 수동 관리, 마크다운 스펙 문서, 세션 결정 로그 — 또는 아무 시스템 없이 매번 다시 설명.

### 클립보드 매니저의 구조적 한계

Raycast, Maccy, macOS Tahoe 클립보드 히스토리 공통:

| 한계 | 왜 문제인가 |
|---|---|
| 시간순 나열만 | "3일 전 프롬프트"를 못 찾음 |
| 타입 구분 없음 | URL, 비밀번호, 코드, 프롬프트가 다 섞임 |
| TTL 만료 | 프롬프트는 8시간보다 오래 살아야 함 |
| 실행 이력 없음 | 이 프롬프트를 썼는지, 잘 먹혔는지 모름 |
| 큐가 아님 | 히스토리(과거)지, 실행 대기열(미래)이 아님 |

> **구조적 갭: 클립보드는 뒤를 봄(복사한 것). 바이브 코더는 앞을 봄(할 것).**

### Stack + Pin이 푸는 것

Stack은 클립보드 매니저가 아님. **실행 대기열**임. Pin이 추가되면 세 역할:

| 역할 | 카드 타입 | 수명 |
|---|---|---|
| 자주 쓰는 프롬프트 | 핀 카드 | **영구** |
| 오늘의 작업 컨텍스트 | 일반 카드 | TTL (8시간) |
| 실행 완료 이력 | Copied 카드 | TTL |

**바이브 코더 시나리오:**

1. **"매번 다시 설명하는" 문제** → 프로젝트 컨텍스트 프롬프트를 핀 → 탭 → 복사 → 새 세션에 붙여넣기. 2초.
2. **"도구 간 컨텍스트 단절"** → Claude에서 결정 → `Cmd+`` → 캡처 → Cursor의 Claude가 MCP로 읽음.
3. **"클립보드에 다 섞이는" 문제** → 의도적으로 던진 것만 들어감. 노이즈 제로.

---

## Design

### Data Flow

```
CaptureCard (도메인 모델)
    ↓ isPinned: Bool 추가
CardRecord (GRDB 브릿지)
    ↓ isPinned 컬럼 매핑
PromptCueDatabase (마이그레이션)
    ↓ ALTER TABLE cards ADD isPinned BOOLEAN NOT NULL DEFAULT 0
CardStore (영속화)
    ↓ 변경 없음 — CardRecord이 처리
StackWriteService (비즈니스 로직)
    ↓ StackNoteUpdate에 isPinned 추가
BacktickMCPServer (외부 API)
    ↓ update_note 스키마 + noteDictionary 확장
CardStackOrdering (정렬)
    ↓ 핀 카드 최상단
CaptureCard.isExpired (TTL)
    ↓ 핀이면 만료 안 됨
CardStackView (UI)
    ↓ 핀 아이콘 + 컨텍스트 메뉴
```

### Changed Files

| Layer | File | Change |
|---|---|---|
| **Domain** | `Sources/PromptCueCore/CaptureCard.swift` | `isPinned: Bool` field, `togglePinned()` method, decoder default |
| **Domain** | `Sources/PromptCueCore/CardStackOrdering.swift` | Pinned-first sort logic |
| **DB** | `PromptCue/Services/PromptCueDatabase.swift` | `addIsPinned` migration |
| **DB** | `PromptCue/Services/CardStore.swift` | `CardRecord` gets `isPinned` field |
| **Service** | `PromptCue/Services/StackWriteService.swift` | `StackNoteUpdate` gets `isPinned` |
| **MCP** | `Sources/BacktickMCPServer/BacktickMCPServerSession.swift` | `update_note` schema + response |
| **UI** | `PromptCue/UI/Views/CardStackView.swift` | Pin icon, context menu |
| **Test** | `Tests/PromptCueCoreTests/` | Sort, TTL, toggle tests |

### Key Decisions

#### 1. TTL: Pinned cards never expire

```swift
// CaptureCard.swift
public func isExpired(relativeTo date: Date = Date(), ttl: TimeInterval = CaptureCard.ttl) -> Bool {
    if isPinned { return false }
    return createdAt.addingTimeInterval(ttl) < date
}
```

Pin의 존재 이유가 "영구 보존"이므로 TTL 면제.

#### 2. Sort: Pinned first, then existing logic

```swift
// CardStackOrdering.swift
public static func compare(_ lhs: CaptureCard, _ rhs: CaptureCard) -> Bool {
    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
    // existing lastCopiedAt → sortOrder → createdAt → id logic
    ...
}
```

핀 카드 내부 정렬은 기존 sortOrder/createdAt 유지. 수동 드래그 정렬 가능.

#### 3. MCP: isPinned in update_note + list_notes response

```jsonc
// update_note input schema
"isPinned": { "type": ["boolean", "null"], "description": "Pin or unpin this note" }

// noteDictionary output (all tools)
{ "id": "...", "text": "...", "isPinned": true, ... }
```

AI 에이전트가 자주 쓰는 프롬프트를 직접 핀/언핀 가능.

### Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| DB migration failure | Low | `NOT NULL DEFAULT false` — existing data safe |
| Codable backward compat | Low | `decodeIfPresent` + default `false` in custom decoder |
| Sort regression | Medium | Add pinned cases to `CardStackOrderingTests` |
| MCP backward compat | Low | Additive only — no existing field changes |

### Implementation Phases

```
Phase 1: Domain (no dependencies)
  ├─ CaptureCard.isPinned + togglePinned()
  ├─ CardStackOrdering pinned-first
  ├─ isExpired() pin bypass
  └─ PromptCueCore tests
  → Verify: swift test

Phase 2: Persistence (depends on Phase 1)
  ├─ PromptCueDatabase addIsPinned migration
  └─ CardRecord isPinned mapping
  → Verify: swift test + xcodebuild build

Phase 3: Services (depends on Phase 2)
  ├─ StackNoteUpdate.isPinned
  └─ StackWriteService.updateNote() handling
  → Verify: xcodebuild test

Phase 4: MCP (depends on Phase 1, parallel with Phase 3)
  └─ BacktickMCPServerSession schema + response
  → Verify: swift test --filter BacktickMCPServerTests

Phase 5: UI (depends on Phase 3)
  └─ CardStackView pin icon + context menu
  → Verify: xcodebuild build + manual QA
```

---

## Research Sources

- [PainIndex — Vibe Coder Report, March 2026](https://painindex.xyz/)
- [SitePoint: Vibe Coding Guide 2026](https://www.sitepoint.com/vibe-coding-2026-complete-guide/)
- [31 Days of Vibe Coding: Context Management](https://31daysofvibecoding.com/2026/01/07/context-management/)
- [MIT Technology Review: From Vibe Coding to Context Engineering](https://www.technologyreview.com/2025/11/05/1127477/from-vibe-coding-to-context-engineering-2025-in-software-development/)
- [Stark Insider: Two AIs, One Codebase](https://www.starkinsider.com/2025/10/claude-vs-cursor-dual-ai-coding-workflow.html)
- [Blake Crosley: Claude Code + Cursor — 30 Sessions](https://blakecrosley.com/blog/claude-code-cursor-workflow)
- [Solveo: 1,000 Reddit Comments Analysis](https://www.solveo.co/post/we-analyzed-1-000-reddit-comments-to-discover-the-most-used-vibe-coding-tools)
- [Medium: Markdown-First Vibe Coding](https://medium.com/@francisjosephyanga/from-chaos-to-clarity-my-discovery-of-markdown-first-vibe-coding-48ede545bd1b)
- [Medium: Complete Guide to AI Agent Memory Files](https://medium.com/data-science-collective/the-complete-guide-to-ai-agent-memory-files-claude-md-agents-md-and-beyond-49ea0df5c5a9)
- [DEV Community: From StackOverflow to Vibe Coding](https://dev.to/trackjs/from-stackoverflow-to-vibe-coding-the-evolution-of-copy-paste-development-4ngl)
- [Addy Osmani: Vibe Coding vs AI-Assisted Engineering](https://medium.com/@addyosmani/vibe-coding-is-not-the-same-as-ai-assisted-engineering-3f81088d5b98)
- [arxiv: Qualitative Study of Vibe Coding](https://arxiv.org/html/2509.12491v1)
