# AI Prompt Assembly — Feature Proposal

## Problem

바이브 코더는 하루 종일 메모를 캡처한다. 버그, 기능 요청, 아이디어, 다른 프로젝트 관련 노트가 섞인다. 현재 워크플로우는:

1. 노트 하나 복사
2. AI 채팅에 붙여넣기
3. 지시 타이핑
4. 다음 노트로 반복

**문제:** 관련된 노트를 묶어서 한 번에 보내고 싶지만, 수동 분류 + 매번 다른 지시 작성이 friction.

## Solution

AI(Claude Haiku)가 백그라운드에서 노트를 자동 분류하고, 구조화된 프롬프트로 조립한다. 사용자는 완성된 프롬프트를 복사만 하면 된다.

## 기각된 대안: Deterministic 포맷팅

초기에는 AI 없이 bullet/numbered/XML 등 15개 포맷을 제공하는 방안을 검토했으나, 다음 이유로 기각:

- **포맷 선택지 다양화는 엔지니어의 발상.** 바이브 코더는 Settings에서 포맷을 고르지 않음.
- **Header preset은 불필요.** "Fix the following issues:" 같은 헤더는 AI 채팅창에 직접 타이핑하는 게 더 자연스러움. 매번 상황이 달라서 고정 프리셋이 어색함.
- **Tail 다양화는 friction 증가.** 여러 tail을 수동으로 전환하는 건 오히려 워크플로우를 느리게 만듦.
- **AI가 하면 분류 + tail 생성을 한 번에 해결.** Haiku 1회 호출 비용 ~$0.006 (0.6원).

## UX Model

### Before (현재)

```
[노트1] → 복사 → AI에 붙이기 → 지시 타이핑
[노트2] → 복사 → AI에 붙이기 → 지시 타이핑
[노트3] → 복사 → AI에 붙이기 → 지시 타이핑
```

### After (제안)

```
노트 쌓임 → AI 백그라운드 분류/조립 → 완성된 프롬프트 복사 → 끝
```

### Stack UI

```
┌─────────────────────────────┐
│ 🔗 PromptCue 버그 수정 (2)    │  ← AI 생성 그룹
│ 스택 반짝임 + 카드 패딩 이슈    │
│                        [복사] │
├─────────────────────────────┤
│ 🔗 PromptCue 기능 설계 (2)    │  ← AI 생성 그룹
│ Settings 리디자인 + 멀티선택   │
│                        [복사] │
├─────────────────────────────┤
│ 🔗 Crest 아이디어 (1)         │
│ Maze 영감 → 아트/명언         │
│                        [복사] │
├─────────────────────────────┤
│ 스택 메뉴 반짝임 버그...       │  ← 원본 노트들 (하단)
│ 카드 패딩 타이트...            │
│ Settings 사이드 네비...        │
│ ...                          │
└─────────────────────────────┘
```

### Copy Behavior

그룹 복사 시:
1. AI가 조립한 구조화된 프롬프트가 클립보드에 복사됨
2. 그룹에 소속된 모든 원본 노트가 copied 처리됨 (lastCopiedAt 설정)
3. 그룹 카드 자체도 copied 처리 → 하단으로 이동

### AI가 생성하는 프롬프트 예시

입력 노트:
- "스택 메뉴 반짝임 버그 고쳐줘"
- "카드 패딩 너무 타이트, 폰트 15/19 맞나?"

AI 출력 (클립보드에 복사되는 내용):
```
다음 UI 버그들을 수정해줘.

- 스택 메뉴가 나타날 때 반짝이면서 패널이 나타나는 현상이 있음. 원인 확인하고 수정 필요.
- 스택 카드의 상하좌우 패딩이 너무 타이트함. 폰트 사이즈 15/19 확인 필요. macOS native font 사용 여부도 확인.

각 이슈의 원인을 진단한 뒤 수정해줘. 기존 동작을 깨트리지 않도록 주의.
```

## AI 호출 전략

### Trigger

- 새 노트가 추가될 때
- 노트가 삭제/수정될 때
- 일정 시간 debounce (e.g., 새 노트 추가 후 2초 대기 → 호출)

### Model

- **Claude Haiku** (claude-haiku-4-5-20251001)
- 비용: ~$0.006/call (입력 ~1,500 tokens + 출력 ~800 tokens)
- 지연: ~1초

### System Prompt 역할

1. 노트들을 주제/프로젝트/태스크 유형별로 분류
2. 각 그룹에 대해 적절한 프롬프트 조립 (지시 + 노트 내용 + tail)
3. 그룹 라벨 생성 (짧은 요약)
4. 원본 노트 내용은 보존 (재작성 금지, 구조화만)

### 중요 원칙

```
AI의 역할: 분류 + 구조화 + 적절한 지시 생성
AI가 하지 않는 것: 노트 내용 재작성, 요약, 의도 변경
```

## Data Model

### PromptGroup (신규)

```swift
struct PromptGroup: Identifiable, Codable, Sendable {
    let id: UUID
    let label: String              // AI가 생성한 그룹 라벨 ("PromptCue 버그 수정")
    let sourceCardIDs: [UUID]      // 소속 원본 노트 IDs
    let assembledPrompt: String    // AI가 조립한 완성 프롬프트
    let createdAt: Date
    let lastCopiedAt: Date?        // 복사 시점
}
```

### 기존 CaptureCard 변경

- 변경 없음. 원본 노트는 그대로 유지.
- 그룹 복사 시 소속 카드들의 `lastCopiedAt`만 업데이트.

## API Key 관리

### Phase 1: 개발용

- 환경변수 `PROMPTCUE_ANTHROPIC_API_KEY`로 주입
- 키 없으면 AI 그루핑 비활성, 기존 동작 유지

### Phase 2: 사용자용

- Settings에 API 키 입력 필드
- Keychain에 안전하게 저장
- 키 유효성 검증 (간단한 test call)
- 키 없으면 AI 기능 비활성 상태로 graceful degradation

## Architecture

```
노트 변경 감지
  → Debounce (2초)
  → uncopied 노트 수집
  → Haiku API 호출 (분류 + 프롬프트 조립)
  → PromptGroup 배열 생성
  → Stack UI 상단에 표시

그룹 복사
  → assembledPrompt → 클립보드
  → sourceCardIDs 전부 markCopied
  → 그룹 자체도 markCopied
```

### 파일 구조 (예상)

| 파일 | 위치 | 역할 |
|------|------|------|
| `PromptGroup.swift` | PromptCueCore | 그룹 모델 |
| `AnthropicClient.swift` | PromptCue/Services | API 호출 |
| `PromptAssemblyEngine.swift` | PromptCue/Services | 분류/조립 오케스트레이션 |
| `PromptAssemblyPrompts.swift` | PromptCue/Services | 시스템 프롬프트 템플릿 |
| `APIKeyPreferences.swift` | PromptCue/Services | 키 저장/로드 |
| `PromptGroupView.swift` | PromptCue/UI | 그룹 카드 UI |

## Risks

| Risk | Mitigation |
|------|------------|
| API 키 없는 사용자 | AI 기능 완전 비활성, 기존 bullet copy 유지 |
| API 호출 실패 | 에러 표시 + 기존 동작 fallback |
| 분류 품질 불안정 | 시스템 프롬프트 튜닝 + 사용자가 그룹 무시하고 개별 복사 가능 |
| 노트가 1개일 때 | 그루핑 불필요, 단일 노트 프롬프트로 조립 |
| 프라이버시 우려 | 사용자가 직접 API 키 입력 = 본인 계정으로 호출, 제3자 서버 경유 없음 |

## Success Criteria

- [ ] 5개 이상의 혼합 노트 → 올바른 그룹 분류
- [ ] 각 그룹에 적절한 지시(tail) 자동 생성
- [ ] 그룹 복사 → 소속 노트 전부 copied 처리
- [ ] API 키 없으면 기존 동작 그대로
- [ ] Haiku 호출 latency < 2초
- [ ] 비용 < $0.01/call
