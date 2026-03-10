#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

TARGET_WORKTREE="../PromptCue-main-safe"
TARGET_BRANCH="feat/performance-main-safe"
BASE_REF="main"
VERIFY=0
APP_PATH=""

SAFE_FILES=(
  ".gitignore"
  "PromptCue/App/AppCoordinator.swift"
  "PromptCue/App/AppModel.swift"
  "PromptCue/App/PerformanceTrace.swift"
  "PromptCue/Services/CardStore.swift"
  "PromptCue/Services/CloudSyncControlling.swift"
  "PromptCue/Services/CloudSyncEngine.swift"
  "PromptCue/Services/RecentScreenshotCoordinator.swift"
  "PromptCue/Services/RecentScreenshotLocator.swift"
  "PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift"
  "PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift"
  "PromptCue/UI/WindowControllers/CapturePanelController.swift"
  "PromptCue/UI/WindowControllers/StackPanelController.swift"
  "PromptCueTests/AppStartupPerformanceTests.swift"
  "PromptCueTests/CapturePanelResizePerformanceTests.swift"
  "PromptCueTests/CapturePreviewImagePerformanceTests.swift"
  "PromptCueTests/CardStorePerformanceTests.swift"
  "PromptCueTests/CloudSyncApplyPerformanceTests.swift"
  "PromptCueTests/CloudSyncMergeTests.swift"
  "PromptCueTests/CloudSyncPushPerformanceTests.swift"
  "PromptCueTests/RecentScreenshotCoordinatorClipboardTests.swift"
  "PromptCueTests/RecentScreenshotCoordinatorPerformanceTests.swift"
  "PromptCueTests/RecentScreenshotCoordinatorTests.swift"
  "PromptCueTests/StorageServicesTests.swift"
  "docs/Implementation-Plan.md"
  "docs/Master-Board.md"
  "docs/Performance-Remediation-Plan.md"
  "scripts/record_stack_open_trace.sh"
  "scripts/sync_safe_main_merge_worktree.sh"
  "scripts/verify_main_merge_safety.sh"
)

DEFERRED_FILES=(
  "PromptCue/UI/Views/CaptureCardView.swift"
  "PromptCue/UI/Views/CardStackView.swift"
  "PromptCue/UI/Components/StackCardOverflowPolicy.swift"
  "PromptCueTests/CaptureCardRenderingTests.swift"
  "PromptCueTests/StackCardOverflowPerformanceTests.swift"
  "PromptCueTests/StackCardOverflowPolicyTests.swift"
  "PromptCue/UI/Components/StackNotificationCardChromeRecipe.swift"
  "PromptCue/UI/Components/StackNotificationCardSurface.swift"
  "PromptCue/UI/Components/StackPanelBackdrop.swift"
  "PromptCue/UI/Components/StackPanelBackdropRecipe.swift"
  "PromptCue/UI/DesignSystem/PrimitiveTokens.swift"
  "PromptCue/UI/DesignSystem/SemanticTokens.swift"
  "PromptCue/UI/DesignSystem/PanelBackdropFamily.swift"
  "PromptCue/UI/Preview/DesignSystemPreviewView.swift"
  "PromptCueTests/StackPanelVisualPerformanceTests.swift"
  "docs/Design-Polish-Execution-Plan.md"
  "docs/Design-System.md"
  "docs/Execution-PRD.md"
  "docs/Quality-Remediation-Plan.md"
)

print_usage() {
  cat <<'EOF'
Usage: scripts/sync_safe_main_merge_worktree.sh [options]

Create or refresh a clean worktree that contains only the merge-safe
performance/instrumentation changes that preserve current main functionality and
UI style.

Options:
  --target PATH    Target worktree path (default: ../PromptCue-main-safe)
  --branch NAME    Target branch name (default: feat/performance-main-safe)
  --base REF       Base ref for the worktree (default: main)
  --verify         Run scripts/verify_main_merge_safety.sh --profile safe-main
  --app PATH       Optional app path to pass through to verification
  --help           Show this help
EOF
}

run() {
  echo "+ $*"
  "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a value" >&2; exit 1; }
      TARGET_WORKTREE="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "--branch requires a value" >&2; exit 1; }
      TARGET_BRANCH="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || { echo "--base requires a value" >&2; exit 1; }
      BASE_REF="$2"
      shift 2
      ;;
    --verify)
      VERIFY=1
      shift
      ;;
    --app)
      [[ $# -ge 2 ]] || { echo "--app requires a value" >&2; exit 1; }
      APP_PATH="$2"
      shift 2
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

TARGET_WORKTREE_ABS="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${TARGET_WORKTREE}")"

if [[ ! -d "${TARGET_WORKTREE_ABS}" ]]; then
  run git worktree add "${TARGET_WORKTREE_ABS}" -b "${TARGET_BRANCH}" "${BASE_REF}"
fi

for file in "${SAFE_FILES[@]}"; do
  if [[ ! -e "${PROJECT_ROOT}/${file}" ]]; then
    echo "missing safe source file: ${file}" >&2
    exit 1
  fi

  mkdir -p "${TARGET_WORKTREE_ABS}/$(dirname "${file}")"
  run rsync -a "${PROJECT_ROOT}/${file}" "${TARGET_WORKTREE_ABS}/${file}"
done

(
  cd "${TARGET_WORKTREE_ABS}"
  run xcodegen generate
)

echo
echo "Prepared safe-main worktree:"
echo "  ${TARGET_WORKTREE_ABS}"
echo
echo "Deferred to preserve current main UI style and interaction behavior:"
for file in "${DEFERRED_FILES[@]}"; do
  echo "  - ${file}"
done

echo
(
  cd "${TARGET_WORKTREE_ABS}"
  run git status --short --branch
)

if [[ "${VERIFY}" -eq 1 ]]; then
  VERIFY_CMD=("${TARGET_WORKTREE_ABS}/scripts/verify_main_merge_safety.sh" "--profile" "safe-main")
  if [[ -n "${APP_PATH}" ]]; then
    VERIFY_CMD+=("--app" "${APP_PATH}")
  fi
  run "${VERIFY_CMD[@]}"
fi
