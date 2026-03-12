#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_ROOT}/PromptCue.xcodeproj"
SCHEME="PromptCue"
CONFIGURATION="Release"
OUTPUT_ROOT="${PROJECT_ROOT}/build/release-validation"
DERIVED_DATA_PATH=""
SOURCE_PACKAGES_DIR=""
ARCHIVE_PATH=""
EXPORTED_APP_PATH=""
ARTIFACT_PATH=""
ARCHIVE_LOG_PATH=""
VALIDATION_REPORT_PATH=""
METADATA_PATH=""
SKIP_XCODEGEN=0

print_usage() {
  cat <<'EOF'
Usage: scripts/archive_release_validation.sh [options]

Archive the current Release configuration without signing credentials so CI can
validate the release lane shape, bundled helper packaging, and release metadata.

Options:
  --output-root PATH       Root folder for archive, exported app, logs, and metadata
                           (default: build/release-validation)
  --project PATH           Xcode project path
                           (default: PromptCue.xcodeproj in repo root)
  --scheme NAME            Xcode scheme to archive (default: PromptCue)
  --configuration NAME     Xcode configuration to archive (default: Release)
  --skip-xcodegen          Reuse the existing project instead of regenerating it
  --help                   Show this help
EOF
}

fail() {
  echo "archive_release_validation: $*" >&2
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

cd "${PROJECT_ROOT}"

PROJECT_PATH="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${PROJECT_PATH}")"
OUTPUT_ROOT="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${OUTPUT_ROOT}")"

[[ -e "${PROJECT_PATH}" ]] || fail "project path does not exist: ${PROJECT_PATH}"

DERIVED_DATA_PATH="${OUTPUT_ROOT}/DerivedData"
SOURCE_PACKAGES_DIR="${OUTPUT_ROOT}/SourcePackages"
ARCHIVE_PATH="${OUTPUT_ROOT}/PromptCue.xcarchive"
EXPORTED_APP_PATH="${OUTPUT_ROOT}/Prompt Cue.app"
ARTIFACT_PATH="${OUTPUT_ROOT}/Prompt Cue.app.zip"
ARCHIVE_LOG_PATH="${OUTPUT_ROOT}/archive.log"
VALIDATION_REPORT_PATH="${OUTPUT_ROOT}/release-validation.txt"
METADATA_PATH="${OUTPUT_ROOT}/release-metadata.json"

mkdir -p "${OUTPUT_ROOT}"
rm -rf \
  "${DERIVED_DATA_PATH}" \
  "${SOURCE_PACKAGES_DIR}" \
  "${ARCHIVE_PATH}" \
  "${EXPORTED_APP_PATH}" \
  "${ARTIFACT_PATH}" \
  "${ARCHIVE_LOG_PATH}" \
  "${VALIDATION_REPORT_PATH}" \
  "${METADATA_PATH}"

if [[ "${SKIP_XCODEGEN}" -eq 0 ]]; then
  command -v xcodegen >/dev/null 2>&1 || fail "xcodegen is not installed"
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
  CODE_SIGNING_ALLOWED=NO
  archive
)

printf '+'
for arg in "${XCODEBUILD_CMD[@]}"; do
  printf ' %q' "${arg}"
done
printf '\n'
"${XCODEBUILD_CMD[@]}" 2>&1 | tee "${ARCHIVE_LOG_PATH}"

ARCHIVED_APP_PATH="${ARCHIVE_PATH}/Products/Applications/Prompt Cue.app"
[[ -d "${ARCHIVED_APP_PATH}" ]] || fail "archived app is missing: ${ARCHIVED_APP_PATH}"

run ditto "${ARCHIVED_APP_PATH}" "${EXPORTED_APP_PATH}"
run ditto -c -k --sequesterRsrc --keepParent "${EXPORTED_APP_PATH}" "${ARTIFACT_PATH}"
run "${PROJECT_ROOT}/scripts/validate_release_artifact.sh" \
  --archive "${ARCHIVE_PATH}" \
  --app "${EXPORTED_APP_PATH}" \
  --artifact "${ARTIFACT_PATH}" \
  --report-out "${VALIDATION_REPORT_PATH}"
run "${PROJECT_ROOT}/scripts/write_release_metadata.sh" \
  --archive "${ARCHIVE_PATH}" \
  --app "${EXPORTED_APP_PATH}" \
  --artifact "${ARTIFACT_PATH}" \
  --validation-report "${VALIDATION_REPORT_PATH}" \
  --out "${METADATA_PATH}"

echo "Archive:    ${ARCHIVE_PATH}"
echo "App:        ${EXPORTED_APP_PATH}"
echo "Artifact:   ${ARTIFACT_PATH}"
echo "Report:     ${VALIDATION_REPORT_PATH}"
echo "Metadata:   ${METADATA_PATH}"
