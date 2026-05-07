# Onboarding Visual Assets

이 디렉토리는 `docs/Connection-Walkthrough-Visuals-Plan.md`에 정의된 onboarding 시각 자료의 ground truth.

## 구조

| 폴더 | 용도 | 현재 상태 |
|---|---|---|
| `common/` | 키캡 / 다이어그램 등 lane 공통 | ⌘+` ⌘+2 SVG 작성됨 |
| `capture-stack/` | Lane 2 자산 (대부분 in-app live overlay라 거의 비어 있음) | 비어 있음 |
| `claude-desktop/` | Lane 1 — Claude Desktop config 편집 경로 | Phase 2에서 작성 |
| `claude-code/` | Lane 1 — Claude Code 1-click 경로 | Phase 2에서 작성 |
| `codex/` | Lane 1 — Codex CLI 1-click 경로 | Phase 2에서 작성 |
| `chatgpt/` | Lane 1 — ChatGPT tunnel 경로 (가장 위험) | Phase 3에서 작성 |

## 자산 추가 규칙

1. 각 자산 옆 캡션에 캡처 일자 명시 (예: `claude-desktop-tools-list.png — captured 2026-05-15, Claude Desktop 0.7.x`)
2. 외부 앱 UI 캡처는 분기별 1회 재검증
3. PNG @2x, SVG는 light/dark `prefers-color-scheme` media query 포함
4. 새 폴더 생성 시 이 README 업데이트

## 다음 단계

- Phase 2 진입 시점에 Claude Desktop / Claude Code / Codex 자산 일괄 제작
- Phase 3 진입 전 ngrok / ChatGPT UI 재확인 (UI 변경 가능성 가장 큼)
