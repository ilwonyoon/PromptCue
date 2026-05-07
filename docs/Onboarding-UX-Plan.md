# Onboarding UX Plan

## 목적

배포 대상이 넓어질 때, 앱을 처음 켠 사용자가 **5분 안에 자기에게 더 끌리는 한 lane을 끝까지 경험**하게 만든다. 두 lane을 다 강제로 통과시키지 않는다 — 사용자가 시작점을 고르고, 다른 lane은 자연스럽게 따라오게 한다.

### 두 개의 독립된 가치 명제 (Two Lanes)

Backtick은 사실상 **두 개의 다른 제품이 한 앱에 들어 있는** 형태다. 이걸 onboarding에서 명확히 분리해서 가르쳐야 한다 — 한 funnel로 묶으려 하면 둘 다 약해진다.

#### Lane 1 — Shared memory across AI agents
**Memory + MCP** 가 핵심. AI 도구들이 너의 장기 지식 layer에 직접 접근.

- **사용자 시나리오:** "내가 Claude에서 정리한 프로젝트 결정사항을 Codex가 코드 짤 때 그대로 참조" / "ChatGPT에서 한 brainstorm을 Claude Desktop이 이어받음"
- **시간 축:** 장기. 한 번 저장하면 며칠/몇 주 살아 있음
- **선결 조건:** MCP 연결 필수. 이게 없으면 가치 0
- **Aha 순간:** 한쪽에서 저장한 doc을 다른 쪽 AI가 자동으로 읽어 답을 줄 때
- **타깃 사용자:** "AI 여러 개 옮겨다니는데 매번 컨텍스트 다시 까는 게 짜증" 인 사람

#### Lane 2 — Capture & Stack for day-to-day vibe coding
**Capture + Stack** 한 묶음. 빠르게 떠오르는 prompt를 dump하고, 작업 중인 큐를 손 닿는 곳에 둠.

- **사용자 시나리오:** "코드 짜다가 머릿속에 다음 prompt가 떠오름 → ⌘+`` ` `` 하나로 dump → 지금 하던 거 끝나면 Stack에서 꺼내서 AI에 던짐" / "에러 메시지 / 스택 트레이스 / 스니펫을 휘발성 메모처럼 모아두는 통"
- **시간 축:** 단기. 8h auto-expire. 오늘의 작업 큐.
- **선결 조건:** **MCP 없어도 즉시 가치 발생.** 클립보드 + 단축키만으로 충분
- **Aha 순간:** vibe coding 중에 흐름 안 끊고 prompt를 쌓아두는 마찰 0의 경험
- **타깃 사용자:** "지금 한 시간짜리 코딩 세션 들어가는데 도구가 흐름 끊는 게 싫음" 인 사람

#### 두 lane은 독립적이다

| | Lane 1 (Shared memory) | Lane 2 (Capture & Stack) |
|---|---|---|
| **MCP 필요?** | 필수 | 없어도 OK (있으면 + 가치) |
| **시간 축** | 장기 (Memory) | 단기 (Stack 8h) |
| **마찰 비용** | 높음 (한 번 setup) | 0 (단축키) |
| **즉시 가치?** | setup 후에만 | 첫 ⌘+`` ` `` 부터 |
| **타깃 무드** | "AI 여러 개를 한 두뇌처럼" | "오늘 vibe coding 한 시간만" |

**중요:** 두 lane은 서로 hook이 다르다. 한 사용자가 "Lane 2가 더 끌림"이면 Lane 1을 강제로 통과시키지 않는다. Lane 2만으로도 retain 가능. 그리고 Lane 2를 쓰다 보면 자연스럽게 Lane 1으로 확장하고 싶은 순간이 온다 (예: 어제 capture했던 prompt를 Memory로 save하고 싶을 때).

### 핵심 카피

- 전체 brand: **"Stack for today. Memory for everything else."** (이미 `docs/Terminology.md`)
- Lane 1 카피: "One memory. Every AI."
- Lane 2 카피: "Don't break your flow. Capture. Stack. Move on."

### 현실적인 main AI 우선순위 (Lane 1에 한정)

ChatGPT를 통한 Lane 1 hook은 진입장벽(tunnel 설치 + 토큰 + ChatGPT 등록)이 너무 높다. Lane 1 funnel을 거기에 의존하면 좁아짐.

**Lane 1 우선순위:**
1. **Claude Desktop (Mac)** — 1차 main. Mac 사용자 베이스 가장 큼. config 파일 한 번 편집이라 자동화 가능.
2. **Claude Code** — 1-click이라 통과율 가장 높음, 단 개발자로 사용자 좁음
3. **Codex CLI** — 1-click이지만 더 좁음
4. **ChatGPT** — 가치 크지만 구현 위험. Phase 후순위.

Lane 1을 시작하면 **Claude Desktop을 default 추천** (감지 시).

### 성공 정의 (lane 분리)

Onboarding 완료 = **사용자가 고른 lane을 끝까지 통과** — 두 lane 모두 통과 안 해도 됨.

**Lane 1 완료 조건:** main AI 1개 MCP 연결 + 첫 doc save 또는 첫 stack item이 AI에서 read됨

**Lane 2 완료 조건:** 첫 capture + Stack에서 한 번 처리 (copy 또는 AI read) + Capture/Stack의 용도 차이 인지

**Cross-lane bonus (선택):** 한 lane을 끝낸 사용자에게 다른 lane 진입점 제공
- Lane 2 → Lane 1: "Want to make these visible to your AI?" → MCP 연결 sub-flow
- Lane 1 → Lane 2: "Try Capture — it's the fastest way to feed your memory" → Capture 데모

게이트:
- **둘 다 미달:** onboarding skip 또는 미완성 → 메뉴바 nudge로 두 lane 모두 부드럽게 유도
- **한 lane만 완료:** 그 사용자는 "이미 가치를 얻고 있는" 상태 → 다른 lane은 부드러운 cross-sell, 강제 X
- **둘 다 완료:** 가장 강력한 retention 신호. 별도 친절한 마무리 카드

---

## 현재 상태 (2026-05-02 기준)

조사한 결과 다음과 같다:

- **첫 실행 분기 없음.** `AppCoordinator`/`AppDelegate`/`PromptCueApp` 어디에도 `hasCompletedOnboarding`, `firstLaunch`, `welcome` 같은 상태 키가 없다. 처음 켜면 그냥 메뉴바 아이콘만 생기고 끝.
- **MCP 연결 UX는 Settings 안에 있음.** `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift`에 Claude Desktop / Claude Code / Codex 3종이 정의돼 있고, 각각 config 파일 경로가 다르고 일부는 CLI 자동화, 일부는 직접 JSON 편집을 한다.
- **ChatGPT는 별도 경로.** `docs/ChatGPT-Setup-Guide.md`에 ngrok / cloudflared 두 옵션이 있는데, 이건 마크다운으로만 존재하고 앱 안에서 단계별로 안내되지 않는다. ngrok 한 번 깔고 토큰 등록하고 터널 띄우는 흐름은 신규 사용자 기준으로 절대 친절하지 않다.
- **Capture / Stack 학습 자료 없음.** 단축키 (`Cmd+`` ` ``, `Cmd+2`)는 default로 등록돼 있지만, 첫 사용자에게 그걸 알려주는 UI가 없다.

즉 지금은 "메뉴바 앱이 깔렸다"와 "MCP가 연결돼서 가치가 발생한다" 사이의 다리가 통째로 비어 있다.

---

## 디자인 원칙

1. **두 lane을 명확히 분리해서 보여 준다.** Welcome 다음 화면에서 사용자가 "내가 뭘 먼저 해보고 싶은지" 고른다. 한 lane을 다른 lane의 prerequisite처럼 만들지 않는다.
2. **각 lane은 독립적으로 완결된다.** Lane 2를 골라서 끝까지 가도 사용자는 가치를 얻는다. Lane 1을 모른 채로 retention 가능.
3. **읽지 않고 한 번 해본다.** 설명 → 따라하기가 아니라, 실제로 capture를 만들고 실제로 MCP를 연결한다. 가짜 데모 금지.
4. **언제든 빠져나갈 수 있다.** "Skip"은 1차 시민. 나중에 다시 시작할 수 있도록 메뉴/Settings에서 onboarding 재진입 가능.
5. **MCP 연결은 클라이언트 단위로 분리.** Lane 1 안에서도 사용자는 본인이 쓰는 도구만 신경 쓴다.
6. **각 MCP 단계마다 검증 신호.** "되어 있다"고 믿게 하지 않고, 앱이 실제로 연결을 확인. 실패 시 무엇이 틀렸는지 한 줄로.
7. **Cross-sell은 부드럽게.** 한 lane 끝낸 사용자에게 다른 lane 진입점은 단 한 줄로 제시. 강제 X.
8. **BW 디자인 시스템 유지.** Onboarding이라고 색이 튀지 않는다. 강조는 stroke와 typography로.

---

## 전체 플로우 (Lane 분기형)

```
앱 첫 실행
  ↓
[1] Welcome — "Two things Backtick does. Pick where to start."
  ↓
[2] Lane picker — 두 카드 큰 비교:
       [A] "Connect my AI to a memory I control"   (Lane 1)
       [B] "Capture prompts during coding, fast"   (Lane 2)
       [Skip — just give me the menubar app]
  ↓
  ┌─────────────────────────────┴─────────────────────────────┐
  ↓                                                            ↓
LANE 1 (Shared Memory)                              LANE 2 (Capture & Stack)
  ↓                                                            ↓
[1A-1] Pick main AI (Claude Desktop default)        [2B-1] What's Capture for? + try
[1A-2] Connect (config edit / 1-click) + verify     [2B-2] What's Stack for? + try (copy or paste)
[1A-3] Save first doc to Memory + AI reads it       [2B-3] Show keyboard shortcut + flow story
  ↓                                                            ↓
  └────────────┬──────────────────────────────────────┬────────┘
               ↓                                       ↓
       Lane 1 done card +                    Lane 2 done card +
       cross-sell to Lane 2 (one line)       cross-sell to Lane 1 (one line)
               ↓                                       ↓
       완료 → 메뉴바 hint + Settings 진입점 + 미완 lane은 부드러운 nudge
```

각 단계는 "다음" / "건너뛰기" / (lane 안에서는) "Try the other lane instead" 액션. Lane 안 진행도는 1/3 dot indicator. **두 lane이 동등한 무게로 picker에 노출된다.** A가 default가 아니다 — 사용자의 선택에 맡긴다.

**중요한 디자인 결정 — Capture와 Stack은 한 lane 안에서 분리된 두 단계 [2B-1][2B-2]로 가르친다.** 둘은 다른 도구이고 사용자가 용도 차이를 인지해야 가치의 절반을 안 놓친다. 하지만 둘 다 day-to-day 도구라는 같은 lane에 속하므로, 한 lane 안에서 자연스럽게 이어 가르친다.

**Lane 1의 [1A-3]는 doc save를 강조한다 — Lane 2의 stack과 다른 차원**임을 명시. Stack은 today's queue, Memory는 long-term doc. Lane 1의 진짜 가치는 doc/memory 쪽에 있고, MCP 연결은 그걸 위한 다리.

---

## 단계별 상세

### [1] Welcome

**목표:** "Backtick은 두 가지를 한다 — 둘 중 하나를 골라서 시작해 봐"라는 mental frame을 심는다. 한 가치 명제로 단순화하지 않는다.

**화면:**
- 한 줄 카피 (예: "Two ways Backtick helps. Pick one to start.")
- 비주얼: 좌/우로 갈라진 두 영역 — 왼쪽은 N개 AI 아이콘이 한 메모리를 가리키는 다이어그램, 오른쪽은 ⌘+`` ` `` 키캡 + Stack 카드 모양
- "Continue" / "Skip onboarding"

**기술 노트:**
- 별도 `OnboardingWindowController` 신설 (CapturePanel/StackPanel과 동일 패턴: NSWindowController가 NSPanel + SwiftUI hosting)
- 첫 실행 판정: `UserDefaults` key `com.backtick.onboarding.completed` (Bool) + 단계별 진행 상태 `com.backtick.onboarding.step` + 어느 lane을 골랐는지 `com.backtick.onboarding.lane` ("lane1" | "lane2" | "skipped")
- LSUIElement이라 Dock 아이콘이 없어 첫 실행 감지 시 자동 부상 필요. `NSApp.activate(ignoringOtherApps: true)` + 메뉴바 아이콘에 시각적 강조 (예: 1회 pulse)

### [2] Lane picker — 시작점 선택

**목표:** 사용자가 본인에게 더 끌리는 lane을 고른다. **둘 다 강제하지 않는다.** 두 카드는 동등한 무게.

**화면 카피:** "Where would you like to start?"

**두 카드 (동등 크기, 좌우 배치):**

#### Card A — "Connect my AI to a memory I control"
- 아이콘: AI 도구들이 한 메모리 layer를 가리키는 그림
- 한 줄: "Your AI tools read from a memory you maintain. Across Claude, Codex, ChatGPT — same memory."
- Sub-bullet 2개:
  - "5 min setup — connect your main AI"
  - "Best if: you bounce between AI tools and lose context"
- 시간 표시: "~5 min"

#### Card B — "Capture prompts during coding, fast"
- 아이콘: ⌘+`` ` `` 키캡 + Stack 카드 mock
- 한 줄: "Don't break your flow. Hit ⌘+`` ` `` from anywhere, dump a prompt, keep going. Your stack is always one keystroke away."
- Sub-bullet 2개:
  - "Works the moment you press the shortcut"
  - "Best if: you do long coding sessions and want zero-friction prompt staging"
- 시간 표시: "~2 min"

#### 하단 옵션
- "Skip — just give me the menubar app" — onboarding을 통째로 닫음, 메뉴바 nudge로 두 lane 모두 사후 유도
- "I want both" — 작은 텍스트 링크: "Pick one for now. We'll show the other when you're ready." (양쪽 lane을 한 세션에 강제하지 않음)

**기술 노트:**
- 사용자 선택을 `com.backtick.onboarding.lane`에 저장
- "Skip"은 가장 약한 시각 강조 — 메뉴바 nudge가 어떻게든 다시 잡을 수 있도록

---

## Lane 1: Shared Memory

### [1A-1] Pick main AI

**목표:** Lane 1 사용자가 매일 가장 많이 쓰는 AI 1개를 고른다.

**화면 카피:** "Which AI do you use most? We'll connect Backtick to it first."

**4-tile 그리드 (라디오 단일 선택):**

| Tile | 감지 방법 | 표시 | Default 추천 |
|---|---|---|---|
| Claude Desktop | `~/Library/Application Support/Claude/` 존재 | "✓ Detected" / "Get Claude Desktop →" | ★ 감지 시 자동 선택 |
| Claude Code | `which claude` | "✓ Detected — 1-click" / "—" | 2순위 |
| Codex CLI | `which codex` | "✓ Detected — 1-click" / "—" | 3순위 |
| ChatGPT (web) | 항상 노출 | "Needs 5-min tunnel setup" | 마지막 |

UX 디테일:
- **Default selection:** 감지된 클라이언트 중 우선순위 가장 높은 것 (대부분 Claude Desktop)
- 감지 안 된 tile은 흐리게 표시 + "Get {client} →" 외부 링크
- ChatGPT는 항상 enabled이지만 "Needs setup" 라벨로 진입장벽 미리 알려줌
- 하단: "You can add more later in Settings → Connectors."

하단 액션:
- [Continue]
- [Try the other lane instead] → [2] Lane picker로 복귀

**기술 노트:**
- 감지 로직은 `MCPConnectorSettingsModel`에 이미 일부 있음 — 거기 확장
- 사용자가 감지 안 된 tile을 선택해도 진행은 가능 — [1A-2]에서 "Install first" 안내

### [1A-2] Connect main AI + verify

**목표:** 선택한 클라이언트와 Backtick MCP가 실제로 통신하는 상태를 만든다. 클라이언트별로 다른 sub-stepper.

**시각 자료:** 이 단계의 모든 클라이언트별 스크린샷 / 비디오 / 다이어그램 명세는 `docs/Connection-Walkthrough-Visuals-Plan.md`에 따로 정의. 글로만 설명하지 말고 실제 외부 앱 화면을 보여 줘야 사용자가 막히지 않는다.

#### [1A-2-Code] Claude Code / Codex CLI (1-click 경로)

**플로우:**
1. 한 줄 설명: "Backtick will register itself as an MCP server in your `claude` / `codex` config."
2. **[Connect] 버튼 1개.** 누르면 내부적으로 `claude mcp add backtick ...` 또는 codex 등가 명령 실행.
3. 진행: spinner → ✓ "Connected" 또는 ✗ "Failed: <한 줄 사유>"
4. 검증:
   - Backtick MCP server가 health endpoint 응답하는지 확인
   - `claude mcp list` 또는 등가 명령으로 등록 여부 재확인

**기술 노트:**
- `MCPConnectorSettingsModel.supportsTerminalSetupAutomation`에 hook
- 검증은 새로 추가 필요: `verifyMCPConnection(client:)` → Bool

#### [1A-2-Desktop] Claude Desktop (config 편집 경로)

**플로우:**
1. 한 줄 설명: "Claude Desktop reads its MCP servers from a config file. We'll add Backtick to it."
2. 3-step expander:
   - Step 1: "Preview the change" — diff 형태로 현재 vs 적용 후. 다른 MCP 서버 보존 강조.
   - Step 2: **[Apply]** — atomic 저장 + 백업 (`.backup-<timestamp>.json`)
   - Step 3: **[Restart Claude Desktop]** — 실행 중이면 종료 + 재실행
3. 검증:
   - 즉시: config 파일이 valid JSON + Backtick entry 있는지
   - 지연: 재시작 후 5초 대기 → MCP server에 incoming connection (`BacktickMCPConnectionActivity`)
   - 30초 timeout 시 "Couldn't verify automatically — open Claude and look for Backtick in tools list" 수동 verify

**기술 노트:**
- Config path: `homeConfigRelativePath` (이미 정의됨)
- Atomic write + 백업 패턴 신규 필요
- MCP server connection 카운터 추가

#### [1A-2-ChatGPT] ChatGPT (tunnel sub-onboarding)

가장 복잡 — 4-step sub-stepper:

**Step 1 — Choose tunnel:**
- ngrok (기본 추천): "2 min, free tier 2h disconnect"
- Cloudflare: "Always-on, needs domain"

**Step 2 — Install + auth (ngrok 기준):**
- Detect `which ngrok` → 분기
- 미설치: `brew install ngrok` copy 버튼 (Backtick이 직접 brew 안 돌림)
- 토큰 미등록: "Get your token at ngrok.com" 외부 링크 + 토큰 입력 + [Save] (`ngrok config add-authtoken <token>`)

**Step 3 — Launch tunnel:**
- [Launch tunnel] 버튼 (Settings 메커니즘 재사용)
- URL 표시 + "We'll keep this running"

**Step 4 — Connect in ChatGPT:**
- Remote MCP URL 큰 글씨 + [Copy URL]
- "Open ChatGPT → Settings → Apps → Add App. Paste. Authorize."
- [I've added it] → 검증 (`BacktickMCPConnectionActivity`에서 ChatGPT origin incoming)

**기술 노트:**
- `docs/ChatGPT-Setup-Guide.md` 텍스트 거의 그대로 활용
- Cloudflare는 외부 docs 링크만

#### 모든 [1A-2] 경로 공통 fallback

연결 실패 시:
- 에러 코드/메시지를 그대로 보여 주지 말 것. "What went wrong" 한 줄 + "Show details" expander.
- "Get help" → GitHub Issues
- [Retry] / [Skip for now]

### [1A-3] Save first doc to Memory + AI reads it (★ Lane 1 hook)

**목표:** **Memory + MCP의 진짜 가치는 doc save에 있다.** 단순 stack read가 아니라, "내가 저장한 장기 지식을 AI가 그대로 읽어 답해 준다"가 Lane 1의 aha 순간.

**A. 화면 — "What's Memory for?":**

> **Memory = the long layer.**
>
> Stack is for today (8h auto-clear). Memory is for things you want to keep — decisions, plans, project context.
>
> When you save a doc to Memory, **every AI you connected can read it.** That's the point.

[Save my first doc] 버튼.

**B. 실제 시도:**
1. Memory 패널에 빈 doc 입력창. Suggested topic 1-2개 제공:
   - "Backtick onboarding test — checking if my AI can read this"
   - "My current project — {project name 자동 추출 가능 시}"
2. 사용자가 짧은 doc 한 개 작성 + [Save]
3. ✓ "Saved to Memory."
4. **Sample prompt 큰 글씨로:** `"What's in my Backtick memory?"` + [Copy]
5. "Open {main AI} and paste this. Your AI will answer with what you just wrote."
6. 검증: `BacktickMCPConnectionActivity`에서 incoming MCP read polling, 60-90s timeout
7. 잡히면: 큰 confirmation "✓ {main AI} just read your memory." — 카드에 doc 일부 inline 표시
8. Timeout: [I tried it] 수동 진행

**C. Lane 1 마무리 카드:**
> That's Lane 1.
>
> From now on: anything you save to Memory shows up in {main AI}. Connect more AI tools later — same memory will be there.

[Done] / [Try Lane 2 instead — Capture & Stack →] (cross-sell, 한 줄)

**기술 노트:**
- Memory save path는 `documentStore`/Memory panel 메커니즘 재사용
- Doc save 후 read polling 메커니즘은 [1A-2] verify와 같은 신호
- "Lane 1 완료" 마킹 → `com.backtick.onboarding.lane1.completed = true`

---

## Lane 2: Capture & Stack (day-to-day vibe coding)

### [2B-1] Capture — when/why first, then try

**목표:** Capture를 **마찰 0의 dump 도구**로 인지시킨다. 코딩 흐름 안 끊고 prompt 쌓아두는 도구.

**A. 화면 — "What's Capture for?":**

> **Capture = friction-zero dump.**
>
> You're coding, you're in flow, and a prompt pops in your head — a question for your AI, a refactor idea, a snippet you just copied. Hit `⌘+`` ` `` and dump it. Don't break your flow.
>
> Examples:
> - "Why does this hook re-render twice?"
> - "Refactor: extract the useState chain"
> - (paste error log from terminal)

[Try it now] 버튼.

**B. 실제 시도:**
1. Onboarding 창이 작아지고 capture 패널이 뜬다
2. 입력창 위 한 줄: "Type anything. Press Enter to save."
3. Enter → ✓ "Captured."
4. **단축키 학습 (강조):** 큰 키캡 모양 `⌘` + `` ` `` + "From now on, press this from anywhere — Cursor, VSCode, terminal, browser. Backtick floats over everything."

**C. 마무리:**
> Got it. Now let's see where it went — and what to do with it.

[Continue to Stack →]

**기술 노트:**
- `AppModel`이 capture-completed signal을 emit하면 onboarding이 받아서 다음
- mental model 카드는 wall-of-text 금지, 좌측 큰 글자 + 우측 example list

### [2B-2] Stack — when/why first, then try

**목표:** Stack이 **today's queue**임을 인지시킨다. Capture가 "넣기"라면 Stack은 "꺼내 쓰기 또는 줄 세우기".

**A. 화면 — "What's Stack for?":**

> **Stack = today's queue.**
>
> Capture dumps things in. Stack is where you decide what to do with them — copy to paste, or hand the whole thing to your AI.
>
> Stack auto-clears every 8h. It's not a notebook — it's the working surface for **right now**.
>
> Brand line: **"Stack for today. Memory for everything else."**

[Show me my Stack] 버튼.

**B. 실제 시도:**
1. Stack 패널 자동 열림. 방금 capture한 prompt가 맨 위
2. 카드 옆 풍선으로 두 가지 사용법 노출:
   - **(a) Copy** — 클립보드, 어디든 paste. "When you want to send it manually."
   - **(b) Multi-select & Copy** — 여러 prompt 골라서 한 번에 paste. (vibe coding 시 자주 쓰는 패턴)
3. 둘 중 하나라도 액션 → ✓ "Done"

**C. 핵심 메시지 마지막 카드:**
> The Lane 2 loop:
> **dump (Capture) → queue (Stack) → use (copy)**.
>
> You can do this without ever connecting an AI. It just works as a fast prompt staging surface.

[Continue]

**기술 노트:**
- 카드 "copied" 상태는 `markCopied()` 사용
- Stack 패널 위 onboarding overlay/coach mark layer 신규 필요
- **Lane 2에서는 MCP read 액션을 안 가르친다.** Lane 2는 MCP 없어도 가치 발생이 핵심. MCP 연결한 사용자에게는 [2B-3] 마무리 카드에서 한 줄 cross-sell.

### [2B-3] Flow story + shortcut anchor (Lane 2 마무리)

**목표:** Lane 2 사용자에게 vibe coding 시나리오를 짧은 스토리로 보여 주고, 단축키를 다시 한 번 강조해서 "근육 기억"을 만든다.

**A. 화면 — "Your day with Backtick":**

3-step 미니 시나리오 카드 (시각적으로 가벼움):

```
1. You're coding in {Cursor / VSCode / wherever}.
2. A prompt idea pops. You hit ⌘+` — drop, gone in <1s.
3. Later, when you need it, ⌘+2 opens Stack. Copy. Paste. Move on.
```

**B. 단축키 anchor:**
큰 키캡 두 개 나란히:
- `⌘` + `` ` `` → Capture
- `⌘` + `2` → Stack toggle

"These are the only two shortcuts you need. Customize them in Settings if you want."

**C. Lane 2 마무리 카드:**
> That's Lane 2.
>
> Capture & Stack work without any AI connection — they're just a faster way to handle prompts.
>
> *(MCP 연결 안 된 경우)* When you're ready, you can connect an AI tool to read your stack/memory directly — that's Lane 1.
>
> *(이미 MCP 연결돼 있으면 카피 다름)* Your AI is already connected — try asking it "What's in my Backtick stack?" anytime.

[Done] / [Try Lane 1 instead — connect AI memory →] (cross-sell, 한 줄)

**기술 노트:**
- Lane 2 완료 마킹 → `com.backtick.onboarding.lane2.completed = true`
- 이 단계는 사용자가 실제 액션을 하지 않아도 통과 — 단축키 인지가 목표
- MCP 연결 상태에 따라 마무리 카피 분기

---

## Cross-lane bonus (선택, 마무리 카드 이후)

한 lane 통과 후 사용자가 [Try other lane] 한 줄을 클릭하면 그 lane의 첫 단계로 진입. 강제 X.

이 시점에서는 사용자가 이미 한 lane의 가치를 봤으므로, 두 번째 lane의 mental model 카드를 짧게 압축할 수 있다. (예: Lane 1을 끝낸 사용자에게 Lane 2의 ⌘+`` ` `` 단축키만 한 화면으로 보여 줘도 충분.)


## 온보딩 종료 후

- 메뉴바 아이콘 위에 1회 한정 hint balloon: "Press `Cmd+`` ` `` to capture anywhere."
- 메뉴바 메뉴에 "Show onboarding again" 항목 (또는 Settings → Help)
- Settings에 새 섹션 "Get Started" — onboarding 재진입 + 각 MCP 연결 가이드 링크

---

## 측정 (당장 안 해도 자리는 잡아 둘 것)

각 단계 진입/완료를 local에 anonymous로 카운트만 해 둬도 큰 이득:
- `onboarding.welcome.shown`
- `onboarding.capture.completed`
- `onboarding.stack.copied`
- `onboarding.mcp.{client}.connected`
- `onboarding.skipped_at_step.{n}`

수치를 외부 전송하지 않더라도, Settings → Diagnostics에 노출하면 사용자 인터뷰 시 본인이 어디서 막혔는지 같이 볼 수 있음.

---

## 단계별 구현 우선순위 (Lane 분기형)

이 plan을 한 번에 다 만들지 않는다. 작게 자른다. **각 lane은 독립적으로 배포 가능 — 하나만 먼저 ship해도 사용자에게 가치 전달.**

배포 순서 결정:
- **Lane 2 (Capture & Stack)가 구현 비용이 가장 작고 즉시 가치 발생** — 외부 의존성 0, MCP 검증 불필요
- **Lane 1 (Shared memory)은 구현 위험이 더 큼** — config 편집, 외부 앱 재시작, MCP read polling, 검증 fallback
- 따라서 **Lane 2 → Lane 1** 순서로 phase 분리. 동시에 못 가도 Lane 2가 먼저 나가면 사용자에게 즉시 가치.

---

**Phase 1 — Onboarding 골격 + Lane 2 (Capture & Stack) 완성 (1.5주):**
- 첫 실행 감지 (`hasCompletedOnboarding`, `onboarding.lane` UserDefaults)
- `OnboardingWindowController` 신설
- [1] Welcome (lane 분기 mental frame)
- [2] Lane picker (두 카드 동등)
- **Lane 2 전체:** [2B-1] Capture overlay → [2B-2] Stack overlay → [2B-3] Flow story
- Stack 패널 위 onboarding overlay/coach mark layer
- Settings에 "Show onboarding again" + 메뉴바 nudge
- Skip 액션 + 메뉴바 재진입

**Phase 1 통과 = Lane 2 사용자는 onboarding 완전히 끝남.** Lane 1 사용자는 [2] picker에서 "Lane 1 coming soon — explore the menubar app for now" 안내 후 종료. 비참하지만 ship 가능.

---

**Phase 2 — Lane 1 핵심 (Claude Desktop main + 1-click 경로) (2주):**
- [1A-1] Pick main AI (4-tile 라디오, Claude Desktop default)
- **[1A-2-Desktop] Claude Desktop config 편집 — diff preview + atomic apply + 백업 + 재시작 안내 + 지연 검증** (★ Phase 2 핵심 구현물)
- [1A-2-Code] Claude Code / Codex 1-click 경로 (구현 비용 작아서 같이 묶음)
- [1A-3] Save first doc to Memory + read polling 검증
- Memory 패널의 doc 입력 UI에 onboarding overlay layer

**Phase 2 통과 = Lane 1 사용자도 Claude 계열 (Desktop / Code / Codex) 어느 것이든 끝까지 통과 가능.** 가장 큰 사용자 그룹 커버.

---

**Phase 3 — Cross-lane bonus + Lane 1 ChatGPT tunnel (2주, 위험):**
- Cross-lane 진입점 ("Try the other lane" 한 줄)
- [1A-2-ChatGPT] tunnel sub-onboarding (4-step ngrok 경로)
- 토큰 입력 + tunnel 시작 + URL 복사 + ChatGPT 등록 + 검증
- Cloudflare는 외부 docs 링크만
- **위험:** ChatGPT 경로 funnel이 좁을 수 있음. Phase 1+2 데이터 보고 ChatGPT 수요가 정말 큰지 확인 후 진행

---

**Phase 4 (선택) — 분석 / 측정 (1주):**
- 단계별 funnel 카운터:
  - `onboarding.lane.picked.{1|2|skipped}` — lane 분포
  - `onboarding.lane1.completed`, `onboarding.lane2.completed`
  - `onboarding.lane1.failed_at_step.{1A-1|1A-2|1A-3}`
- Settings → Diagnostics 노출
- Lane 분포 데이터로 Phase 3 (ChatGPT) 우선순위 재평가 — Lane 1 진입률 vs Lane 2 진입률 비교

---

**핵심:** Phase 1만 나가도 사용자의 절반 (Lane 2 선택자)에게는 onboarding이 완전히 동작. 나머지 절반은 "곧 옴" 상태로 대기. Lane 1 구현 위험을 Phase 2까지 미루는 비용이 있지만, ship 빠르고 학습 빠름.

---

## 열린 질문

### Lane 분기 자체에 대한 질문 (가장 중요)
1. **두 lane 카드의 우열을 어떻게 시각적으로 처리할까?** "동등 무게"가 원칙이지만 사용자는 default가 없으면 frozen될 수도. 옵션: (a) 둘 다 동등, 첫 번째 카드는 미세하게 hover 강조, (b) 자기 환경에 맞춰 추천 — Claude 감지되면 Lane 1, 아무것도 없으면 Lane 2.
2. **Lane 2를 끝낸 사용자에게 Lane 1 cross-sell을 얼마나 강하게?** 너무 약하면 Lane 1 진입률 0, 너무 강하면 "또 뭘 하라는 거야" 짜증. 현재 안: 마무리 카드의 한 줄 링크만. 메뉴바 nudge에서는 Lane 1을 lane2 완료자에게 며칠 후 별도 prompt.
3. **사용자가 두 lane을 둘 다 onboarding에서 끝내고 싶다면?** 현재 안은 "한 번에 하나" — picker에서 "I want both" 클릭해도 한 lane 끝나고 cross-sell. 한 세션에서 다 가르치면 인지 부담 큼. 이게 맞는 결정인지 검증 필요.

### Lane 1 (Shared Memory) 구현 위험
4. **MCP 연결 검증을 어디까지 자동화할 수 있나?** (가장 위험한 부분)
   - Claude Code / Codex: CLI 출력 파싱 가능, 비교적 안전
   - Claude Desktop: 외부 앱 재시작 → MCP server에 incoming connection이 잡혀야 검증 — 사용자가 Claude를 다시 띄우지 않으면 영원히 연결 안 됨. 30s timeout + 수동 verify로 가야 할 듯
   - ChatGPT: tunnel URL → ChatGPT가 add → 사용자가 authorize까지 해야 첫 connection — 검증까지 사용자 액션이 3개. 어디까지 polling하고 어디서 포기할지 기준 필요
5. **[1A-3] doc save 후 read polling timeout?** 사용자가 sample prompt 복사 → AI 앱 전환 → paste → 응답까지 60s 충분한가? 90s + 수동 진행 fallback이 안전할지도.
6. **연결 실패 시 첫 사용자가 디버깅을 할 수 있나?** "What went wrong"을 한 줄로 매핑 필요 — config 권한, claude CLI 버전 mismatch, 토큰 잘못, tunnel 충돌 등.
7. **Claude Desktop 미감지 사용자에게 무엇을 default로?** Claude Code/Codex가 있으면 그쪽, 아무것도 없으면 "Get Claude Desktop →" 외부 링크 + 다른 옵션. 빈 상태에서 ChatGPT가 default가 되면 funnel 무너짐.

### Lane 2 (Capture & Stack) 디자인 디테일
8. **Capture/Stack 패널 위 coach mark의 디자인 토큰?** 새 semantic token group이 필요할 수도.
9. **[2B-1] / [2B-2] mental model 카피 길이.** "What's it for?" 카드가 3-5초인지 7-10초인지. 짧으면 인지 안 되고 길면 skip. A/B 또는 사용자 인터뷰 필요.
10. **Stack 가르칠 때 Memory를 얼마나 언급?** 너무 많으면 "그럼 Memory도 지금 배워야?" 부담, 너무 안 하면 brand line 절반 빠짐. 현재 안: 한 줄로 vector만 심기.

### 시스템 / 인프라
11. **첫 실행 감지가 LSUIElement 앱에서 자연스럽게 부상하는 게 가능한가?** Dock 아이콘 없으니 — 메뉴바 아이콘 클릭 유도? `NSApp.activate(ignoringOtherApps: true)`로 강제 fore?
12. **다국어.** 한국어 사용자에게 영어 onboarding 그대로 OK? ko 우선 → en fallback?
13. **Skip / 미완 lane → 메뉴바 nudge 빈도.** 너무 자주면 짜증, 너무 적으면 잊음. 첫 7일 동안 1일 1회 + 첫 capture 시 1회가 시작점.
