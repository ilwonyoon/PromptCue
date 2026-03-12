# MCP Tool Update — classify, group, prompts

## Overview

BacktickMCP 서버에 2개 신규 도구 + MCP prompts capability를 추가한다. 기존 6개 도구 변경 없음.

**추가하는 이유**: 기존 CRUD 도구(list/get/create/update/delete/mark_executed)는 개별 노트 조작은 커버하지만, "쌓인 노트를 효율적으로 처리"하는 데 3가지가 빠져있음:

1. **한눈에 파악** — 노트가 어떤 프로젝트/세션 기준으로 몇 개씩 있는지 (→ `classify_notes`)
2. **관련 노트 합치기** — 분절된 노트를 하나의 맥락으로 (→ `group_notes`)
3. **의도에 맞는 처리** — 같은 노트라도 "진단해" vs "실행해"로 결과가 다름 (→ `prompts`)

**플로우:**

```
노트 쌓임 → classify_notes (리포/세션별 1차 분류)
         → 에이전트가 triage 템플릿으로 그룹핑 제안
         → 사용자 확인
         → group_notes (합치기, 원본은 active 유지)
         → 의도별 템플릿 (diagnose/execute)으로 처리
         → 완료 시 mark_notes_executed로 copied 처리
```

**핵심 원칙:**
- active 카드만 처리 (copied는 이미 실행됨)
- group_notes는 합치기만, archive는 별도 (archiveSources 기본값 = false)
- MCP 서버는 데이터 파이프 — 판단은 에이전트 몫

---

## Phase 1: `classify_notes` (읽기 전용)

메타데이터 기반 1차 분류. 에이전트의 탐색 비용을 줄여주는 도구.

**서비스**: `StackReadService.classifyNotes(scope:groupBy:)`

| groupBy | 키 조합 | 용도 |
|---------|---------|------|
| `repository` (기본값) | `repositoryName` + `branch` | 리포/브랜치별 |
| `session` | `sessionIdentifier` | 세션별 |
| `app` | `bundleIdentifier` + `appName` | 앱별 |

**Input:**
```json
{
  "scope": "active",
  "groupBy": "repository"
}
```

**Output:**
```json
{
  "groupBy": "repository",
  "scope": "active",
  "groupCount": 2,
  "totalNotes": 8,
  "groups": [
    {
      "groupKey": "PromptCue|mcp-tool-update",
      "repositoryName": "PromptCue",
      "branch": "mcp-tool-update",
      "noteCount": 5,
      "noteIDs": ["uuid1", "uuid2", ...],
      "previewTexts": ["MCP 파싱 에러...", "classify tool 추가..."]
    }
  ]
}
```

**Edge cases:** 빈 스택 → `[]`, suggestedTarget 없음 → `"uncategorized"` 그룹.

---

## Phase 2: `group_notes` (쓰기)

관련 노트를 하나의 카드로 합침. Stack UI에 정리된 카드를 남기기 위한 도구.

**서비스**: `StackGroupService.groupNotes(_:)`

**Input:**
```json
{
  "noteIDs": ["uuid1", "uuid2", "uuid3"],
  "title": "MCP 파싱 에러 수정",
  "separator": "---",
  "archiveSources": false
}
```

**archiveSources 기본값 = false.** 합치기 ≠ 실행 완료. 실행 완료 시 별도로 `mark_notes_executed` 호출.

**합쳐진 카드 텍스트 포맷:**
```
# MCP 파싱 에러 수정

--- [note:abc123 | 2026-03-12]

JSON-RPC 파싱에서 타입 불일치

--- [note:def456 | 2026-03-12]

tool call argument 검증 빠져있음
```

각 source note의 ID + 날짜를 separator에 포함해서 traceability 확보.

**Output:**
```json
{
  "groupedNote": { /* 표준 note dictionary */ },
  "archivedCount": 0,
  "archivedNotes": [],
  "copyEvents": []
}
```

**Edge cases:** 단일 noteID → 유효, 빈 title → 에러, 없는 ID → 에러.

---

## Phase 3: MCP Prompts Capability (3개 템플릿)

`prompts/list` + `prompts/get` 프로토콜 지원. 에이전트의 의도별 처리 품질을 높이는 도구.

### 템플릿 3종

**triage** — 노트 분류 + 그룹핑 제안
```
You are an engineering triage assistant.

## Notes

{noteText}

## Context
Repository: {repositoryName}
Branch: {branch}

## Instructions

1. Group related notes that should be addressed together.
   - Same intent but different modules = separate groups.
   - User should understand the group just from the title.
2. For each group: title, intent tag (diagnose/execute/investigate), difficulty (easy/medium/hard).
3. If a note is ambiguous or exploratory, tag it as investigate — do not promote to execute.
4. Suggest processing order: easy first, respect dependencies.

Return JSON: { groups: [{ title, intent, difficulty, noteIDs, rationale }] }
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
- Hypotheses ranked by likelihood
- Each hypothesis: verification method (log, test, repro steps)
- Distinguish symptoms from causes
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
- Follow existing code patterns
- Minimal, focused changes
- Verify each step compiles
- Do not refactor unrelated code
```

### 프로토콜

- `prompts/list` → 3개 템플릿 메타데이터 반환
- `prompts/get` → name + arguments → 렌더링된 텍스트 반환 (MCP messages 형태)
- 변수: `{noteText}` (필수), `{repositoryName}` (선택), `{branch}` (선택)
- 단일 패스 치환 (재귀 없음)

---

## Phase 4: 테스트

### 통합 테스트 (BacktickMCPServerTests.swift)

- 기존 surface 테스트: 8 tools, prompts capability 확인
- `testClassifyNotesGroupsByRepository` — 같은 리포 2개 + 다른 리포 1개 → 2그룹
- `testClassifyNotesEmptyStack` — 빈 배열
- `testGroupNotesCreatesMergedCard` — 합치기 + 원본 active 유지 확인
- `testGroupNotesMergedTextContainsSourceIDs` — note ID가 merge 포맷에 포함
- `testGroupNotesInvalidIDReturnsError`
- `testPromptsListReturnsThreeTemplates`
- `testPromptsGetDiagnoseRendersTemplate`

### Renderer 테스트 (MCPPromptRendererTests.swift) — 이미 완료

- 변수 치환, optional 기본값, required 에러, 재귀 방지 4종

---

## 코드 변경 (현재 상태 → 필요 변경)

이미 구현된 것:
- [x] `classify_notes` 서비스 + 도구 정의
- [x] `group_notes` 서비스 + 도구 정의 (archiveSources 기본값 false)
- [x] BacktickMCPToolError 추출
- [x] MCPPromptRenderer + 테스트
- [x] prompts/list, prompts/get 프로토콜 dispatch
- [x] Package.swift 업데이트

**아직 필요한 변경:**

| 작업 | 파일 |
|------|------|
| triage 템플릿 축소 (topology/confidence/priority 제거) | `MCPPromptTemplates.swift` |
| plan/review 템플릿 제거 (3종만 유지) | `MCPPromptTemplates.swift` |
| merge 포맷에 note ID + 날짜 포함 | `StackGroupService.swift` |
| 통합 테스트 작성 | `BacktickMCPServerTests.swift` |
| 계획문서 동기화 | `MCP-Tool-Update-Plan.md` (이 파일) |

---

## 성공 기준

- [ ] `swift test` 통과
- [ ] `xcodegen generate` 성공
- [ ] `xcodebuild build` 성공 (`CODE_SIGNING_ALLOWED=NO`)
- [ ] tools/list → 8개 도구
- [ ] classify_notes → 그룹 반환, 원본 변경 없음
- [ ] group_notes → 합쳐진 카드 (note ID 포함), 원본 active 유지
- [ ] prompts/list → 3개 템플릿
- [ ] prompts/get → 변수 치환된 렌더링
- [ ] 기존 테스트 전부 통과
