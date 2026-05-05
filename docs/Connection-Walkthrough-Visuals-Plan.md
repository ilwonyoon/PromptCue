# Connection Walkthrough — Visual Plan

이 문서는 **Onboarding-UX-Plan.md의 Lane 1 [1A-2] Connect main AI + verify** 단계에서 사용할 시각 자료(스크린샷, 짧은 비디오, 인-앱 일러스트)를 정의한다.

연결은 onboarding의 가장 위험한 단계 — 글만으로는 사용자가 어디서 막히는지 모른다. 외부 앱(Claude Desktop, ngrok dashboard, ChatGPT settings)의 실제 화면을 같이 보여 줘야 한다.

---

## 원칙

1. **외부 앱 화면을 그대로 보여 준다.** "Claude Desktop의 Settings를 열어"라고 글로 쓰지 않고, **실제 Claude Desktop Settings 스크린샷**을 보여 준다. 사용자는 그림에서 본 그 위치를 자기 화면에서 찾는다.

2. **스크린샷은 "annotated still"이 기본.** 비디오는 30초 넘으면 거의 안 봐 — 진짜 필요한 곳에만 짧게(<10s, 자동 반복).

3. **시각 자산은 1단계당 1-2개.** 4개 넘으면 사용자는 어떤 그림을 봐야 할지 헷갈림. 한 단계 = 한 결정 = 한 그림.

4. **Backtick UI 화면은 in-app 렌더가 정답일 때가 있다.** 진행 중인 onboarding 자체가 그 UI 위에 떠 있으면, 스크린샷 대신 라이브 패널을 옆에 띄워서 화살표/풍선으로 가리키는 게 더 나음. 외부 앱은 스크린샷, Backtick은 라이브.

5. **OS / 클라이언트 버전 표기 필수.** "Claude Desktop 0.7.x — Mar 2026" 정도로 캡션. 외부 앱 UI는 자주 바뀐다.

6. **Light/Dark 모두 캡처.** Backtick은 BW theme이니 둘 다 자연스럽게 보여야 함. 외부 앱은 Light 1개 기본 + Dark는 dark 사용자에게만 swap.

7. **다국어.** 외부 앱은 영문 UI를 default 캡처 (사용자가 영문 ChatGPT/Claude 환경 가능성이 가장 큼). 한국어 사용자에게는 짧은 자막/텍스트 오버레이만 ko로 번역.

---

## 자산 종류

| 종류 | 파일 형식 | 용도 | 길이 / 크기 |
|---|---|---|---|
| Screenshot — annotated still | PNG, @2x | 외부 앱의 정적 화면 (Claude Settings 같은) | 보통 800-1200 px wide |
| Short loop — silent | MP4 / WebM, autoplay loop | 짧은 액션 시퀀스 (예: ngrok 터미널 띄우는 동작) | 5-10s, 무성, <2 MB |
| In-app live overlay | SwiftUI overlay | Backtick 자체 UI 가리킬 때 | 라이브 |
| Diagram — static | SVG | 개념 도해 (어떤 것이 어디로 연결되는지) | 인라인 SVG |

**비디오는 정말 필요한 곳에만.** 기본은 스크린샷. 비디오 만들 때마다 유지보수 비용이 따라온다 (외부 앱 UI 바뀌면 다시 찍어야 함).

---

## 클라이언트별 자산 명세

### Claude Desktop (가장 중요 — Phase 2 핵심)

연결 경로: config 파일 자동 편집 → 사용자가 Claude Desktop 재시작 → Backtick이 connection polling.

#### 자산 1 — `claude-desktop-detect.png`
- **목적:** [1A-1] Pick main AI 화면에서 "✓ Detected" 라벨 옆에 노출. 사용자가 "내 환경 인식됐다"는 신호.
- **내용:** Claude Desktop 메뉴바 아이콘 + Dock 아이콘 작은 컴포지션. 또는 Claude Desktop 아이콘 단독 + ✓ 마크.
- **annotation:** 없음. 식별용 thumbnail.

#### 자산 2 — `claude-desktop-config-diff.svg` (in-app generated)
- **목적:** [1A-2] Connect 단계의 Step 1 "Preview the change".
- **내용:** 사용자의 실제 `claude_desktop_config.json` 파일 내용 + Backtick이 추가할 entry를 diff 형태로 나란히. 빨간/초록 대신 Backtick BW palette — 추가 줄은 stroke + 굵은 typography로 강조.
- **이건 정적 스크린샷이 아니라 **실시간 렌더링**.** 사용자별로 config 내용이 다르므로 매번 새로 그림.

#### 자산 3 — `claude-desktop-restart.png` (annotated)
- **목적:** Step 3 "Restart Claude Desktop" — 사용자가 Claude를 재시작해야 하는 위치 안내.
- **내용:** Claude Desktop 메뉴바의 Quit 메뉴 또는 ⌘Q 키캡 그림.
- **annotation:** "Quit completely, then re-open" 한 줄. 사용자가 "Cmd+W로 닫는" 것과 "Cmd+Q로 종료"의 차이를 모를 수 있음.
- **대안:** Backtick이 자동으로 Claude를 quit + relaunch해 주면 이 자산 불필요. 자동 처리가 첫 번째 선택.

#### 자산 4 — `claude-desktop-tools-list.png` (annotated, 검증용)
- **목적:** 자동 검증 timeout 시 fallback — 사용자가 직접 Claude UI에서 Backtick MCP가 등록됐는지 확인하게.
- **내용:** Claude Desktop의 MCP tools 패널 또는 도구 목록 화면 스크린샷. Backtick entry가 어디에 보이는지 화살표로 강조.
- **annotation:** "Look for `backtick` here. If you see it, you're connected." 한 줄.
- **위험:** Claude Desktop이 MCP tools list를 어디에 노출하는지는 버전마다 변함. 자산 캡션에 버전 명시 + 외부 docs 링크 (Anthropic의 MCP 가이드).

#### 짧은 비디오?
- **불필요.** 위 4개 스크린샷이면 충분. config 편집은 Backtick이 자동으로 하므로 사용자가 따라 할 동작이 거의 없음.

---

### Claude Code / Codex CLI (1-click — 가장 단순)

연결 경로: Backtick이 `claude mcp add backtick ...` 등가 명령을 사용자 대신 실행 → 검증.

#### 자산 1 — `claude-code-detect.png`
- **목적:** [1A-1] picker tile thumbnail.
- **내용:** Claude Code 로고 또는 터미널 + `claude` 프롬프트 스크린샷.

#### 자산 2 — `claude-code-cli-output.png` (annotated)
- **목적:** [1A-2-Code] 검증 단계에서 사용자가 "정말 됐나?" 물을 때 expander 안에 노출.
- **내용:** 터미널에서 `claude mcp list` 실행 결과의 스크린샷. `backtick` 항목이 강조.
- **annotation:** "Backtick is registered. You can verify yourself: `claude mcp list`" — copy 가능한 명령어 같이.

#### 자산 3 — `claude-code-sample-prompt.png` (선택)
- **목적:** 마무리 단계에서 "이제 Claude Code 세션에서 이걸 물어봐" 안내.
- **내용:** 터미널에서 `claude` 세션 안에 `What's in my Backtick memory?` 입력하는 모습. (실제 응답까지는 안 보여 줌 — 응답은 사용자별로 다르니까.)
- **annotation:** 입력 prompt만 강조. 응답 영역은 흐리게.

#### Codex도 동일 패턴
- `codex-detect.png`, `codex-cli-output.png`, `codex-sample-prompt.png` 동일 구조.
- Codex CLI의 출력 형식이 다르므로 별도 캡처 필요.

#### 짧은 비디오?
- **`claude-code-1click.webm`** — 5초 loop, 사용자가 [Connect] 버튼 누르면 spinner → ✓ 전환. **이건 in-app 라이브 애니메이션**으로 처리해도 됨 (실제 동작이라 비디오 불필요). 외부 캡처는 필요 X.

---

### ChatGPT (가장 복잡 — Phase 3, 비디오 가장 많이 필요)

연결 경로: tunnel 설치 → ngrok 토큰 등록 → tunnel 시작 → ChatGPT에 URL 붙이기 → authorize.

각 step마다 외부 앱 / 터미널이 등장. 사용자가 가장 많이 막히는 경로 — **시각 자료 가장 두텁게**.

#### Step 1 — Choose tunnel (개념)
- **자산 1: `tunnel-concept.svg`** — diagram. ChatGPT (web) ←→ 공개 tunnel URL ←→ Backtick (localhost). 사용자가 "왜 tunnel이 필요한가"를 30초에 이해해야 함.

#### Step 2 — Install + auth (ngrok 기준)
- **자산 2: `ngrok-brew-install.png`** — 터미널 스크린샷. `brew install ngrok` 명령어와 성공 출력.
  - annotation: "Run this in Terminal once."
- **자산 3: `ngrok-dashboard-token.png`** (annotated, 외부 사이트)
  - 내용: ngrok.com dashboard에서 authtoken을 찾는 정확한 위치 (Auth → Your Authtoken).
  - annotation: 토큰이 있는 영역을 빨간 사각형으로 강조 + "Copy this token" 한 줄.
  - **위험:** ngrok dashboard UI는 자주 바뀐다. 캡션에 캡처 일자 명시 + Phase 3 전후로 분기별 재캡처 routine 필요.

#### Step 3 — Launch tunnel
- **자산 4: `ngrok-launch.webm`** (10s loop)
  - 내용: 사용자가 [Launch tunnel] 버튼 누름 → 터미널이 뜨고 → ngrok이 URL을 표시.
  - 이건 **in-app 라이브 동작이라 비디오 불필요할 수도.** 단, 사용자에게 "Terminal이 자동으로 뜬다"는 사실을 미리 알려 주는 미리보기 용도로는 짧은 loop가 도움.
- **자산 5: `ngrok-url-anatomy.png`**
  - 내용: ngrok URL 구조 (`https://abc-123.ngrok.io`) 분해. Backtick에 표시될 형태와 일치하는지 확인용.

#### Step 4 — Connect in ChatGPT (외부 앱 — 가장 위험)
이 단계가 ChatGPT 경로의 핵심 마찰. 사용자가 **ChatGPT 웹의 정확한 메뉴를 찾아야** 한다.

- **자산 6: `chatgpt-settings-apps-1.png`** (annotated)
  - 내용: ChatGPT 웹의 좌하단 프로필 → Settings 클릭 위치.
  - annotation: 클릭 지점 강조.
- **자산 7: `chatgpt-settings-apps-2.png`** (annotated)
  - 내용: Settings 모달의 "Apps" 탭 (또는 Connectors / Beta features — ChatGPT가 이 라벨을 자주 바꿈).
  - annotation: 탭 위치 강조.
- **자산 8: `chatgpt-settings-apps-3.png`** (annotated)
  - 내용: "Add app" / "Connect MCP server" 버튼 + URL 입력 필드.
  - annotation: 입력 필드 강조 + "Paste your Backtick MCP URL here" 한 줄.
- **자산 9: `chatgpt-authorize.png`** (annotated)
  - 내용: ChatGPT가 OAuth authorize 화면을 띄움 (Backtick이 OAuth provider라면).
  - annotation: "Click Allow" 강조.

**짧은 비디오 1개 — `chatgpt-add-mcp.webm`** (~15s, 자막 포함)
- Settings → Apps → Add → URL paste → Authorize까지 한 번에 흐름.
- 자막은 5단계 (Click Settings, Open Apps, Click Add, Paste URL, Authorize) 짧게.
- **이게 Phase 3에서 가장 ROI 높은 자산.** 9개 스크린샷보다 한 비디오가 직관적일 수 있음. 단 비디오만으로는 사용자가 자기 화면에서 일시정지하고 따라하기 어려우니, 비디오 + 분해 스크린샷 둘 다 두는 게 안전.

#### 검증 단계
- **자산 10: `chatgpt-mcp-active.png`**
  - 내용: ChatGPT Settings의 Apps 목록에서 Backtick이 "Connected" 상태로 보이는 화면.
  - 검증 timeout 시 사용자가 자기 눈으로 확인하는 fallback.

---

## Lane 2 (Capture & Stack)도 시각 자료 필요한가?

대체로 **불필요.** Lane 2는 Backtick의 자체 UI (Capture 패널, Stack 패널)만 다루고, onboarding이 그 패널 위에 라이브 overlay로 가르치므로 외부 스크린샷 0개.

단 하나 예외:

- **자산 — `keyboard-shortcut-keycap.svg`** — `⌘+`` ` ``과 `⌘+2` 키캡 그림. mac 표준 키캡 외형 따라 SVG로. [2B-1] Capture 단계와 [2B-3] Flow story 단계 양쪽에서 재사용.

---

## 자산 디렉토리 구조 (제안)

```
docs/assets/
  onboarding/
    common/
      keyboard-shortcut-cmd-backtick.svg
      keyboard-shortcut-cmd-2.svg
      tunnel-concept.svg
    claude-desktop/
      detect.png
      config-diff-template.png   (placeholder, 라이브 렌더 reference)
      restart.png
      tools-list.png
    claude-code/
      detect.png
      cli-output.png
      sample-prompt.png
    codex/
      detect.png
      cli-output.png
      sample-prompt.png
    chatgpt/
      settings-apps-1.png
      settings-apps-2.png
      settings-apps-3.png
      authorize.png
      mcp-active.png
      add-mcp.webm
    capture-stack/
      (자산 거의 없음 — 라이브 overlay 위주)
```

각 폴더에 `_README.md`로 캡처 시점, OS/앱 버전, 마지막 검증 일자 기록.

---

## 자산 제작 작업 순서

**Phase 1 (Lane 2 only) 제작 자산:**
- `keyboard-shortcut-cmd-backtick.svg`
- `keyboard-shortcut-cmd-2.svg`
- (그 외 모두 라이브 overlay)

→ 작업량 최소. 디자이너 0.5일 정도.

**Phase 2 (Lane 1 핵심) 제작 자산:**
- Claude Desktop: 4개 (detect, config-diff template, restart, tools-list)
- Claude Code: 3개 (detect, cli-output, sample-prompt)
- Codex: 3개 (Claude Code와 동일 구조 복제)

→ 디자이너 + 엔지니어 함께 2-3일. config-diff는 in-app 라이브 렌더라 디자이너는 placeholder만, 엔지니어가 실제 diff 컴포넌트 구현.

**Phase 3 (ChatGPT) 제작 자산:**
- tunnel concept SVG 1개
- ngrok 관련 4개
- ChatGPT 외부 화면 5개 + 비디오 1개

→ 가장 큰 작업. 디자이너 + 엔지니어 5일.

---

## 자산 유지보수 정책 (★ 잊지 말 것)

외부 앱 UI는 자주 바뀐다 — 이게 시각 자료의 가장 큰 리스크.

1. **분기별 1회 (3개월) 캡처 검증.** 모든 외부 앱 자산을 차례로 열어 보고 UI가 그대로인지 확인. 바뀐 건 재캡처.
2. **사용자 피드백 채널.** "이 화면이 내 Claude/ChatGPT 환경과 다름" 신고 버튼을 onboarding 자산 옆에 작게 노출. 신고 1건이라도 들어오면 즉시 재캡처.
3. **각 자산 옆 캡션에 캡처 일자.** 사용자가 "오래된 그림이네" 알아챌 수 있게.
4. **`scripts/check_onboarding_assets.sh` (선택):** 각 자산 폴더의 마지막 수정 일자가 90일 넘으면 CI 경고.

이 유지보수가 안 되면 Phase 3 (ChatGPT) 자산은 6개월 안에 사용자 환경과 어긋나 오히려 혼란 유발 — onboarding이 망가진 것보다 더 나쁜 신뢰 손상.

---

## 열린 질문

1. **비디오 자체 호스팅 vs 인-앱 임베드.** 앱 번들 크기 늘리지 말고 CDN으로 빼야 하는지, 아니면 핵심 비디오는 번들 안에 두고 그 외는 외부 fetch로 갈지. 첫 실행에서 네트워크 없이 onboarding을 돌릴 수 있어야 한다면 핵심 자산은 번들 필수.
2. **`config-diff` 라이브 렌더 vs 정적 placeholder.** 라이브가 정확하지만 구현 비용. Phase 2 첫 ship에서는 정적 예시 + "Your config will be similar" 카피로 갈 수도. 단 사용자별로 config가 비어 있을 수도(완전 깨끗) 있고, 다른 MCP 서버가 5개 있을 수도 있어서 정적 예시는 항상 어긋남. **라이브 렌더가 옳다.**
3. **외부 앱 UI 변경 감지 자동화.** Phase 3 ChatGPT는 특히 위험. 분기별 수동 검증 외에 자동 detect 방법은 현실적으로 없음 — 그냥 사용자 피드백이 가장 빠른 신호.
4. **자막 / 캡션 다국어 처리.** 비디오 자막은 SRT 별도 파일로 분리하면 ko/en swap 가능. 스크린샷 안 임베드된 텍스트는 swap 어려움 — 영문 캡처 1개 default가 현실적.
5. **사용자가 자기 환경 캡처를 보낼 수 있게?** "내 화면은 다른데" 사용자가 직접 자기 화면을 찍어 보내면 자산 업데이트가 빨라짐. Settings → Help → "Send a screenshot of where you got stuck" 진입점. 보안상 익명 + 사용자 확인 후 전송.

---

## 다음 단계 (제안)

1. 본 문서 합의 후 → `docs/assets/onboarding/` 디렉토리 구조 생성 (빈 placeholder만)
2. Phase 1 자산 (키캡 SVG 2개) 먼저 제작 — 디자이너 0.5일
3. Phase 2 진입 시점에 Claude Desktop / Claude Code / Codex 자산 일괄 제작
4. Phase 3 진입 전 ngrok / ChatGPT UI를 다시 한 번 확인 (UI 변경 가능성 가장 큼)
