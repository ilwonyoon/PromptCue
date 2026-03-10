#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

INCLUDE_PERF=1
APP_PATH=""
PROFILE="full"

FUNCTIONAL_TARGETS=(
  "-only-testing:PromptCueTests/AppModelRecentScreenshotTests"
  "-only-testing:PromptCueTests/RecentScreenshotCoordinatorTests"
  "-only-testing:PromptCueTests/RecentScreenshotCoordinatorClipboardTests"
  "-only-testing:PromptCueTests/StorageServicesTests"
  "-only-testing:PromptCueTests/CloudSyncMergeTests"
  "-only-testing:PromptCueTests/CaptureComposerLayoutTests"
  "-only-testing:PromptCueTests/CueTextEditorMetricsTests"
  "-only-testing:PromptCueTests/CaptureEditorLayoutCalculatorTests"
  "-only-testing:PromptCueTests/CaptureCardRenderingTests"
)

print_usage() {
  cat <<'EOF'
Usage: scripts/verify_main_merge_safety.sh [options]

Run the merge gate for the performance integration branch with a functional-first
order: regressions first, then build, then performance checks.

Options:
  --app PATH      Path to "Prompt Cue.app" for the live stack-open trace
  --profile NAME  Verification profile: full or safe-main (default: full)
  --skip-perf     Skip perf benchmarks and the live stack-open trace
  --help          Show this help
EOF
}

run() {
  echo "+ $*"
  "$@"
}

resolve_current_app_path() {
  local settings
  settings="$(xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug -showBuildSettings)"
  local target_build_dir
  local full_product_name
  target_build_dir="$(printf '%s\n' "${settings}" | awk -F ' = ' '/TARGET_BUILD_DIR/ { print $2; exit }')"
  full_product_name="$(printf '%s\n' "${settings}" | awk -F ' = ' '/FULL_PRODUCT_NAME/ { print $2; exit }')"

  if [[ -z "${target_build_dir}" || -z "${full_product_name}" ]]; then
    echo "Could not resolve the current Debug app path from build settings" >&2
    exit 1
  fi

  printf '%s/%s\n' "${target_build_dir}" "${full_product_name}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || { echo "--app requires a value" >&2; exit 1; }
      APP_PATH="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "--profile requires a value" >&2; exit 1; }
      PROFILE="$2"
      shift 2
      ;;
    --skip-perf)
      INCLUDE_PERF=0
      shift
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

case "${PROFILE}" in
  full|safe-main)
    ;;
  *)
    echo "unknown profile: ${PROFILE}" >&2
    print_usage >&2
    exit 1
    ;;
esac

run xcodegen generate
run swift test
run xcodebuild \
  -project PromptCue.xcodeproj \
  -scheme PromptCue \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test \
  "${FUNCTIONAL_TARGETS[@]}"
run xcodebuild \
  -project PromptCue.xcodeproj \
  -scheme PromptCue \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ "${INCLUDE_PERF}" -eq 1 ]]; then
  PERF_FLAGS="OTHER_SWIFT_FLAGS=\$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS"

  run xcodebuild \
    -project PromptCue.xcodeproj \
    -scheme PromptCue \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    "${PERF_FLAGS}" \
    test \
    -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyBenchmark

  run xcodebuild \
    -project PromptCue.xcodeproj \
    -scheme PromptCue \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    "${PERF_FLAGS}" \
    test \
    -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyDispatchBenchmark

  run xcodebuild \
    -project PromptCue.xcodeproj \
    -scheme PromptCue \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    "${PERF_FLAGS}" \
    test \
    -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testQueuedRemoteApplyCompletionBenchmark

  if [[ "${PROFILE}" == "full" ]]; then
    run xcodebuild \
      -project PromptCue.xcodeproj \
      -scheme PromptCue \
      -configuration Debug \
      CODE_SIGNING_ALLOWED=NO \
      "${PERF_FLAGS}" \
      test \
      -only-testing:PromptCueTests/StackPanelVisualPerformanceTests/testStackVisualRenderBenchmark
  else
    echo "+ skipping StackPanelVisualPerformanceTests for safe-main profile"
  fi

  if [[ -z "${APP_PATH}" ]]; then
    APP_PATH="$(resolve_current_app_path)"
  fi

  run "${PROJECT_ROOT}/scripts/record_stack_open_trace.sh" --app "${APP_PATH}"
fi

run git diff --check
