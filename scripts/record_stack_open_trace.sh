#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_PATH=""
OUT_DIR=""
TIME_LIMIT="8s"
ATTACH_RETRY_LIMIT=3
ATTACH_RETRY_DELAY_SECONDS=1

print_usage() {
  cat <<'EOF'
Usage: scripts/record_stack_open_trace.sh [options]

Record a live stack-open trace by launching Prompt Cue directly, attaching
xctrace to the exact process, auto-triggering the real toggle-stack path, and
exporting a trace plus the measured first-frame log.

Options:
  --app PATH         Path to "Prompt Cue.app"
  --out-dir PATH     Output directory for trace and logs
  --time-limit TIME  xctrace time limit (default: 8s)
  --help             Show this help
EOF
}

fail() {
  echo "record_stack_open_trace: $*" >&2
  exit 1
}

resolve_latest_app() {
  local resolved_path=""
  local settings=""
  local target_build_dir=""
  local full_product_name=""

  for configuration in DevSigned Debug; do
    if settings="$(xcodebuild \
      -project "${SCRIPT_DIR}/../PromptCue.xcodeproj" \
      -scheme PromptCue \
      -configuration "${configuration}" \
      -showBuildSettings 2>/dev/null)"; then
      target_build_dir="$(printf '%s\n' "${settings}" | awk -F ' = ' '/TARGET_BUILD_DIR/ { print $2; exit }')"
      full_product_name="$(printf '%s\n' "${settings}" | awk -F ' = ' '/FULL_PRODUCT_NAME/ { print $2; exit }')"
      resolved_path="${target_build_dir}/${full_product_name}"

      if [[ -x "${resolved_path}/Contents/MacOS/Prompt Cue" ]]; then
        printf '%s\n' "${resolved_path}"
        return 0
      fi
    fi
  done

  local candidates=()
  while IFS= read -r path; do
    [[ "${path}" == *"/Index.noindex/"* ]] && continue
    [[ -x "${path}/Contents/MacOS/Prompt Cue" ]] || continue
    candidates+=("$path")
  done < <(
    find /tmp "${HOME}/Library/Developer/Xcode/DerivedData" \
      -path '*/Build/Products/Debug/Prompt Cue.app' \
      -type d \
      -print 2>/dev/null
  )

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  python3 - "${candidates[@]}" <<'PY'
import os
import sys

paths = sys.argv[1:]
latest = max(paths, key=lambda p: os.path.getmtime(p))
print(latest)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || fail "--app requires a value"
      APP_PATH="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || fail "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --time-limit)
      [[ $# -ge 2 ]] || fail "--time-limit requires a value"
      TIME_LIMIT="$2"
      shift 2
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${APP_PATH}" ]]; then
  APP_PATH="$(resolve_latest_app)" || fail "could not find a local DevSigned or Debug build of Prompt Cue.app; pass --app"
fi

APP_PATH="$(cd "${APP_PATH}" && pwd)"
[[ -d "${APP_PATH}" ]] || fail "app path does not exist: ${APP_PATH}"

APP_BINARY="${APP_PATH}/Contents/MacOS/Prompt Cue"
[[ -x "${APP_BINARY}" ]] || fail "app binary is not executable: ${APP_BINARY}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')-$$"
if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="/tmp/promptcue-traces/stack-open/${TIMESTAMP}"
fi
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

TRACE_PATH="${OUT_DIR}/stack-open.trace"
STDOUT_LOG="${OUT_DIR}/stdout.log"
TOC_PATH="${OUT_DIR}/trace-toc.xml"

echo "Recording live stack-open trace..."
APP_PID=""

cleanup_app() {
  if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" >/dev/null 2>&1; then
    kill "${APP_PID}" >/dev/null 2>&1 || true
  fi
}

launch_target_app() {
  : >"${STDOUT_LOG}"
  PROMPTCUE_TRACE_STACK_TOGGLE_ON_START=1 \
  PROMPTCUE_TRACE_STACK_TOGGLE_DELAY_MS=1500 \
  PROMPTCUE_TRACE_AUTO_QUIT_AFTER_STACK=1 \
  PROMPTCUE_TRACE_STDOUT_METRIC=1 \
    "${APP_BINARY}" >"${STDOUT_LOG}" 2>&1 &
  APP_PID=$!
}

trap cleanup_app EXIT

XCTRACE_STATUS=0
ATTEMPT=1
while true; do
  launch_target_app
  sleep 0.5

  set +e
  xcrun xctrace record \
    --template 'Logging' \
    --instrument os_signpost \
    --instrument 'Points of Interest' \
    --time-limit "${TIME_LIMIT}" \
    --output "${TRACE_PATH}" \
    --attach "${APP_PID}"
  XCTRACE_STATUS=$?
  set -e

  if [[ ${XCTRACE_STATUS} -eq 0 || ${XCTRACE_STATUS} -eq 54 ]]; then
    break
  fi

  cleanup_app
  wait "${APP_PID}" || true

  if [[ ${XCTRACE_STATUS} -eq 21 && ${ATTEMPT} -lt ${ATTACH_RETRY_LIMIT} ]]; then
    echo "record_stack_open_trace: attach attempt ${ATTEMPT} failed; retrying..." >&2
    ATTEMPT=$((ATTEMPT + 1))
    sleep "${ATTACH_RETRY_DELAY_SECONDS}"
    continue
  fi

  fail "xctrace record failed with status ${XCTRACE_STATUS}"
done

for _ in 1 2 3 4 5; do
  if ! kill -0 "${APP_PID}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if kill -0 "${APP_PID}" >/dev/null 2>&1; then
  kill "${APP_PID}" >/dev/null 2>&1 || true
  trap - EXIT
  fail "target app did not exit after stack-open trace capture; check that the traced build includes PerformanceTrace hooks"
fi

wait "${APP_PID}" || true
trap - EXIT

xcrun xctrace export --input "${TRACE_PATH}" --toc --output "${TOC_PATH}"

METRIC_LINE="$(rg -o 'PROMPTCUE_STACK_OPEN_FIRST_FRAME_MS=[0-9.]+' "${STDOUT_LOG}" | tail -n 1 || true)"
if [[ -z "${METRIC_LINE}" ]]; then
  fail "no stack-open metric found in ${STDOUT_LOG}"
fi

echo "Trace: ${TRACE_PATH}"
echo "TOC:   ${TOC_PATH}"
echo "Metric: ${METRIC_LINE}"
