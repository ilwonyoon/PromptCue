#!/usr/bin/env bash

set -euo pipefail

# Keep Perl-backed tools like shasum on a locale that exists both locally and in CI.
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_PATH=""
ARCHIVE_PATH=""
ARTIFACT_PATH=""
VALIDATION_REPORT=""
OUT_PATH=""
VALIDATION_MODE="unsigned-ci"
NOTARY_LOG=""
GATEKEEPER_LOG=""

print_usage() {
  cat <<'EOF'
Usage: scripts/write_release_metadata.sh [options]

Write a release record JSON for the current app/archive pair. The record is
meant to survive both CI-safe unsigned validation and the future signed lane.

Options:
  --app PATH                 Path to the exported .app bundle
  --archive PATH             Path to the .xcarchive
  --artifact PATH            Optional packaged artifact path, such as a zip
  --validation-report PATH   Optional validation report path
  --notary-log PATH          Optional notarytool JSON log path
  --gatekeeper-log PATH      Optional Gatekeeper assessment log path
  --out PATH                 Metadata JSON output path
  --validation-mode NAME     Metadata label for the current lane
                             (default: unsigned-ci)
  --help                     Show this help
EOF
}

fail() {
  echo "write_release_metadata: $*" >&2
  exit 1
}

plist_value() {
  local plist_path="$1"
  local key_path="$2"

  /usr/libexec/PlistBuddy -c "Print ${key_path}" "${plist_path}" 2>/dev/null || true
}

sha256_of() {
  local target_path="$1"

  if [[ -e "${target_path}" ]]; then
    shasum -a 256 "${target_path}" | awk '{print $1}'
  else
    printf '\n'
  fi
}

is_signed() {
  local target_path="$1"

  if codesign -dv --verbose=4 "${target_path}" >/dev/null 2>&1; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || fail "--app requires a value"
      APP_PATH="$2"
      shift 2
      ;;
    --archive)
      [[ $# -ge 2 ]] || fail "--archive requires a value"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --artifact)
      [[ $# -ge 2 ]] || fail "--artifact requires a value"
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --validation-report)
      [[ $# -ge 2 ]] || fail "--validation-report requires a value"
      VALIDATION_REPORT="$2"
      shift 2
      ;;
    --notary-log)
      [[ $# -ge 2 ]] || fail "--notary-log requires a value"
      NOTARY_LOG="$2"
      shift 2
      ;;
    --gatekeeper-log)
      [[ $# -ge 2 ]] || fail "--gatekeeper-log requires a value"
      GATEKEEPER_LOG="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || fail "--out requires a value"
      OUT_PATH="$2"
      shift 2
      ;;
    --validation-mode)
      [[ $# -ge 2 ]] || fail "--validation-mode requires a value"
      VALIDATION_MODE="$2"
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

[[ -n "${APP_PATH}" ]] || fail "--app is required"
[[ -n "${ARCHIVE_PATH}" ]] || fail "--archive is required"
[[ -n "${OUT_PATH}" ]] || fail "--out is required"

APP_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${APP_PATH}")"
ARCHIVE_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ARCHIVE_PATH}")"
OUT_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${OUT_PATH}")"
if [[ -n "${ARTIFACT_PATH}" ]]; then
  ARTIFACT_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ARTIFACT_PATH}")"
fi
if [[ -n "${VALIDATION_REPORT}" ]]; then
  VALIDATION_REPORT="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${VALIDATION_REPORT}")"
fi
if [[ -n "${NOTARY_LOG}" ]]; then
  NOTARY_LOG="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${NOTARY_LOG}")"
fi
if [[ -n "${GATEKEEPER_LOG}" ]]; then
  GATEKEEPER_LOG="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${GATEKEEPER_LOG}")"
fi

APP_INFO_PLIST="${APP_PATH}/Contents/Info.plist"
[[ -f "${APP_INFO_PLIST}" ]] || fail "app Info.plist does not exist: ${APP_INFO_PLIST}"

DISPLAY_NAME="$(plist_value "${APP_INFO_PLIST}" ':CFBundleDisplayName')"
BUNDLE_ID="$(plist_value "${APP_INFO_PLIST}" ':CFBundleIdentifier')"
MARKETING_VERSION="$(plist_value "${APP_INFO_PLIST}" ':CFBundleShortVersionString')"
BUILD_VERSION="$(plist_value "${APP_INFO_PLIST}" ':CFBundleVersion')"
EXECUTABLE_NAME="$(plist_value "${APP_INFO_PLIST}" ':CFBundleExecutable')"
APP_BINARY_PATH="${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"
HELPER_PATH="${APP_PATH}/Contents/Helpers/BacktickMCP"

APP_BINARY_SHA256="$(sha256_of "${APP_BINARY_PATH}")"
HELPER_SHA256="$(sha256_of "${HELPER_PATH}")"
ARTIFACT_SHA256=""
if [[ -n "${ARTIFACT_PATH}" ]]; then
  ARTIFACT_SHA256="$(sha256_of "${ARTIFACT_PATH}")"
fi

HELPER_FILE_OUTPUT=""
HELPER_ARCHES=""
if [[ -x "${HELPER_PATH}" ]]; then
  HELPER_FILE_OUTPUT="$(file "${HELPER_PATH}")"
  HELPER_ARCHES="$(lipo -info "${HELPER_PATH}" 2>/dev/null || true)"
fi

GIT_SHA="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || true)"
GIT_REF="$(git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
GIT_DESCRIBE="$(git -C "${PROJECT_ROOT}" describe --always --dirty --tags 2>/dev/null || true)"
if [[ -n "$(git -C "${PROJECT_ROOT}" status --short 2>/dev/null || true)" ]]; then
  GIT_DIRTY="true"
else
  GIT_DIRTY="false"
fi

APP_SIGNED="$(is_signed "${APP_PATH}")"
HELPER_SIGNED="$(is_signed "${HELPER_PATH}")"
GENERATED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "${OUT_PATH}")"

export GENERATED_AT_UTC VALIDATION_MODE GIT_SHA GIT_REF GIT_DESCRIBE GIT_DIRTY
export APP_PATH ARCHIVE_PATH ARTIFACT_PATH VALIDATION_REPORT DISPLAY_NAME BUNDLE_ID
export MARKETING_VERSION BUILD_VERSION EXECUTABLE_NAME APP_BINARY_PATH APP_BINARY_SHA256
export HELPER_PATH HELPER_FILE_OUTPUT HELPER_ARCHES HELPER_SHA256 ARTIFACT_SHA256
export APP_SIGNED HELPER_SIGNED NOTARY_LOG GATEKEEPER_LOG

python3 - "${OUT_PATH}" <<'PY'
import json
import os
import sys

def maybe(value):
    if value is None or value == "":
        return None
    return value

def as_bool(value):
    return value == "true"

def load_json(path):
    if not path:
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return None

notary_payload = load_json(maybe(os.environ.get("NOTARY_LOG")))

payload = {
    "generated_at_utc": os.environ["GENERATED_AT_UTC"],
    "validation_mode": os.environ["VALIDATION_MODE"],
    "git": {
        "sha": maybe(os.environ.get("GIT_SHA")),
        "ref": maybe(os.environ.get("GIT_REF")),
        "describe": maybe(os.environ.get("GIT_DESCRIBE")),
        "dirty": as_bool(os.environ.get("GIT_DIRTY")),
    },
    "app": {
        "path": os.environ["APP_PATH"],
        "display_name": maybe(os.environ.get("DISPLAY_NAME")),
        "bundle_identifier": maybe(os.environ.get("BUNDLE_ID")),
        "marketing_version": maybe(os.environ.get("MARKETING_VERSION")),
        "build_version": maybe(os.environ.get("BUILD_VERSION")),
        "executable_name": maybe(os.environ.get("EXECUTABLE_NAME")),
        "binary_path": maybe(os.environ.get("APP_BINARY_PATH")),
        "binary_sha256": maybe(os.environ.get("APP_BINARY_SHA256")),
        "signed": as_bool(os.environ.get("APP_SIGNED")),
    },
    "helper": {
        "path": maybe(os.environ.get("HELPER_PATH")),
        "file_output": maybe(os.environ.get("HELPER_FILE_OUTPUT")),
        "architectures": maybe(os.environ.get("HELPER_ARCHES")),
        "sha256": maybe(os.environ.get("HELPER_SHA256")),
        "signed": as_bool(os.environ.get("HELPER_SIGNED")),
    },
    "archive": {
        "path": os.environ["ARCHIVE_PATH"],
    },
    "artifact": {
        "path": maybe(os.environ.get("ARTIFACT_PATH")),
        "sha256": maybe(os.environ.get("ARTIFACT_SHA256")),
    },
    "validation_report_path": maybe(os.environ.get("VALIDATION_REPORT")),
    "notarization": {
        "log_path": maybe(os.environ.get("NOTARY_LOG")),
        "submission_id": maybe(notary_payload.get("id")) if isinstance(notary_payload, dict) else None,
        "status": maybe(notary_payload.get("status")) if isinstance(notary_payload, dict) else None,
    },
    "gatekeeper": {
        "log_path": maybe(os.environ.get("GATEKEEPER_LOG")),
    },
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "Wrote release metadata to ${OUT_PATH}"
