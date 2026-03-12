#!/usr/bin/env bash

set -euo pipefail

APP_PATH=""
ARCHIVE_PATH=""
ARTIFACT_PATH=""
REPORT_OUT=""
EXPECTED_BUNDLE_ID="com.promptcue.promptcue"
EXPECTED_DISPLAY_NAME="Prompt Cue"
EXPECTED_HELPER_RELATIVE_PATH="Contents/Helpers/BacktickMCP"
REQUIRE_SIGNATURE=0

REPORT_LINES=()
ERRORS=()

print_usage() {
  cat <<'EOF'
Usage: scripts/validate_release_artifact.sh [options]

Validate the current archived app shape without requiring Developer ID or
notarization credentials. This is the CI-safe H1 guard rail for the Release
lane until the signed release path is wired.

Options:
  --app PATH                  Path to the exported .app bundle
  --archive PATH              Path to the .xcarchive that produced the app
  --artifact PATH             Optional packaged artifact path, such as a zip
  --report-out PATH           Write a plain-text validation report to this path
  --expected-bundle-id ID     Expected app bundle identifier
                              (default: com.promptcue.promptcue)
  --expected-display-name ID  Expected app display name (default: Prompt Cue)
  --require-signature         Fail unless the app and helper have valid signatures
  --help                      Show this help
EOF
}

fail() {
  echo "validate_release_artifact: $*" >&2
  exit 1
}

append_report() {
  REPORT_LINES+=("$1")
}

append_error() {
  ERRORS+=("$1")
}

plist_value() {
  local plist_path="$1"
  local key_path="$2"

  /usr/libexec/PlistBuddy -c "Print ${key_path}" "${plist_path}" 2>/dev/null || true
}

check_codesign() {
  local target_path="$1"
  if codesign --verify --strict --verbose=4 "${target_path}" >/dev/null 2>&1; then
    printf 'valid\n'
  elif codesign -dv --verbose=4 "${target_path}" >/dev/null 2>&1; then
    printf 'present-but-invalid\n'
  else
    printf 'missing\n'
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
    --report-out)
      [[ $# -ge 2 ]] || fail "--report-out requires a value"
      REPORT_OUT="$2"
      shift 2
      ;;
    --expected-bundle-id)
      [[ $# -ge 2 ]] || fail "--expected-bundle-id requires a value"
      EXPECTED_BUNDLE_ID="$2"
      shift 2
      ;;
    --expected-display-name)
      [[ $# -ge 2 ]] || fail "--expected-display-name requires a value"
      EXPECTED_DISPLAY_NAME="$2"
      shift 2
      ;;
    --require-signature)
      REQUIRE_SIGNATURE=1
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

[[ -n "${APP_PATH}" ]] || fail "--app is required"
[[ -n "${ARCHIVE_PATH}" ]] || fail "--archive is required"

APP_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${APP_PATH}")"
ARCHIVE_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ARCHIVE_PATH}")"
if [[ -n "${ARTIFACT_PATH}" ]]; then
  ARTIFACT_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ARTIFACT_PATH}")"
fi

APP_INFO_PLIST="${APP_PATH}/Contents/Info.plist"
ARCHIVE_INFO_PLIST="${ARCHIVE_PATH}/Info.plist"

[[ -d "${APP_PATH}" ]] || append_error "app bundle is missing: ${APP_PATH}"
[[ -f "${APP_INFO_PLIST}" ]] || append_error "app Info.plist is missing: ${APP_INFO_PLIST}"
[[ -d "${ARCHIVE_PATH}" ]] || append_error "archive is missing: ${ARCHIVE_PATH}"
[[ -f "${ARCHIVE_INFO_PLIST}" ]] || append_error "archive Info.plist is missing: ${ARCHIVE_INFO_PLIST}"

DISPLAY_NAME=""
BUNDLE_ID=""
MARKETING_VERSION=""
BUILD_VERSION=""
EXECUTABLE_NAME=""
ARCHIVE_APP_PATH=""
APP_BINARY_PATH=""
HELPER_PATH=""
HELPER_FILE_OUTPUT=""
HELPER_LIPO_OUTPUT=""
APP_SIGNATURE_STATUS="missing"
HELPER_SIGNATURE_STATUS="missing"

if [[ ${#ERRORS[@]} -eq 0 ]]; then
  DISPLAY_NAME="$(plist_value "${APP_INFO_PLIST}" ':CFBundleDisplayName')"
  BUNDLE_ID="$(plist_value "${APP_INFO_PLIST}" ':CFBundleIdentifier')"
  MARKETING_VERSION="$(plist_value "${APP_INFO_PLIST}" ':CFBundleShortVersionString')"
  BUILD_VERSION="$(plist_value "${APP_INFO_PLIST}" ':CFBundleVersion')"
  EXECUTABLE_NAME="$(plist_value "${APP_INFO_PLIST}" ':CFBundleExecutable')"
  ARCHIVE_APP_PATH="${ARCHIVE_PATH}/Products/Applications/${EXPECTED_DISPLAY_NAME}.app"
  APP_BINARY_PATH="${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"
  HELPER_PATH="${APP_PATH}/${EXPECTED_HELPER_RELATIVE_PATH}"

  [[ -n "${DISPLAY_NAME}" ]] || append_error "CFBundleDisplayName is missing from ${APP_INFO_PLIST}"
  [[ -n "${BUNDLE_ID}" ]] || append_error "CFBundleIdentifier is missing from ${APP_INFO_PLIST}"
  [[ -n "${MARKETING_VERSION}" ]] || append_error "CFBundleShortVersionString is missing from ${APP_INFO_PLIST}"
  [[ -n "${BUILD_VERSION}" ]] || append_error "CFBundleVersion is missing from ${APP_INFO_PLIST}"
  [[ -n "${EXECUTABLE_NAME}" ]] || append_error "CFBundleExecutable is missing from ${APP_INFO_PLIST}"
  [[ -d "${ARCHIVE_APP_PATH}" ]] || append_error "archive does not contain ${EXPECTED_DISPLAY_NAME}.app"
  [[ -x "${APP_BINARY_PATH}" ]] || append_error "app executable is missing or not executable: ${APP_BINARY_PATH}"
  [[ -x "${HELPER_PATH}" ]] || append_error "bundled helper is missing or not executable: ${HELPER_PATH}"

  if [[ -n "${DISPLAY_NAME}" && "${DISPLAY_NAME}" != "${EXPECTED_DISPLAY_NAME}" ]]; then
    append_error "unexpected display name: ${DISPLAY_NAME}"
  fi
  if [[ -n "${BUNDLE_ID}" && "${BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]]; then
    append_error "unexpected bundle identifier: ${BUNDLE_ID}"
  fi
  if [[ -n "${MARKETING_VERSION}" && ! "${MARKETING_VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    append_error "marketing version must be numeric dot-separated, got: ${MARKETING_VERSION}"
  fi
  if [[ -n "${BUILD_VERSION}" && ! "${BUILD_VERSION}" =~ ^[0-9]+$ ]]; then
    append_error "build version must be numeric, got: ${BUILD_VERSION}"
  fi
  if [[ -n "${ARTIFACT_PATH}" && ! -s "${ARTIFACT_PATH}" ]]; then
    append_error "artifact path is missing or empty: ${ARTIFACT_PATH}"
  fi

  if [[ -x "${HELPER_PATH}" ]]; then
    HELPER_FILE_OUTPUT="$(file "${HELPER_PATH}")"
    HELPER_LIPO_OUTPUT="$(lipo -info "${HELPER_PATH}" 2>&1 || true)"
  fi

  APP_SIGNATURE_STATUS="$(check_codesign "${APP_PATH}")"
  if [[ -x "${HELPER_PATH}" ]]; then
    HELPER_SIGNATURE_STATUS="$(check_codesign "${HELPER_PATH}")"
  fi

  if [[ "${REQUIRE_SIGNATURE}" -eq 1 ]]; then
    [[ "${APP_SIGNATURE_STATUS}" == "valid" ]] || append_error "app signature is not valid"
    [[ "${HELPER_SIGNATURE_STATUS}" == "valid" ]] || append_error "helper signature is not valid"
  fi
fi

append_report "Release artifact validation"
append_report "App path: ${APP_PATH}"
append_report "Archive path: ${ARCHIVE_PATH}"
if [[ -n "${ARTIFACT_PATH}" ]]; then
  append_report "Artifact path: ${ARTIFACT_PATH}"
fi
append_report "Display name: ${DISPLAY_NAME:-<missing>}"
append_report "Bundle ID: ${BUNDLE_ID:-<missing>}"
append_report "Marketing version: ${MARKETING_VERSION:-<missing>}"
append_report "Build version: ${BUILD_VERSION:-<missing>}"
append_report "Executable: ${EXECUTABLE_NAME:-<missing>}"
append_report "Helper path: ${HELPER_PATH:-<missing>}"
append_report "App signature status: ${APP_SIGNATURE_STATUS}"
append_report "Helper signature status: ${HELPER_SIGNATURE_STATUS}"
if [[ -n "${HELPER_FILE_OUTPUT}" ]]; then
  append_report "Helper file: ${HELPER_FILE_OUTPUT}"
fi
if [[ -n "${HELPER_LIPO_OUTPUT}" ]]; then
  append_report "Helper lipo: ${HELPER_LIPO_OUTPUT}"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  append_report ""
  append_report "Errors:"
  for error in "${ERRORS[@]}"; do
    append_report "- ${error}"
  done
fi

if [[ -n "${REPORT_OUT}" ]]; then
  mkdir -p "$(dirname "${REPORT_OUT}")"
  printf '%s\n' "${REPORT_LINES[@]}" > "${REPORT_OUT}"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  printf '%s\n' "${REPORT_LINES[@]}" >&2
  exit 1
fi

printf '%s\n' "${REPORT_LINES[@]}"
