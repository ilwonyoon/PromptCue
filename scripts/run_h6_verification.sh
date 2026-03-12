#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_CONFIG_PATH="${PROJECT_ROOT}/Config/Local.xcconfig"

OUTPUT_ROOT="${PROJECT_ROOT}/build/h6-verification"
SKIP_XCODEGEN=0
ALLOW_DIRTY=0
REQUIRE_SIGNED=0

print_usage() {
  cat <<'EOF'
Usage: scripts/run_h6_verification.sh [options]

Run the current H6 verification slice for public-launch hardening. This covers:
  - package/project/app verification
  - app-target policy test compilation
  - unsigned release archive validation
  - bundled helper smoke from a temp directory
  - signed release lane attempt when local Developer ID + notary credentials exist

Options:
  --output-root PATH   Root folder for logs and generated verification artifacts
                       (default: build/h6-verification)
  --skip-xcodegen      Reuse the existing project instead of regenerating it
  --allow-dirty        Allow running from a dirty git worktree
  --require-signed     Fail if signed release credentials are unavailable
  --help               Show this help
EOF
}

fail() {
  echo "run_h6_verification: $*" >&2
  exit 1
}

run_logged() {
  local log_path="$1"
  shift

  mkdir -p "$(dirname "${log_path}")"

  printf '+'
  for arg in "$@"; do
    printf ' %q' "${arg}"
  done
  printf '\n'

  "$@" 2>&1 | tee "${log_path}"
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

has_signed_release_credentials() {
  local signing_sha=""
  local signing_identity=""
  local team_id=""
  local notary_profile=""
  local auto_signing_sha=""

  signing_sha="$(read_local_config_value PROMPTCUE_RELEASE_SIGNING_SHA1)"
  signing_identity="$(read_local_config_value PROMPTCUE_RELEASE_SIGNING_IDENTITY)"
  team_id="$(read_local_config_value PROMPTCUE_RELEASE_TEAM_ID)"
  notary_profile="$(read_local_config_value PROMPTCUE_RELEASE_NOTARY_PROFILE)"

  if [[ -z "${signing_sha}" && -z "${signing_identity}" ]]; then
    auto_signing_sha="$(
      security find-identity -v -p codesigning \
        | awk '/Developer ID Application:/ && $0 !~ /REVOKED/ { print $2; exit }'
    )"
  fi

  [[ -n "${signing_sha}" || -n "${signing_identity}" || -n "${auto_signing_sha}" ]] \
    && [[ -n "${team_id}" ]] \
    && [[ -n "${notary_profile}" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-root)
      [[ $# -ge 2 ]] || fail "--output-root requires a value"
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --skip-xcodegen)
      SKIP_XCODEGEN=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --require-signed)
      REQUIRE_SIGNED=1
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

if [[ "${ALLOW_DIRTY}" -ne 1 ]]; then
  [[ -z "$(git -C "${PROJECT_ROOT}" status --short 2>/dev/null || true)" ]] \
    || fail "git worktree is dirty; commit or stash changes, or rerun with --allow-dirty"
fi

OUTPUT_ROOT="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${OUTPUT_ROOT}")"
LOG_ROOT="${OUTPUT_ROOT}/logs"
ARCHIVE_VALIDATION_ROOT="${OUTPUT_ROOT}/release-validation"
HELPER_SMOKE_ROOT="${OUTPUT_ROOT}/helper-smoke"
HELPER_SMOKE_APP="${HELPER_SMOKE_ROOT}/Prompt Cue.app"
HELPER_SMOKE_LOG="${LOG_ROOT}/helper-smoke.txt"
H6_SUMMARY_PATH="${OUTPUT_ROOT}/h6-summary.txt"
SIGNED_RELEASE_ROOT="${OUTPUT_ROOT}/signed-release"

rm -rf "${OUTPUT_ROOT}"
mkdir -p "${LOG_ROOT}" "${HELPER_SMOKE_ROOT}"

if [[ "${SKIP_XCODEGEN}" -eq 0 ]]; then
  run_logged "${LOG_ROOT}/xcodegen.log" xcodegen generate
fi

run_logged "${LOG_ROOT}/swift-test.log" swift test
run_logged "${LOG_ROOT}/debug-build.log" \
  xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build
run_logged "${LOG_ROOT}/release-build.log" \
  xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Release CODE_SIGNING_ALLOWED=NO build
run_logged "${LOG_ROOT}/devsigned-build.log" \
  xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration DevSigned build
run_logged "${LOG_ROOT}/policy-build-for-testing.log" \
  xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing \
    -only-testing:PromptCueTests/AppDelegateCloudSyncTests \
    -only-testing:PromptCueTests/AppModelCloudSyncLifecycleTests \
    -only-testing:PromptCueTests/CloudSyncSettingsTests

run_logged "${LOG_ROOT}/archive-release-validation.log" \
  "${PROJECT_ROOT}/scripts/archive_release_validation.sh" \
    --output-root "${ARCHIVE_VALIDATION_ROOT}" \
    --skip-xcodegen

[[ -d "${ARCHIVE_VALIDATION_ROOT}/Prompt Cue.app" ]] \
  || fail "release validation export is missing: ${ARCHIVE_VALIDATION_ROOT}/Prompt Cue.app"

ditto "${ARCHIVE_VALIDATION_ROOT}/Prompt Cue.app" "${HELPER_SMOKE_APP}"

env -i \
  HOME="${HOME}" \
  PATH="${PATH}" \
  TMPDIR="${TMPDIR:-/tmp}" \
  LANG=C \
  LC_ALL=C \
  "${HELPER_SMOKE_APP}/Contents/Helpers/BacktickMCP" --help > "${HELPER_SMOKE_LOG}" 2>&1

grep -q "Usage: BacktickMCP" "${HELPER_SMOKE_LOG}" \
  || fail "bundled helper smoke did not print usage from temp directory"

if has_signed_release_credentials; then
  run_logged "${LOG_ROOT}/archive-signed-release.log" \
    "${PROJECT_ROOT}/scripts/archive_signed_release.sh" \
      --output-root "${SIGNED_RELEASE_ROOT}" \
      --skip-xcodegen
  SIGNED_STATUS="completed"
else
  if [[ "${REQUIRE_SIGNED}" -eq 1 ]]; then
    fail "signed release credentials are unavailable; install a Developer ID Application certificate and set PROMPTCUE_RELEASE_TEAM_ID / PROMPTCUE_RELEASE_NOTARY_PROFILE"
  fi
  SIGNED_STATUS="blocked-by-local-credentials"
fi

cat > "${H6_SUMMARY_PATH}" <<EOF
H6 Verification Summary
Output root: ${OUTPUT_ROOT}

Completed:
- swift test
- xcodegen generate$([[ "${SKIP_XCODEGEN}" -eq 1 ]] && printf ' (skipped by flag)' || true)
- Debug build (CODE_SIGNING_ALLOWED=NO)
- Release build (CODE_SIGNING_ALLOWED=NO)
- DevSigned build
- app-target policy build-for-testing
- unsigned release archive validation
- bundled helper smoke from temp directory

Signed release lane:
- ${SIGNED_STATUS}

Key artifacts:
- unsigned release validation: ${ARCHIVE_VALIDATION_ROOT}
- helper smoke log: ${HELPER_SMOKE_LOG}
- signed release root: ${SIGNED_RELEASE_ROOT}
EOF

printf 'H6 verification complete.\n'
printf 'Summary: %s\n' "${H6_SUMMARY_PATH}"
printf 'Helper smoke log: %s\n' "${HELPER_SMOKE_LOG}"
printf 'Unsigned release validation: %s\n' "${ARCHIVE_VALIDATION_ROOT}"
printf 'Signed release lane: %s\n' "${SIGNED_STATUS}"
