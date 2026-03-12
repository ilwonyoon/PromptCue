#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_CONFIG_PATH="${PROJECT_ROOT}/Config/Local.xcconfig"

PROJECT_PATH="${PROJECT_ROOT}/PromptCue.xcodeproj"
SCHEME="PromptCue"
CONFIGURATION="Release"
OUTPUT_ROOT="${PROJECT_ROOT}/build/signed-release"
PACKAGE_FORMAT="zip"
ARTIFACT_BASENAME=""
ARTIFACT_VOLUME_NAME=""
ALLOW_DIRTY=0
SKIP_XCODEGEN=0

SIGNING_SHA1=""
SIGNING_IDENTITY=""
TEAM_ID=""
NOTARY_PROFILE=""

DERIVED_DATA_PATH=""
SOURCE_PACKAGES_DIR=""
ARCHIVE_PATH=""
EXPORTED_APP_PATH=""
SUBMISSION_ZIP_PATH=""
FINAL_ZIP_PATH=""
FINAL_DMG_PATH=""
PRIMARY_ARTIFACT_PATH=""
ARCHIVE_LOG_PATH=""
VALIDATION_REPORT_PATH=""
METADATA_PATH=""
NOTARY_LOG_PATH=""
GATEKEEPER_LOG_PATH=""
CHECKSUM_PATH=""

print_usage() {
  cat <<'EOF'
Usage: scripts/archive_signed_release.sh [options]

Archive, notarize, staple, and package a Release candidate using Developer ID
credentials stored locally. This is the deterministic direct-download lane for
master-owned release work.

Options:
  --output-root PATH         Root folder for archive, logs, and packaged outputs
                             (default: build/signed-release)
  --project PATH             Xcode project path
                             (default: PromptCue.xcodeproj in repo root)
  --scheme NAME              Xcode scheme to archive (default: PromptCue)
  --configuration NAME       Xcode configuration to archive (default: Release)
  --package-format FORMAT    One of: zip, dmg, both (default: zip)
  --artifact-basename NAME   Override the packaged artifact base name
  --volume-name NAME         Override the DMG volume name
  --signing-sha1 SHA1        Developer ID Application certificate SHA1
  --signing-identity NAME    Developer ID Application certificate name
  --team-id TEAMID           Apple Team ID for manual signing
  --notary-profile NAME      notarytool keychain profile name
  --allow-dirty              Allow packaging from a dirty git worktree
  --skip-xcodegen            Reuse the existing project instead of regenerating it
  --help                     Show this help

Credential fallback order:
  1. explicit flags
  2. Config/Local.xcconfig values
  3. repo-defined auto-detection for Developer ID Application

Supported Config/Local.xcconfig keys:
  PROMPTCUE_RELEASE_SIGNING_SHA1
  PROMPTCUE_RELEASE_SIGNING_IDENTITY
  PROMPTCUE_RELEASE_TEAM_ID
  PROMPTCUE_RELEASE_NOTARY_PROFILE
EOF
}

fail() {
  echo "archive_signed_release: $*" >&2
  exit 1
}

run() {
  printf '+'
  for arg in "$@"; do
    printf ' %q' "${arg}"
  done
  printf '\n'
  "$@"
}

run_to_file() {
  local output_path="$1"
  shift

  printf '+' >&2
  for arg in "$@"; do
    printf ' %q' "${arg}" >&2
  done
  printf '\n' >&2
  "$@" > "${output_path}"
}

run_to_file_with_stderr() {
  local output_path="$1"
  shift

  printf '+' >&2
  for arg in "$@"; do
    printf ' %q' "${arg}" >&2
  done
  printf '\n' >&2
  "$@" > "${output_path}" 2>&1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

absolute_path() {
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

read_local_config_value() {
  local key="$1"

  [[ -f "${LOCAL_CONFIG_PATH}" ]] || return 0

  awk -F '=' -v target_key="${key}" '
    $1 ~ "^[[:space:]]*" target_key "[[:space:]]*$" {
      value=$2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "${LOCAL_CONFIG_PATH}"
}

resolve_signing_reference() {
  local auto_sha=""
  local auto_label=""

  if [[ -z "${SIGNING_SHA1}" ]]; then
    SIGNING_SHA1="$(read_local_config_value PROMPTCUE_RELEASE_SIGNING_SHA1)"
  fi
  if [[ -z "${SIGNING_IDENTITY}" ]]; then
    SIGNING_IDENTITY="$(read_local_config_value PROMPTCUE_RELEASE_SIGNING_IDENTITY)"
  fi

  if [[ -n "${SIGNING_SHA1}" ]]; then
    SIGNING_REFERENCE="${SIGNING_SHA1}"
    SIGNING_LABEL="${SIGNING_IDENTITY:-${SIGNING_SHA1}}"
    return
  fi

  if [[ -n "${SIGNING_IDENTITY}" ]]; then
    SIGNING_REFERENCE="${SIGNING_IDENTITY}"
    SIGNING_LABEL="${SIGNING_IDENTITY}"
    return
  fi

  auto_sha="$(
    security find-identity -v -p codesigning \
      | awk '/Developer ID Application:/ && $0 !~ /REVOKED/ { print $2; exit }'
  )"
  auto_label="$(
    security find-identity -v -p codesigning \
      | awk -F '"' '/Developer ID Application:/ && $0 !~ /REVOKED/ { print $2; exit }'
  )"

  [[ -n "${auto_sha}" ]] || fail "no valid Developer ID Application signing identity found; set PROMPTCUE_RELEASE_SIGNING_SHA1 or PROMPTCUE_RELEASE_SIGNING_IDENTITY in Config/Local.xcconfig"

  SIGNING_REFERENCE="${auto_sha}"
  SIGNING_LABEL="${auto_label:-${auto_sha}}"
}

resolve_release_credentials() {
  if [[ -z "${TEAM_ID}" ]]; then
    TEAM_ID="$(read_local_config_value PROMPTCUE_RELEASE_TEAM_ID)"
  fi
  if [[ -z "${NOTARY_PROFILE}" ]]; then
    NOTARY_PROFILE="$(read_local_config_value PROMPTCUE_RELEASE_NOTARY_PROFILE)"
  fi

  resolve_signing_reference

  [[ -n "${TEAM_ID}" ]] || fail "missing Apple Team ID; set PROMPTCUE_RELEASE_TEAM_ID in Config/Local.xcconfig or pass --team-id"
  [[ -n "${NOTARY_PROFILE}" ]] || fail "missing notarytool profile; set PROMPTCUE_RELEASE_NOTARY_PROFILE in Config/Local.xcconfig or pass --notary-profile"
}

ensure_clean_worktree() {
  if [[ "${ALLOW_DIRTY}" -eq 1 ]]; then
    return
  fi

  [[ -z "$(git -C "${PROJECT_ROOT}" status --short 2>/dev/null || true)" ]] \
    || fail "git worktree is dirty; commit or stash changes, or rerun with --allow-dirty"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:space:]/' '--' \
    | tr -cd '[:alnum:]._-' \
    | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

notary_status_from_log() {
  local log_path="$1"

  python3 - "${log_path}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

print(payload.get("status", ""))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-root)
      [[ $# -ge 2 ]] || fail "--output-root requires a value"
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || fail "--project requires a value"
      PROJECT_PATH="$2"
      shift 2
      ;;
    --scheme)
      [[ $# -ge 2 ]] || fail "--scheme requires a value"
      SCHEME="$2"
      shift 2
      ;;
    --configuration)
      [[ $# -ge 2 ]] || fail "--configuration requires a value"
      CONFIGURATION="$2"
      shift 2
      ;;
    --package-format)
      [[ $# -ge 2 ]] || fail "--package-format requires a value"
      PACKAGE_FORMAT="$2"
      shift 2
      ;;
    --artifact-basename)
      [[ $# -ge 2 ]] || fail "--artifact-basename requires a value"
      ARTIFACT_BASENAME="$2"
      shift 2
      ;;
    --volume-name)
      [[ $# -ge 2 ]] || fail "--volume-name requires a value"
      ARTIFACT_VOLUME_NAME="$2"
      shift 2
      ;;
    --signing-sha1)
      [[ $# -ge 2 ]] || fail "--signing-sha1 requires a value"
      SIGNING_SHA1="$2"
      shift 2
      ;;
    --signing-identity)
      [[ $# -ge 2 ]] || fail "--signing-identity requires a value"
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --team-id)
      [[ $# -ge 2 ]] || fail "--team-id requires a value"
      TEAM_ID="$2"
      shift 2
      ;;
    --notary-profile)
      [[ $# -ge 2 ]] || fail "--notary-profile requires a value"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --skip-xcodegen)
      SKIP_XCODEGEN=1
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

case "${PACKAGE_FORMAT}" in
  zip | dmg | both)
    ;;
  *)
    fail "unsupported --package-format '${PACKAGE_FORMAT}'; expected zip, dmg, or both"
    ;;
esac

require_command xcodebuild
require_command xcrun
require_command codesign
require_command ditto
require_command hdiutil
require_command shasum
require_command spctl
require_command python3

cd "${PROJECT_ROOT}"

PROJECT_PATH="$(absolute_path "${PROJECT_PATH}")"
OUTPUT_ROOT="$(absolute_path "${OUTPUT_ROOT}")"

[[ -e "${PROJECT_PATH}" ]] || fail "project path does not exist: ${PROJECT_PATH}"

ensure_clean_worktree
resolve_release_credentials

DERIVED_DATA_PATH="${OUTPUT_ROOT}/DerivedData"
SOURCE_PACKAGES_DIR="${OUTPUT_ROOT}/SourcePackages"
ARCHIVE_PATH="${OUTPUT_ROOT}/PromptCue.xcarchive"
ARCHIVE_LOG_PATH="${OUTPUT_ROOT}/archive.log"
VALIDATION_REPORT_PATH="${OUTPUT_ROOT}/release-validation.txt"
METADATA_PATH="${OUTPUT_ROOT}/release-metadata.json"
NOTARY_LOG_PATH="${OUTPUT_ROOT}/notary-log.json"
GATEKEEPER_LOG_PATH="${OUTPUT_ROOT}/gatekeeper.log"

mkdir -p "${OUTPUT_ROOT}"
rm -rf \
  "${DERIVED_DATA_PATH}" \
  "${SOURCE_PACKAGES_DIR}" \
  "${ARCHIVE_PATH}" \
  "${ARCHIVE_LOG_PATH}" \
  "${VALIDATION_REPORT_PATH}" \
  "${METADATA_PATH}" \
  "${NOTARY_LOG_PATH}" \
  "${GATEKEEPER_LOG_PATH}"

if [[ "${SKIP_XCODEGEN}" -eq 0 ]]; then
  require_command xcodegen
  run xcodegen generate
fi

XCODEBUILD_CMD=(
  xcodebuild
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -destination "generic/platform=macOS"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_DIR}"
  -archivePath "${ARCHIVE_PATH}"
  COMPILER_INDEX_STORE_ENABLE=NO
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="${SIGNING_REFERENCE}"
  DEVELOPMENT_TEAM="${TEAM_ID}"
  archive
)

printf '+'
for arg in "${XCODEBUILD_CMD[@]}"; do
  printf ' %q' "${arg}"
done
printf '\n'
"${XCODEBUILD_CMD[@]}" 2>&1 | tee "${ARCHIVE_LOG_PATH}"

ARCHIVE_APP_PATH="$(find "${ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${ARCHIVE_APP_PATH}" ]] || fail "archive does not contain an app bundle"

APP_INFO_PLIST="${ARCHIVE_APP_PATH}/Contents/Info.plist"
[[ -f "${APP_INFO_PLIST}" ]] || fail "archived app Info.plist is missing: ${APP_INFO_PLIST}"

DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${APP_INFO_PLIST}" 2>/dev/null || true)"
MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_INFO_PLIST}" 2>/dev/null || true)"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_INFO_PLIST}" 2>/dev/null || true)"
APP_BUNDLE_NAME="$(basename "${ARCHIVE_APP_PATH}")"

[[ -n "${DISPLAY_NAME}" ]] || DISPLAY_NAME="${APP_BUNDLE_NAME%.app}"
[[ -n "${MARKETING_VERSION}" ]] || fail "CFBundleShortVersionString is missing from ${APP_INFO_PLIST}"
[[ -n "${BUILD_VERSION}" ]] || fail "CFBundleVersion is missing from ${APP_INFO_PLIST}"

if [[ -z "${ARTIFACT_BASENAME}" ]]; then
  ARTIFACT_BASENAME="$(slugify "${DISPLAY_NAME}")"
fi
if [[ -z "${ARTIFACT_VOLUME_NAME}" ]]; then
  ARTIFACT_VOLUME_NAME="${DISPLAY_NAME}"
fi

EXPORTED_APP_PATH="${OUTPUT_ROOT}/${APP_BUNDLE_NAME}"
SUBMISSION_ZIP_PATH="${OUTPUT_ROOT}/notary-submit.zip"
FINAL_ZIP_PATH="${OUTPUT_ROOT}/${ARTIFACT_BASENAME}-${MARKETING_VERSION}-${BUILD_VERSION}.zip"
FINAL_DMG_PATH="${OUTPUT_ROOT}/${ARTIFACT_BASENAME}-${MARKETING_VERSION}-${BUILD_VERSION}.dmg"
CHECKSUM_PATH="${OUTPUT_ROOT}/${ARTIFACT_BASENAME}-${MARKETING_VERSION}-${BUILD_VERSION}.sha256.txt"

rm -rf "${EXPORTED_APP_PATH}" "${SUBMISSION_ZIP_PATH}" "${FINAL_ZIP_PATH}" "${FINAL_DMG_PATH}" "${CHECKSUM_PATH}"

run ditto "${ARCHIVE_APP_PATH}" "${EXPORTED_APP_PATH}"
run ditto -c -k --sequesterRsrc --keepParent "${EXPORTED_APP_PATH}" "${SUBMISSION_ZIP_PATH}"
run "${PROJECT_ROOT}/scripts/validate_release_artifact.sh" \
  --archive "${ARCHIVE_PATH}" \
  --app "${EXPORTED_APP_PATH}" \
  --artifact "${SUBMISSION_ZIP_PATH}" \
  --require-signature \
  --report-out "${VALIDATION_REPORT_PATH}"

run_to_file "${NOTARY_LOG_PATH}" xcrun notarytool submit "${SUBMISSION_ZIP_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait \
  --output-format json

NOTARY_STATUS="$(notary_status_from_log "${NOTARY_LOG_PATH}")"
[[ "${NOTARY_STATUS}" == "Accepted" ]] || fail "notary submission did not succeed; see ${NOTARY_LOG_PATH}"

run xcrun stapler staple "${EXPORTED_APP_PATH}"
run xcrun stapler validate "${EXPORTED_APP_PATH}"

run_to_file_with_stderr "${GATEKEEPER_LOG_PATH}" \
  spctl --assess --type execute --verbose=4 "${EXPORTED_APP_PATH}"

PRIMARY_ARTIFACT_PATH=""

case "${PACKAGE_FORMAT}" in
  zip)
    run ditto -c -k --sequesterRsrc --keepParent "${EXPORTED_APP_PATH}" "${FINAL_ZIP_PATH}"
    PRIMARY_ARTIFACT_PATH="${FINAL_ZIP_PATH}"
    ;;
  dmg)
    run hdiutil create \
      -quiet \
      -volname "${ARTIFACT_VOLUME_NAME}" \
      -srcfolder "${EXPORTED_APP_PATH}" \
      -format UDZO \
      -imagekey zlib-level=9 \
      "${FINAL_DMG_PATH}"
    PRIMARY_ARTIFACT_PATH="${FINAL_DMG_PATH}"
    ;;
  both)
    run ditto -c -k --sequesterRsrc --keepParent "${EXPORTED_APP_PATH}" "${FINAL_ZIP_PATH}"
    run hdiutil create \
      -quiet \
      -volname "${ARTIFACT_VOLUME_NAME}" \
      -srcfolder "${EXPORTED_APP_PATH}" \
      -format UDZO \
      -imagekey zlib-level=9 \
      "${FINAL_DMG_PATH}"
    PRIMARY_ARTIFACT_PATH="${FINAL_DMG_PATH}"
    ;;
esac

[[ -n "${PRIMARY_ARTIFACT_PATH}" ]] || fail "primary artifact path was not produced"

run_to_file "${CHECKSUM_PATH}" shasum -a 256 "${PRIMARY_ARTIFACT_PATH}"
run "${PROJECT_ROOT}/scripts/write_release_metadata.sh" \
  --archive "${ARCHIVE_PATH}" \
  --app "${EXPORTED_APP_PATH}" \
  --artifact "${PRIMARY_ARTIFACT_PATH}" \
  --validation-report "${VALIDATION_REPORT_PATH}" \
  --notary-log "${NOTARY_LOG_PATH}" \
  --gatekeeper-log "${GATEKEEPER_LOG_PATH}" \
  --validation-mode developer-id-notarized \
  --out "${METADATA_PATH}"

echo "Archive:           ${ARCHIVE_PATH}"
echo "Exported app:      ${EXPORTED_APP_PATH}"
echo "Submission zip:    ${SUBMISSION_ZIP_PATH}"
if [[ -f "${FINAL_ZIP_PATH}" ]]; then
  echo "Final zip:         ${FINAL_ZIP_PATH}"
fi
if [[ -f "${FINAL_DMG_PATH}" ]]; then
  echo "Final dmg:         ${FINAL_DMG_PATH}"
fi
echo "Primary artifact:  ${PRIMARY_ARTIFACT_PATH}"
echo "Validation report: ${VALIDATION_REPORT_PATH}"
echo "Notary log:        ${NOTARY_LOG_PATH}"
echo "Gatekeeper log:    ${GATEKEEPER_LOG_PATH}"
echo "Checksum:          ${CHECKSUM_PATH}"
echo "Metadata:          ${METADATA_PATH}"
