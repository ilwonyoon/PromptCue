#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WAIT_SECONDS="2.5"
KEEP_RUNNING=0
APP_PATH=""
OUT_DIR=""
DRAFT_FILE=""
APP_PID=""
SCENARIO="default"
EXPECTED_VISIBLE=""
EXPECTED_SCROLL=""
EXPECTATION_NOTE=""

print_usage() {
  cat <<'EOF'
Usage: scripts/qa_capture_input.sh [options]

Launch Prompt Cue with local QA env hooks, wait for the capture panel to settle,
capture a screenshot, and save stdout/stderr logs into a timestamped output folder.

Options:
  --app PATH           Path to "Prompt Cue.app"
  --out-dir PATH       Output directory for logs and screenshot
  --draft-file PATH    Text file passed via PROMPTCUE_QA_DRAFT_TEXT_FILE
  --scenario NAME      default | wrap-two-lines | bottom-breathing | large-paste
  --wait SECONDS       Wait time before screenshot capture (default: 2.5)
  --keep-running       Leave the launched app process running after capture
  --help               Show this help
EOF
}

fail() {
  echo "qa_capture_input: $*" >&2
  exit 1
}

escape_json() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

resolve_latest_app() {
  local candidates=()
  while IFS= read -r path; do
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

configure_scenario() {
  case "${SCENARIO}" in
    default)
      EXPECTED_VISIBLE=""
      EXPECTED_SCROLL=""
      EXPECTATION_NOTE="No metric assertion for default scenario."
      ;;
    wrap-two-lines)
      EXPECTED_VISIBLE="76"
      EXPECTED_SCROLL="false"
      EXPECTATION_NOTE="Expect wrapped draft to settle at the 2-line visible contract."
      ;;
    bottom-breathing)
      EXPECTED_VISIBLE="54"
      EXPECTED_SCROLL="false"
      EXPECTATION_NOTE="Expect single-line draft to preserve bottom breathing room in baseline visible height."
      ;;
    large-paste)
      EXPECTED_VISIBLE="176"
      EXPECTED_SCROLL="true"
      EXPECTATION_NOTE="Expect paste payload to grow to the visible cap and enable scrolling."
      ;;
    *)
      fail "unknown scenario: ${SCENARIO}"
      ;;
  esac
}

write_scenario_draft() {
  local path="$1"

  case "${SCENARIO}" in
    wrap-two-lines)
      printf '%s' "Prompt Cue wraps short capture notes cleanly." > "${path}"
      ;;
    bottom-breathing)
      printf '%s' "Quick cue." > "${path}"
      ;;
    large-paste)
      {
        for idx in 1 2 3 4 5 6 7; do
          if [[ "${idx}" -gt 1 ]]; then
            printf '\n'
          fi
          printf 'Paste line %s for Prompt Cue capture QA.' "${idx}"
        done
      } > "${path}"
      ;;
    default)
      cat > "${path}" <<'EOF'
Prompt Cue QA draft
Line 2 wraps the capture surface.
Line 3 verifies multiline growth.
EOF
      ;;
  esac
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
    --draft-file)
      [[ $# -ge 2 ]] || fail "--draft-file requires a value"
      DRAFT_FILE="$2"
      shift 2
      ;;
    --scenario)
      [[ $# -ge 2 ]] || fail "--scenario requires a value"
      SCENARIO="$2"
      shift 2
      ;;
    --wait)
      [[ $# -ge 2 ]] || fail "--wait requires a value"
      WAIT_SECONDS="$2"
      shift 2
      ;;
    --keep-running)
      KEEP_RUNNING=1
      shift
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

configure_scenario

if [[ -z "${APP_PATH}" ]]; then
  APP_PATH="$(resolve_latest_app)" || fail "could not find a local Debug build of Prompt Cue.app; pass --app"
fi

APP_PATH="$(cd "${APP_PATH}" && pwd)"
[[ -d "${APP_PATH}" ]] || fail "app path does not exist: ${APP_PATH}"

APP_BINARY="${APP_PATH}/Contents/MacOS/Prompt Cue"
[[ -x "${APP_BINARY}" ]] || fail "app binary is not executable: ${APP_BINARY}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')-$$"
if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="/tmp/promptcue-qa/capture-input/${TIMESTAMP}"
fi
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

if [[ -z "${DRAFT_FILE}" ]]; then
  DRAFT_FILE="${OUT_DIR}/draft.txt"
  write_scenario_draft "${DRAFT_FILE}"
fi

[[ -f "${DRAFT_FILE}" ]] || fail "draft file does not exist: ${DRAFT_FILE}"
DRAFT_FILE="$(cd "$(dirname "${DRAFT_FILE}")" && pwd)/$(basename "${DRAFT_FILE}")"

STDOUT_LOG="${OUT_DIR}/stdout.log"
STDERR_LOG="${OUT_DIR}/stderr.log"
SCREENSHOT_PATH="${OUT_DIR}/capture.png"
METADATA_PATH="${OUT_DIR}/run.json"
METRICS_JSON_PATH="${OUT_DIR}/metrics.json"

echo "Launching Prompt Cue QA harness..."

python3 - "${APP_PATH}" <<'PY'
import os
import signal
import subprocess
import sys

app_path = sys.argv[1]
pattern = f"{app_path}/Contents/MacOS/Prompt Cue"
out = subprocess.run(["pgrep", "-f", pattern], capture_output=True, text=True)
for line in out.stdout.splitlines():
    try:
        os.kill(int(line.strip()), signal.SIGTERM)
    except Exception:
        pass
PY

rm -f "${STDOUT_LOG}" "${STDERR_LOG}"

PROMPTCUE_OPEN_CAPTURE_ON_START=1 \
PROMPTCUE_QA_DRAFT_TEXT_FILE="${DRAFT_FILE}" \
PROMPTCUE_LOG_EDITOR_METRICS=1 \
"${APP_BINARY}" >"${STDOUT_LOG}" 2>"${STDERR_LOG}" &

APP_PID="$!"

sleep 0.5

cleanup() {
  if [[ ${KEEP_RUNNING} -eq 0 ]]; then
    if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" >/dev/null 2>&1; then
      kill "${APP_PID}" >/dev/null 2>&1 || true
    fi
  fi
}

trap cleanup EXIT

sleep "${WAIT_SECONDS}"

if [[ -z "${APP_PID}" ]] || ! kill -0 "${APP_PID}" >/dev/null 2>&1; then
  echo "qa_capture_input: Prompt Cue exited before screenshot capture" >&2
fi

screencapture -x "${SCREENSHOT_PATH}"
SCREENSHOT_INFO="$(sips -g pixelWidth -g pixelHeight "${SCREENSHOT_PATH}")"
METRICS_TAIL="$(grep -E 'CaptureEditor (metrics|runtime)' "${STDERR_LOG}" | tail -n 5 || true)"

python3 - "${STDERR_LOG}" "${EXPECTED_VISIBLE}" "${EXPECTED_SCROLL}" "${METRICS_JSON_PATH}" <<'PY'
import json
import math
import re
import sys

stderr_path, expected_visible, expected_scroll, out_path = sys.argv[1:5]
pattern = re.compile(r"CaptureEditor (metrics|runtime) width=(?P<width>[-0-9.]+) content=(?P<content>[-0-9.]+) visible=(?P<visible>[-0-9.]+) scroll=(?P<scroll>true|false)")
latest = None

with open(stderr_path, "r", encoding="utf-8", errors="ignore") as handle:
    for line in handle:
        match = pattern.search(line)
        if match:
            latest = {
                "layout_width": float(match.group("width")),
                "content_height": float(match.group("content")),
                "visible_height": float(match.group("visible")),
                "scroll": match.group("scroll") == "true",
                "raw": line.strip(),
            }

summary = {
    "metrics_found": latest is not None,
    "latest": latest,
    "expectation": {
        "visible_height": float(expected_visible) if expected_visible else None,
        "scroll": None if not expected_scroll else expected_scroll == "true",
    },
    "status": "not_evaluated",
    "reason": "",
}

if latest is None:
    summary["status"] = "blocked"
    summary["reason"] = "No CaptureEditor metrics/runtime log line found."
elif expected_visible:
    visible_ok = math.isclose(latest["visible_height"], float(expected_visible), abs_tol=1.5)
    scroll_ok = latest["scroll"] == (expected_scroll == "true")
    if visible_ok and scroll_ok:
        summary["status"] = "pass"
    else:
        summary["status"] = "fail"
        summary["reason"] = f"Expected visible={expected_visible}, scroll={expected_scroll}; got visible={latest['visible_height']:.1f}, scroll={str(latest['scroll']).lower()}"

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)
PY

METRICS_STATUS="$(python3 - "${METRICS_JSON_PATH}" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload["status"])
print(payload.get("reason", ""))
print(payload["latest"]["raw"] if payload.get("latest") else "")
PY
)"

METRICS_STATUS_LINE="$(printf '%s\n' "${METRICS_STATUS}" | sed -n '1p')"
METRICS_REASON_LINE="$(printf '%s\n' "${METRICS_STATUS}" | sed -n '2p')"
METRICS_LATEST_LINE="$(printf '%s\n' "${METRICS_STATUS}" | sed -n '3p')"

cat > "${METADATA_PATH}" <<EOF
{
  "app_path": "$(escape_json "${APP_PATH}")",
  "app_binary": "$(escape_json "${APP_BINARY}")",
  "pid": ${APP_PID},
  "wait_seconds": ${WAIT_SECONDS},
  "scenario": "$(escape_json "${SCENARIO}")",
  "draft_file": "$(escape_json "${DRAFT_FILE}")",
  "stdout_log": "$(escape_json "${STDOUT_LOG}")",
  "stderr_log": "$(escape_json "${STDERR_LOG}")",
  "screenshot": "$(escape_json "${SCREENSHOT_PATH}")",
  "metrics_json": "$(escape_json "${METRICS_JSON_PATH}")",
  "keep_running": ${KEEP_RUNNING}
}
EOF

echo
echo "Prompt Cue capture QA summary"
echo "app: ${APP_PATH}"
echo "pid: ${APP_PID}"
echo "scenario: ${SCENARIO}"
echo "expectation: ${EXPECTATION_NOTE}"
echo "draft_file: ${DRAFT_FILE}"
echo "stdout_log: ${STDOUT_LOG}"
echo "stderr_log: ${STDERR_LOG}"
echo "screenshot: ${SCREENSHOT_PATH}"
echo "metadata: ${METADATA_PATH}"
echo "metrics_json: ${METRICS_JSON_PATH}"
echo "screenshot_info:"
echo "${SCREENSHOT_INFO}"
if [[ -n "${METRICS_TAIL}" ]]; then
  echo "capture_metrics:"
  echo "${METRICS_TAIL}"
fi
echo "metrics_check: ${METRICS_STATUS_LINE}"
if [[ -n "${METRICS_REASON_LINE}" ]]; then
  echo "metrics_reason: ${METRICS_REASON_LINE}"
fi
if [[ -n "${METRICS_LATEST_LINE}" ]]; then
  echo "latest_metric: ${METRICS_LATEST_LINE}"
fi
if [[ "${SCENARIO}" == "large-paste" ]]; then
  echo "blocked_note: threshold verification still needs a runtime hook to apply a second payload after launch; current harness only verifies the over-cap endpoint."
fi
if [[ ${KEEP_RUNNING} -eq 1 ]]; then
  echo "app_status: running"
else
  echo "app_status: terminated after capture"
fi
