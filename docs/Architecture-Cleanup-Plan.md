# Architecture Cleanup Plan

## 목적

이 문서는 `architecture-cleanup` 브랜치에서 대형 파일 분해를 안전하게 실행하기 위한
실행 런북이다.

이 문서의 목표는 세 가지다.

1. `main`과 충돌 가능성이 낮은 파일부터 분해한다.
2. API 변경 없이 파일만 분리한다.
3. 멀티에이전트가 바로 착수할 수 있도록 트랙, 소유권, 커밋, 검증 기준을 고정한다.

이 문서는 제품 우선순위 문서가 아니라 구조 정리 실행 문서다.

## 현재 전제

- `main`에서는 Settings 디자인 시스템 리팩토링 머지가 진행 중이다.
- 이 브랜치는 `main` 안정화 후 리베이스해서 머지한다.
- `PromptCue/UI/Settings/PromptCueSettingsView.swift`는 지금 건드리지 않는다.
- `PromptCue/App/AppModel.swift`, `PromptCue/Services/RecentSuggestedAppTargetTracker.swift`,
  `PromptCue/Services/RecentScreenshotCoordinator.swift`는 현재 브랜치에서 안전하게 분해 가능한
  우선 대상이다.

## 실행 원칙

- `main`에서 활발히 수정 중인 파일은 건드리지 않는다.
- `extension` 추출 패턴으로 API 변경 없이 파일만 분리한다.
- 저장 프로퍼티와 `@Published` 선언은 원본 타입 파일에 남긴다.
- 메서드와 계산 프로퍼티만 도메인별 파일로 이동한다.
- 각 추출 슬라이스는 독립 커밋으로 남긴다.
- 각 커밋 전후로 최소 검증을 수행한다.
- 멀티에이전트는 같은 파일을 동시에 수정하지 않는다.

## 현재 대형 파일 스냅샷

| 파일 | 줄 수 | 판정 | main 수정 중 | 실행 우선순위 |
| --- | ---: | --- | --- | --- |
| `PromptCue/UI/Settings/PromptCueSettingsView.swift` | 1702 | SPLIT | YES | Phase 3, 리베이스 후 |
| `PromptCue/App/AppModel.swift` | 1340 | SPLIT | no | Phase 1 |
| `PromptCue/UI/Settings/MCPConnectorSettingsModel.swift` | 1251 | OK | YES | 건드리지 않음 |
| `PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift` | 977 | OK | no | Phase 4 |
| `PromptCue/UI/WindowControllers/CapturePanelController.swift` | 852 | OK | no | Phase 4 |
| `PromptCue/Services/RecentScreenshotCoordinator.swift` | 750 | SPLIT | no | Phase 2B |
| `PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift` | 675 | 경미 | no | Phase 4 |
| `PromptCue/Services/RecentSuggestedAppTargetTracker.swift` | 648 | SPLIT | no | Phase 2A |

## 실행 모드

### Master

Master는 아래를 소유한다.

- 이 문서와 상태 업데이트
- `PromptCue/App/AppModel.swift`
- Phase 1 전체 통합
- 검증 실행
- git 커밋

### Track A: AppModel 분해

소유 파일:

- `PromptCue/App/AppModel.swift`
- `PromptCue/App/AppModel+CaptureSession.swift`
- `PromptCue/App/AppModel+SuggestedTarget.swift`
- `PromptCue/App/AppModel+CloudSync.swift`
- `PromptCue/App/AppModel+Screenshot.swift`

규칙:

- `AppModel.swift`는 Master만 수정한다.
- Worker는 읽기 전용 분석만 허용한다.

### Track B: SuggestedTarget 서비스 분해

소유 파일:

- `PromptCue/Services/RecentSuggestedAppTargetTracker.swift`
- `PromptCue/Services/TerminalWindowSnapshotProvider.swift`
- `PromptCue/Services/IDEWindowSnapshotProvider.swift`
- `PromptCue/Services/TargetDetailResolver.swift`

규칙:

- 이 트랙은 `AppModel`과 독립적으로 진행 가능하다.
- `SuggestedTargetProviding` 프로토콜의 public surface는 바꾸지 않는다.

### Track C: Screenshot 서비스 분해

소유 파일:

- `PromptCue/Services/RecentScreenshotCoordinator.swift`
- `PromptCue/Services/ScreenshotScanResultHandler.swift`

규칙:

- `RecentScreenshotCoordinating` surface는 바꾸지 않는다.
- 타이머, 세션, 캐시 필드의 저장 위치는 `RecentScreenshotCoordinator.swift`에 남긴다.

### Track D: Settings 분해

소유 파일:

- `PromptCue/UI/Settings/PromptCueSettingsView.swift`
- `docs/Settings-View-Decomposition-Plan.md`

규칙:

- `main` 리베이스 전 착수 금지.

## 브랜치와 워크트리 규칙

권장 패턴:

- 통합 브랜치: `feat/architecture-cleanup-integration`
- Track B 브랜치: `feat/architecture-cleanup-target-tracker`
- Track C 브랜치: `feat/architecture-cleanup-screenshot-coordinator`

권장 워크트리:

- `../PromptCue-architecture-cleanup-target-tracker`
- `../PromptCue-architecture-cleanup-screenshot-coordinator`

현재 세션에서는 Master가 현재 워크트리에서 Phase 1을 진행하고,
Track B/C는 병렬 분석 또는 분리 구현 후 순차 통합한다.

## Phase 0: 실행 준비

목표:

- 파일 경계와 커밋 단위를 먼저 고정한다.

완료 기준:

- 각 트랙의 소유 파일이 겹치지 않는다.
- 커밋 메시지와 검증 명령이 확정된다.

실행:

1. 이 문서를 최신 상태로 유지한다.
2. `git status --short`가 깨끗한지 확인한다.
3. 새 파일이 `project.yml`의 `PromptCue` 소스 경로 아래에 자동 포함되는지 확인한다.
4. Phase 1부터 커밋 단위로 실행한다.

## Phase 1: AppModel 분해

목표:

- `AppModel.swift`에서 저장 프로퍼티와 핵심 CRUD만 남기고, 도메인 메서드를 extension 파일로 분리한다.

### 추출 파일과 정확한 메서드 범위

#### 1A. `AppModel+CaptureSession.swift`

이동 대상:

- `beginCaptureSession()`
- `prepareCapturePresentation()`
- `endCaptureSession()`
- `beginCaptureSubmission(onSuccess:)`
- `submitCapture()`
- `clearDraft()`
- `updateDraftEditorMetrics(_:)`
- `prepareDraftMetricsForPresentation()`
- `waitForCaptureSubmissionToSettle(timeout:)`

이 파일에서 함께 접근하는 상태:

- `draftText`
- `draftEditorMetrics`
- `draftSuggestedTargetOverride`
- `isShowingCaptureSuggestedTargetChooser`
- `selectedCaptureSuggestedTargetIndex`
- `isSubmittingCapture`
- `captureSubmissionTask`
- `recentScreenshotCoordinator`
- `attachmentStore`
- `cardStore`
- `cloudSyncEngine`

주의:

- `currentRecentScreenshotAttachment`는 `Screenshot` 도메인에 두되, capture extension에서 사용한다.
- 제출 로직의 동작 변경은 금지한다.

커밋:

- `refactor: extract app model capture session methods`

#### 1B. `AppModel+SuggestedTarget.swift`

이동 대상:

- `refreshAvailableSuggestedTargets()`
- `chooseDraftSuggestedTarget(_:)`
- `clearDraftSuggestedTargetOverride()`
- `toggleCaptureSuggestedTargetChooser()`
- `hideCaptureSuggestedTargetChooser()`
- `moveCaptureSuggestedTargetSelection(by:)`
- `highlightCaptureSuggestedTarget(_:)`
- `highlightAutomaticCaptureSuggestedTarget()`
- `completeCaptureSuggestedTargetSelection()`
- `cancelCaptureSuggestedTargetSelection()`
- `syncAvailableSuggestedTargets()`
- `captureSuggestedTargetChoices`
- `syncCaptureSuggestedTargetSelection()`

주의:

- chooser 인덱스 계산 로직은 유지한다.
- `start()`와 `stop()`은 여러 도메인을 묶고 있으므로 원본 파일에 남긴다.

커밋:

- `refactor: extract app model suggested target methods`

#### 1C. `AppModel+Screenshot.swift`

이동 대상:

- `refreshPendingScreenshot()`
- `dismissPendingScreenshot()`
- `syncRecentScreenshotState()`
- `applyRecentScreenshotState(_:)`
- `currentRecentScreenshotAttachment`

주의:

- 스크린샷 표시 여부 계산 프로퍼티는 public surface라서 필요 시 후속 커밋으로 이동한다.
- 이 커밋에서는 세션/프리뷰 상태 전환 메서드만 옮긴다.

커밋:

- `refactor: extract app model screenshot methods`

#### 1D. `AppModel+CloudSync.swift`

이동 대상:

- `pushCopiedCardsToCloudSync(_:forcePerCardDispatch:)`
- `startCloudSync(initialFetchMode:)`
- `handleCloudRemoteNotification()`
- `setSyncEnabled(_:)`
- `CloudSyncDelegate` extension 전체
- `mergeRemoteChange(local:remote:assetURL:)`
- `importRemoteScreenshotPathIfNeeded(for:assetURL:shouldImport:)`
- `shouldImportRemoteScreenshot(local:remote:winner:assetURL:)`
- `mergeWinner(local:remote:)`
- `mergeCard(local:remote:winner:importedRemoteScreenshotPath:)`
- `card(_:replacingScreenshotPath:)`
- `processPendingRemoteChanges()`
- `buildRemoteApplyPlan(_:)`
- `applyRemoteApplyPlan(_:)`
- `importRemoteScreenshotPath(for:assetURL:)`

주의:

- `CloudSyncInitialFetchMode`, `RemoteApplyPlan`, `RemoteMergeWinner` 타입은 공유 계약이므로
  `AppModel.swift` 상단에 남겨도 괜찮다.
- `start()`와 `stop()`의 cloud wiring은 그대로 두고, 실제 세부 구현만 extension으로 이동한다.

커밋:

- `refactor: extract app model cloud sync methods`

### Phase 1에서 원본 `AppModel.swift`에 남는 것

- 저장 프로퍼티와 계산 프로퍼티
- 초기화 로직
- `start(startupMode:)`
- `stop()`
- `reloadCards(runNonCriticalMaintenance:)`
- 선택/복사/삭제/TTL 관련 카드 CRUD
- 정렬/첨부 정리/로그/스타트업 maintenance 유틸리티

### Phase 1 실행 순서

1. `1B SuggestedTarget`
2. `1C Screenshot`
3. `1A CaptureSession`
4. `1D CloudSync`
5. Phase 1 통합 검증

이 순서를 쓰는 이유:

- `SuggestedTarget`, `Screenshot`는 부작용 범위가 좁다.
- `CaptureSession`은 현재 입력 시스템과 접점이 많아서 앞선 분리 후 처리하는 편이 안전하다.
- `CloudSync`는 diff가 크고 delegate extension이 포함되어 마지막이 낫다.

## Phase 2A: RecentSuggestedAppTargetTracker 분해

목표:

- 앱/윈도우 스냅샷 수집과 상세 정보 해석을 façade에서 분리한다.

### 새 파일

#### `TerminalWindowSnapshotProvider.swift`

이동 대상:

- `enumerateTerminalWindowSnapshots()`
- `enumerateITermWindowSnapshots()`
- `parseTerminalWindowSnapshotOutput(_:appName:bundleIdentifier:)`

남겨둘 것:

- `runCommand(...)`
- `SuggestedTargetWindowSnapshot`
- façade의 정렬/중복 제거 로직

이유:

- `runCommand`는 resolver에서도 사용하므로 1차 추출에서는 공유 helper로 남긴다.

커밋:

- `refactor: extract terminal window snapshot provider`

#### `IDEWindowSnapshotProvider.swift`

이동 대상:

- `enumerateIDEWindowSnapshots()`
- `windowTitles(forProcessIdentifier:)`

남겨둘 것:

- `frontWindowTitle(forProcessIdentifier:)`
  : 새 provider의 API를 호출하는 얇은 façade wrapper로 축소

커밋:

- `refactor: extract ide window snapshot provider`

#### `TargetDetailResolver.swift`

이동 대상:

- `buildDetailedSuggestedTarget(...)`
- `resolveTerminalSessionContext(bundleIdentifier:)`
- `resolveCurrentWorkingDirectory(forTTY:)`
- `resolveGitContext(for:)`
- `GitContextSnapshot`
- `TerminalSessionContext`

남겨둘 것:

- `suggestedTargetMatchKey(_:)`
- `suggestedTargetSnapshotMatchKey(_:)`
- `SupportedSuggestedApp`
- `SupportedSuggestedApps`

커밋:

- `refactor: extract target detail resolver`

### Phase 2A 완료 조건

- `RecentSuggestedAppTargetTracker.swift`는 lifecycle, 최신 타겟 추적, 정렬, dedupe façade만 남는다.
- public protocol 및 main actor semantics는 유지된다.

## Phase 2B: RecentScreenshotCoordinator 분해

목표:

- scan result 적용 로직을 별도 파일로 분리하고 coordinator는 상태 보관과 timer orchestration에 집중시킨다.

### 새 파일

#### `ScreenshotScanResultHandler.swift`

허용되는 형태:

- `private extension RecentScreenshotCoordinator`
- 또는 `private struct ScreenshotScanResultHandler`

이동 대상:

- `applyScanResult(_:referenceDate:)`
- `updatePreviewIfNeeded(using:session:referenceDate:)`
- `ensureClipboardSession(for:referenceDate:)`
- `filteredCandidate(_:referenceDate:)`
- `ensureSession(for:referenceDate:)`
- `ensurePendingDetection(referenceDate:)`
- `candidateExpirationDate(_:referenceDate:)`
- `publishCurrentSessionState(referenceDate:)`

원본 파일에 남길 것:

- 저장 프로퍼티 전부
- `start()`
- `stop()`
- `prepareForCaptureSession()`
- `refreshNow()`
- `resolveCurrentCaptureAttachment(timeout:)`
- 타이머 스케줄링
- background worker orchestration
- preview cache completion 처리

주의:

- `handleCompletedScan(...)`와 `finishAsyncRefresh()`는 async orchestration 성격이 강하므로
  원본 파일에 남겨도 된다.
- 이 Phase는 로직 이동만 하고 동작 변경은 하지 않는다.

커밋:

- `refactor: extract screenshot scan result handler`

## Phase 3: Settings 분해

전제:

- `main`의 Settings 리팩토링 머지 완료 후 리베이스

실행:

1. `docs/Settings-View-Decomposition-Plan.md` Phase 1~4 적용
2. 미사용 코드 삭제
3. 탭 뷰 추출
4. 커넥터 탭과 시트 분리
5. 공통 헬퍼를 components로 정리

커밋:

- `chore: remove unused connector section views`
- `refactor: extract settings tab views`
- `refactor: extract connector settings and sheets`
- `refactor: move shared settings helpers to components`

## Phase 4: 경미한 추출

이 Phase는 기능 수정 중 해당 파일을 다시 열 때만 수행한다.

대상:

- `PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift`
  : `CapturePreviewImageCache`
- `PromptCue/UI/WindowControllers/CapturePanelController.swift`
  : SuggestedTarget panel subviews
- `PromptCue/UI/Capture/CaptureSuggestedTargetViews.swift`
  : `SuggestedTargetIconProvider`

## 검증 프로토콜

### 각 커밋 전 최소 검증

- `xcodegen generate`
- `swift test`

### 각 Phase 종료 검증

- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test`

### 불변 조건

- public API 시그니처 변경 없음
- 타입 이름과 접근 수준 유지
- 런타임 동작 변경 없음
- 저장 프로퍼티 이동 없음

## 커밋 프로토콜

- 커밋은 추출 슬라이스마다 바로 남긴다.
- 여러 추출을 한 커밋에 뭉치지 않는다.
- 검증 실패 상태로 커밋하지 않는다.

권장 커밋 순서:

1. `docs: expand architecture cleanup execution runbook`
2. `refactor: extract app model suggested target methods`
3. `refactor: extract app model screenshot methods`
4. `refactor: extract app model capture session methods`
5. `refactor: extract app model cloud sync methods`
6. `refactor: extract terminal window snapshot provider`
7. `refactor: extract ide window snapshot provider`
8. `refactor: extract target detail resolver`
9. `refactor: extract screenshot scan result handler`

## 멀티에이전트 핸드오프 카드

### Worker Track B 시작 조건

- Phase 1 문서와 소유권이 확정되었을 것
- `RecentSuggestedAppTargetTracker.swift`만 수정할 것
- `AppModel.swift`와 Settings 파일은 건드리지 않을 것

### Worker Track C 시작 조건

- Phase 1 문서와 소유권이 확정되었을 것
- `RecentScreenshotCoordinator.swift`만 수정할 것
- 상태 필드와 timer field는 원본 파일에 남길 것

### 모든 Worker 공통 규칙

- 본인 소유 파일 외 수정 금지
- public API 변경 금지
- 추출 후 자체 빌드/테스트 수행
- 마지막 메시지에 변경 파일 목록, 위험 요소, 검증 결과를 포함

## 라이브 실행 상태

- [x] 실행 런북 업데이트
- [ ] Phase 1A capture session 추출
- [ ] Phase 1B suggested target 추출
- [ ] Phase 1C screenshot 추출
- [ ] Phase 1D cloud sync 추출
- [ ] Phase 1 검증 및 커밋 완료
- [ ] Phase 2A Track B 완료
- [ ] Phase 2B Track C 완료
- [ ] `main` 리베이스 후 Phase 3 착수
