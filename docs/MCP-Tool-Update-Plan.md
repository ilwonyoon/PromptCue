# MCP Tool Update — classify, group, prompts

## Overview

BacktickMCP 서버에 2개 신규 도구(`classify_notes`, `group_notes`)와 MCP `prompts` capability(5개 템플릿)를 추가한다. 기존 6개 도구는 변경 없음.

**핵심 제약: active 카드만 처리한다.** copied 카드는 이미 실행된 것이므로 classify/group 대상에서 제외.

**목표 플로우:**

```
노트 쌓임 → classify_notes(scope: "active", 1차 메타데이터 분류)
         → LLM이 triage 템플릿으로 의미 기반 2차 분류 + 난이도 태깅
         → 사용자 confirm (분류 결과)
         → 난이도별 단계적 실행 (아래 참고)
```

### 실행 전략: 난이도별 단계적 처리

한큐에 모든 그룹을 처리하지 않는다. 난이도별로 사용자 확인 구간을 둔다.

```
[trivial/easy 그룹들]
  → group_notes → structured prompt → 실행
  → ⚠️ 사용자 결과 확인
  → confirm 후 다음 단계

[medium 그룹들]
  → group_notes → structured prompt → 실행
  → ⚠️ 사용자 결과 확인
  → confirm 후 다음 단계

[hard/complex 그룹들]
  → group_notes → structured prompt (plan/diagnose 우선)
  → ⚠️ 사용자가 계획/진단 결과 검토
  → confirm 후 실행
  → ⚠️ 사용자 결과 확인
```

**원칙:**
- 쉬운 것부터 처리해서 빠른 진척 확보
- 난이도가 올라갈수록 사용자 확인 빈도 증가
- hard/complex는 실행 전에 plan 또는 diagnose를 먼저 거침
- 각 단계 결과를 사용자가 확인한 후에야 다음 단계 진행
- LLM이 자율적으로 전체를 끝내려 하지 않음

---

## Phase 1: `classify_notes` (읽기 전용)

### 1.1 StackReadService에 classifyNotes 추가

**파일**: `PromptCue/Services/StackReadService.swift`

```swift
struct NoteClassification: Equatable {
    let groupKey: String
    let repositoryName: String?
    let branch: String?
    let appName: String?
    let sessionIdentifier: String?
    let noteIDs: [UUID]
    let previewTexts: [String]  // 각 노트 text 앞 80자
}

func classifyNotes(scope: StackReadScope, groupBy: String) throws -> [NoteClassification]
```

**그룹핑 키 로직:**

| groupBy | 키 조합 | 용도 |
|---------|---------|------|
| `repository` | `repositoryName` + `branch` | 리포/브랜치별 분류 (기본값) |
| `session` | `sessionIdentifier` | 세션별 분류 |
| `app` | `bundleIdentifier` + `appName` | 앱별 분류 |

- `suggestedTarget` 없는 노트 → `"uncategorized"` 그룹
- 그룹 내 순서: `sortOrder` descending

### 1.2 Tool 정의 + Dispatch

**파일**: `Sources/BacktickMCPServer/BacktickMCPServerSession.swift`

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "scope": {
      "type": "string",
      "enum": ["all", "active", "copied"],
      "description": "기본값: active. copied는 이미 실행된 노트이므로 일반적으로 active만 사용."
    },
    "groupBy": {
      "type": "string",
      "enum": ["repository", "session", "app"]
    }
  },
  "additionalProperties": false
}
```

**scope 기본값은 `"active"`** — copied 노트는 이미 실행 완료된 것이므로 분류 대상에서 제외하는 것이 기본 동작.

**Output:**
```json
{
  "groupBy": "repository",
  "scope": "active",
  "groupCount": 3,
  "totalNotes": 12,
  "groups": [
    {
      "groupKey": "PromptCue|mcp-tool-update",
      "repositoryName": "PromptCue",
      "branch": "mcp-tool-update",
      "appName": "Cursor",
      "noteCount": 5,
      "noteIDs": ["uuid1", "uuid2"],
      "previewTexts": ["MCP에 classify 도구 추가...", "group tool 스펙 정리..."]
    }
  ]
}
```

**Edge cases:**
- 빈 스택 → `groups: []`
- 모든 노트에 suggestedTarget 없음 → 단일 `"uncategorized"` 그룹
- 같은 리포 다른 브랜치 → 별도 그룹
- 같은 리포+브랜치 다른 세션 → `repository` groupBy에서는 같은 그룹, `session`에서는 분리

---

## Phase 2: `group_notes` (쓰기)

### 2.1 StackGroupService 신규 생성

**파일**: `PromptCue/Services/StackGroupService.swift` (NEW)

```swift
struct StackGroupRequest: Equatable, Sendable {
    let sourceNoteIDs: [UUID]
    let title: String
    let separator: String      // 기본값: "---"
    let archiveSources: Bool   // 기본값: true
    let sessionID: String?
}

struct StackGroupResult: Equatable {
    let groupedNote: CaptureCard
    let archivedNotes: [CaptureCard]
    let copyEvents: [CopyEvent]
}

@MainActor
final class StackGroupService {
    private let readService: StackReadService
    private let writeService: StackWriteService
    private let executionService: StackExecutionService

    func groupNotes(_ request: StackGroupRequest) throws -> StackGroupResult
}
```

**생성되는 카드 텍스트 포맷:**
```
# {title}

---

{note1.text}

---

{note2.text}

---

{note3.text}
```

**동작 순서:**
1. `readService`로 sourceNoteIDs 전체 로드 — 못 찾으면 에러
2. 순서 유지 (입력 배열 순), 중복 ID 제거
3. 첫 번째 suggestedTarget 있는 노트에서 target 상속
4. `writeService.createNote()`로 합쳐진 카드 생성
5. `archiveSources == true`면 `executionService.markExecuted()`로 원본 copied 처리
6. 결과 반환

**Edge cases:**
- 단일 noteID → 유효, 타이틀 래퍼 카드 생성
- 빈 text 노트 → separator 사이에 빈 블록
- 이미 copied인 원본 → 경고 반환 (이미 실행된 노트를 다시 그룹핑하려는 것이므로), 단 처리는 허용
- 빈 title → 에러
- 존재하지 않는 ID → 에러
- copied 노트만 포함된 요청 → 경고 포함하여 진행 (사용자가 의도적으로 할 수 있음)

### 2.2 Package.swift 업데이트

BacktickMCPServer target의 `sources:` 배열에 추가:
```
"PromptCue/Services/StackGroupService.swift"
```

### 2.3 Tool 정의 + Dispatch

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "noteIDs": {
      "type": "array",
      "items": { "type": "string", "format": "uuid" },
      "minItems": 1
    },
    "title": { "type": "string" },
    "separator": { "type": "string" },
    "archiveSources": { "type": "boolean" },
    "sessionID": { "type": ["string", "null"] }
  },
  "required": ["noteIDs", "title"],
  "additionalProperties": false
}
```

**Output:**
```json
{
  "groupedNote": { /* 표준 note dictionary */ },
  "archivedCount": 3,
  "archivedNotes": [ /* 표준 note dictionaries */ ],
  "copyEvents": [ /* 표준 copy event dictionaries */ ]
}
```

---

## Phase 3: MCP Prompts Capability

### 3.0 BacktickMCPToolError 추출

`BacktickMCPServerSession.swift` 하단의 `private struct BacktickMCPToolError`를 별도 파일로 추출:

**파일**: `Sources/BacktickMCPServer/BacktickMCPToolError.swift` (NEW)

접근 레벨 `internal`로 변경. 새 파일(MCPPromptRenderer 등)에서 접근 가능하게.

### 3.1 MCPPromptTemplates

**파일**: `Sources/BacktickMCPServer/MCPPromptTemplates.swift` (NEW)

```swift
struct MCPPromptTemplate: Equatable, Sendable {
    let name: String
    let description: String
    let arguments: [MCPPromptArgument]
    let bodyTemplate: String
}

struct MCPPromptArgument: Equatable, Sendable {
    let name: String
    let description: String
    let required: Bool
}

enum MCPPromptCatalog {
    static let all: [MCPPromptTemplate] = [triage, diagnose, execute, plan, review]
    static func template(named: String) -> MCPPromptTemplate?
}
```

### 템플릿 5종

**triage** — 분류 + 그룹핑 제안 + 난이도 태깅
```
You are a senior engineering triage analyst.

## Notes to classify

{noteText}

## Context
Repository: {repositoryName}
Branch: {branch}

## Instructions

1. Classify each note by function/intent (bug fix, feature, refactor, config, docs, test).
2. Group related notes that should be addressed together.
   - Same intent but different modules = separate groups.
   - User should understand the group just from the title.
3. For each group provide:
   - Title (clear, specific to module + problem)
   - Difficulty: trivial | easy | medium | hard | complex
   - Scope: single-file | multi-file | cross-module
4. Suggest execution order (easy first, dependencies respected).
5. Flag ambiguous notes needing clarification.

Return structured JSON: groups array with title, difficulty, scope, noteIDs, executionOrder, rationale.
```

**diagnose** — 진단 전용, 실행 금지
```
You are a senior debugger performing root cause analysis.

## Problem Description

{noteText}

## Context
Repository: {repositoryName}
Branch: {branch}

## Goal
Identify the root cause. Do NOT execute fixes.

## Constraints
- Present hypotheses ranked by likelihood
- For each hypothesis: verification method (log, test, repro steps)
- Distinguish symptoms from causes
- Note missing information needed to confirm
```

**execute** — 구현 실행
```
You are an implementer working in an existing codebase.

## Task

{noteText}

## Context
Repository: {repositoryName}
Branch: {branch}

## Goal
Implement the changes step by step.

## Constraints
- Follow existing code patterns and conventions
- Make minimal, focused changes
- Verify each step compiles before proceeding
- Update tests for affected code
- Do not refactor unrelated code
```

**plan** — 설계/아키텍처
```
You are a software architect analyzing a design problem.

## Problem

{noteText}

## Context
Repository: {repositoryName}
Branch: {branch}

## Goal
Analyze the design space and recommend an approach.

## Deliverables
- 2-3 viable approaches with trade-offs
- Risks and dependencies for each
- Recommended approach with justification
- Implementation phases
- Architectural concerns or breaking changes
```

**review** — 코드 리뷰
```
You are a code reviewer examining changes.

## Changes to Review

{noteText}

## Context
Repository: {repositoryName}
Branch: {branch}

## Goal
Review for correctness, maintainability, and safety.

## Classification
- CRITICAL: Must fix (bugs, security, data loss)
- HIGH: Should fix (performance, error handling)
- MEDIUM: Recommended (style, naming)
- LOW: Optional (nits)
```

### 3.2 MCPPromptRenderer

**파일**: `Sources/BacktickMCPServer/MCPPromptRenderer.swift` (NEW)

```swift
enum MCPPromptRenderer {
    static func render(
        template: MCPPromptTemplate,
        arguments: [String: String]
    ) throws -> String
}
```

**치환 규칙:**
- `{variableName}` → 해당 argument 값
- optional 미제공 → `"(not specified)"`
- required 미제공 → throw error
- **단일 패스** — argument 값 안의 `{...}`는 재귀 치환하지 않음

### 3.3 프로토콜 통합

**initializeResult capabilities 확장:**
```swift
"capabilities": [
    "tools": ["listChanged": false],
    "prompts": ["listChanged": false],
]
```

**handleObject에 method 추가:**
```swift
case "prompts/list":
    return successResponse(id: id, result: promptsList())

case "prompts/get":
    // name + arguments 파싱 → MCPPromptRenderer.render → messages 배열 반환
```

**prompts/get 응답 형태 (MCP spec):**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "description": "...",
    "messages": [
      {
        "role": "user",
        "content": { "type": "text", "text": "rendered template" }
      }
    ]
  }
}
```

---

## Phase 4: 테스트

### 파일 변경

| 파일 | 변경 |
|------|------|
| `Tests/BacktickMCPServerTests/BacktickMCPServerTests.swift` | 기존 surface 테스트 업데이트 (8 tools), 신규 통합 테스트 추가 |
| `Tests/BacktickMCPServerTests/MCPPromptRendererTests.swift` | NEW — renderer 단위 테스트 |

### 테스트 케이스

**classify_notes:**
- `testClassifyNotesGroupsByRepository` — 같은 리포 2개 + 다른 리포 1개 → 2그룹
- `testClassifyNotesWithNoSuggestedTarget` — 전부 uncategorized
- `testClassifyNotesEmptyStack` — 빈 배열
- `testClassifyNotesGroupBySession` — 세션 기반
- `testClassifyNotesGroupByApp` — 앱 기반

**group_notes:**
- `testGroupNotesCreatesMergedCardAndArchivesSources` — 핵심 플로우
- `testGroupNotesWithArchiveSourcesFalse` — 원본 유지
- `testGroupNotesSingleNote` — 단일 노트 래핑
- `testGroupNotesInvalidIDReturnsError` — 없는 ID
- `testGroupNotesEmptyTitleReturnsError` — 빈 타이틀

**prompts:**
- `testPromptsListReturnsAllTemplates` — 5개 이름 확인
- `testPromptsGetTriageRendersTemplate` — 변수 치환 확인
- `testPromptsGetUnknownNameReturnsError`
- `testPromptsGetMissingRequiredArgReturnsError`

**renderer:**
- `testRenderSubstitutesAllVariables`
- `testRenderUsesDefaultForOptionalMissing`
- `testRenderThrowsForRequiredMissing`
- `testRenderDoesNotRecursivelySubstitute`

---

## 구현 순서 (커밋 단위)

| # | 작업 | 파일 |
|---|------|------|
| 1 | BacktickMCPToolError 추출 | `BacktickMCPToolError.swift` (NEW), `BacktickMCPServerSession.swift` |
| 2 | classifyNotes 서비스 메서드 | `StackReadService.swift` |
| 3 | classify_notes 도구 정의 + dispatch | `BacktickMCPServerSession.swift` |
| 4 | StackGroupService 생성 | `StackGroupService.swift` (NEW) |
| 5 | Package.swift sources 추가 | `Package.swift` |
| 6 | group_notes 도구 정의 + dispatch | `BacktickMCPServerSession.swift` |
| 7 | MCPPromptTemplates | `MCPPromptTemplates.swift` (NEW) |
| 8 | MCPPromptRenderer | `MCPPromptRenderer.swift` (NEW) |
| 9 | prompts capability + protocol dispatch | `BacktickMCPServerSession.swift` |
| 10 | 전체 테스트 | `BacktickMCPServerTests.swift`, `MCPPromptRendererTests.swift` (NEW) |

## 신규 파일 목록

```
Sources/BacktickMCPServer/BacktickMCPToolError.swift      (NEW)
Sources/BacktickMCPServer/MCPPromptTemplates.swift         (NEW)
Sources/BacktickMCPServer/MCPPromptRenderer.swift          (NEW)
PromptCue/Services/StackGroupService.swift                 (NEW)
Tests/BacktickMCPServerTests/MCPPromptRendererTests.swift  (NEW)
```

## 리스크

| 리스크 | 심각도 | 완화 |
|--------|--------|------|
| group_notes 부분 실패 (카드 생성 후 archive 실패) | 중간 | merged 카드 ID 반환됨, 호출자가 mark_notes_executed 재시도 가능 |
| BacktickMCPServerSession.swift 비대화 (~900줄) | 중간 | 도구 핸들러를 extension으로 분리 검토 |
| MCP prompts 프로토콜 불일치 | 중간 | 클라이언트(Claude Desktop, Cursor) 테스트 |
| classify_notes 그룹핑 키 충돌 | 낮음 | 복합 키(repo+branch) 사용 |

## 호환성

- **기존 6개 도구**: 스키마, 동작, 응답 형태 변경 없음
- **tools/list 순서**: 기존 순서 유지, 신규 도구는 끝에 추가
- **프로토콜 버전**: 변경 없음. `2025-03-26`, `2024-11-05` 모두 동작
- **DB 스키마**: 변경 없음. group_notes는 기존 CardStore.upsert 사용
- **CopyEvent**: group_notes의 archive는 기존 `CopyEventVia.agentRun` + `CopyEventActor.mcp` 재사용

## 성공 기준

- [ ] `swift test` 통과 (BacktickMCPServerTests + MCPPromptRendererTests)
- [ ] `xcodegen generate` 성공
- [ ] `xcodebuild build` 성공 (`CODE_SIGNING_ALLOWED=NO`)
- [ ] tools/list → 8개 도구
- [ ] classify_notes → 그룹 반환, 원본 변경 없음
- [ ] group_notes → 합쳐진 카드 + 원본 archived
- [ ] group_notes(archiveSources: false) → 원본 유지
- [ ] prompts/list → 5개 템플릿
- [ ] prompts/get → 변수 치환된 렌더링
- [ ] 기존 테스트 전부 통과
