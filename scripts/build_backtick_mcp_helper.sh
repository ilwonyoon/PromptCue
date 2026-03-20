#!/usr/bin/env bash

set -euo pipefail

readonly HELPER_NAME="BacktickMCP"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${SRCROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
readonly VERIFY_SCRIPT="${SCRIPT_DIR}/verify_backtick_mcp_helper.sh"

SWIFT_BUILD_CONFIGURATION="debug"
if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
  SWIFT_BUILD_CONFIGURATION="release"
fi

fail() {
  echo "build_backtick_mcp_helper: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"

  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command not found: ${command_name}"
}

normalize_architecture() {
  case "$1" in
    arm64 | arm64e)
      printf 'arm64\n'
      ;;
    x86_64 | x86-64 | x64)
      printf 'x86_64\n'
      ;;
    "")
      fail "received an empty architecture token"
      ;;
    *)
      fail "unsupported architecture '${1}'"
      ;;
  esac
}

array_contains() {
  local needle="$1"
  shift

  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done

  return 1
}

resolve_architectures() {
  local architecture_source="${BACKTICK_MCP_HELPER_ARCHS:-${ARCHS:-${NATIVE_ARCH_ACTUAL:-$(uname -m)}}}"
  local normalized_candidates=()
  local token=""
  local normalized=""

  for token in ${architecture_source//,/ }; do
    normalized="$(normalize_architecture "${token}")"
    if [[ ${#normalized_candidates[@]} -eq 0 ]] \
      || ! array_contains "${normalized}" "${normalized_candidates[@]}"; then
      normalized_candidates+=("${normalized}")
    fi
  done

  ARCHITECTURES=()

  if [[ ${#normalized_candidates[@]} -gt 0 ]] \
    && array_contains "arm64" "${normalized_candidates[@]}"; then
    ARCHITECTURES+=("arm64")
  fi

  if [[ ${#normalized_candidates[@]} -gt 0 ]] \
    && array_contains "x86_64" "${normalized_candidates[@]}"; then
    ARCHITECTURES+=("x86_64")
  fi

  if [[ ${#ARCHITECTURES[@]} -eq 0 ]]; then
    fail "unable to resolve helper architectures from '${architecture_source}'"
  fi
}

resolve_destination() {
  if [[ -n "${BACKTICK_MCP_HELPER_DESTINATION:-}" ]]; then
    HELPER_DESTINATION="${BACKTICK_MCP_HELPER_DESTINATION}"
  else
    [[ -n "${TARGET_BUILD_DIR:-}" ]] \
      || fail "TARGET_BUILD_DIR is required when BACKTICK_MCP_HELPER_DESTINATION is not set"
    [[ -n "${CONTENTS_FOLDER_PATH:-}" ]] \
      || fail "CONTENTS_FOLDER_PATH is required when BACKTICK_MCP_HELPER_DESTINATION is not set"
    HELPER_DESTINATION="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/${HELPER_NAME}"
  fi

  if [[ "$(basename "${HELPER_DESTINATION}")" != "${HELPER_NAME}" ]]; then
    fail "helper destination must end with ${HELPER_NAME}: ${HELPER_DESTINATION}"
  fi
}

resolve_scratch_path() {
  if [[ -n "${BACKTICK_MCP_HELPER_SCRATCH_PATH:-}" ]]; then
    SCRATCH_ROOT="${BACKTICK_MCP_HELPER_SCRATCH_PATH}"
  else
    SCRATCH_ROOT="${PROJECT_ROOT}/build/BacktickMCPScratch"
  fi

  mkdir -p "${SCRATCH_ROOT}"
}

resolve_deployment_target() {
  DEPLOYMENT_TARGET="${BACKTICK_MCP_HELPER_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-14.0}}"
}

resolve_swiftpm_state_paths() {
  SWIFTPM_BUILD_ARGS=()
  SWIFTPM_STATE_MODE="shared"

  if [[ -n "${BACKTICK_MCP_HELPER_SCRATCH_PATH:-}" ]] \
    || [[ "${BACKTICK_MCP_HELPER_ISOLATED_SWIFTPM_STATE:-0}" == "1" ]]; then
    SWIFTPM_STATE_MODE="isolated"
    SWIFTPM_CACHE_PATH="${SCRATCH_ROOT}/swiftpm-cache"
    SWIFTPM_CONFIG_PATH="${SCRATCH_ROOT}/swiftpm-config"
    SWIFTPM_SECURITY_PATH="${SCRATCH_ROOT}/swiftpm-security"

    mkdir -p \
      "${SWIFTPM_CACHE_PATH}" \
      "${SWIFTPM_CONFIG_PATH}" \
      "${SWIFTPM_SECURITY_PATH}"

    SWIFTPM_BUILD_ARGS+=(
      "--cache-path" "${SWIFTPM_CACHE_PATH}"
      "--config-path" "${SWIFTPM_CONFIG_PATH}"
      "--security-path" "${SWIFTPM_SECURITY_PATH}"
    )
  fi
}

resolve_codesign_strategy() {
  local requested_mode="${BACKTICK_MCP_HELPER_CODESIGN_MODE:-auto}"
  local expanded_identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
  local expanded_identity_name="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-${CODE_SIGN_IDENTITY:-}}"

  SIGNING_MODE="skip"
  SIGNING_REFERENCE=""
  SIGNING_LABEL=""

  if [[ "${expanded_identity}" == "-" ]]; then
    expanded_identity=""
  fi

  if [[ "${expanded_identity_name}" == "-" ]]; then
    expanded_identity_name=""
  fi

  case "${requested_mode}" in
    auto)
      if [[ -n "${expanded_identity}" ]]; then
        SIGNING_MODE="identity"
        SIGNING_REFERENCE="${expanded_identity}"
        SIGNING_LABEL="${expanded_identity_name:-${expanded_identity}}"
      elif [[ "${CONFIGURATION:-Debug}" == "Release" && "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
        fail "Release helper packaging requires a real signing identity when CODE_SIGNING_ALLOWED=YES; use CODE_SIGNING_ALLOWED=NO for unsigned local verification builds"
      else
        SIGNING_MODE="adhoc"
        SIGNING_REFERENCE="-"
        SIGNING_LABEL="adhoc"
      fi
      ;;
    adhoc)
      SIGNING_MODE="adhoc"
      SIGNING_REFERENCE="-"
      SIGNING_LABEL="adhoc"
      ;;
    identity | xcode)
      [[ -n "${expanded_identity}" ]] \
        || fail "BACKTICK_MCP_HELPER_CODESIGN_MODE=${requested_mode} requires EXPANDED_CODE_SIGN_IDENTITY"
      SIGNING_MODE="identity"
      SIGNING_REFERENCE="${expanded_identity}"
      SIGNING_LABEL="${expanded_identity_name:-${expanded_identity}}"
      ;;
    skip)
      SIGNING_MODE="skip"
      ;;
    *)
      fail "unsupported BACKTICK_MCP_HELPER_CODESIGN_MODE '${requested_mode}'"
      ;;
  esac
}

fallback_helper_path_for_architecture() {
  local arch="$1"
  local -a candidates=(
    "${PROJECT_ROOT}/.build/${arch}-apple-macosx/${SWIFT_BUILD_CONFIGURATION}/${HELPER_NAME}"
    "${PROJECT_ROOT}/.build/${SWIFT_BUILD_CONFIGURATION}/${HELPER_NAME}"
  )

  local candidate=""
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

build_for_architecture() {
  local arch="$1"
  local triple="${arch}-apple-macosx${DEPLOYMENT_TARGET}"
  local arch_scratch="${SCRATCH_ROOT}/${SWIFT_BUILD_CONFIGURATION}-${arch}"
  local bin_path=""
  local build_log="${SCRATCH_ROOT}/swift-build-${arch}.log"
  local fallback_path=""
  local attempt=1
  local -a scratch_args=()
  local -a build_args=(
    --disable-sandbox
    --package-path "${PROJECT_ROOT}"
    --manifest-cache local
    --only-use-versions-from-resolved-file
    --configuration "${SWIFT_BUILD_CONFIGURATION}"
    --triple "${triple}"
  )
  local -a show_bin_args=(
    --disable-sandbox
    --package-path "${PROJECT_ROOT}"
    --manifest-cache local
    --only-use-versions-from-resolved-file
    --configuration "${SWIFT_BUILD_CONFIGURATION}"
    --triple "${triple}"
    --show-bin-path
  )

  if [[ "${SWIFTPM_STATE_MODE}" == "isolated" ]]; then
    mkdir -p "${arch_scratch}"
    scratch_args=("--scratch-path" "${arch_scratch}")
    build_args+=("${SWIFTPM_BUILD_ARGS[@]}" "${scratch_args[@]}")
    show_bin_args+=("${SWIFTPM_BUILD_ARGS[@]}" "${scratch_args[@]}")
  fi

  while (( attempt <= 2 )); do
    if "${SWIFT_BIN}" build \
      "${build_args[@]}" \
      --product "${HELPER_NAME}" > /dev/null 2> "${build_log}"; then
      break
    fi

    if (( attempt == 1 )) && [[ "${SWIFTPM_STATE_MODE}" == "isolated" ]]; then
      echo "build_backtick_mcp_helper: retrying clean helper build for ${arch} after isolated scratch failure"
      rm -rf "${arch_scratch}"
      mkdir -p "${arch_scratch}"
      attempt=$((attempt + 1))
      continue
    fi

    if (( attempt == 1 )); then
      echo "build_backtick_mcp_helper: retrying shared helper build for ${arch}"
      attempt=$((attempt + 1))
      continue
    fi

    fallback_path="$(fallback_helper_path_for_architecture "${arch}" || true)"
    if [[ -n "${fallback_path}" ]]; then
      echo "build_backtick_mcp_helper: falling back to existing helper artifact for ${arch}: ${fallback_path}"
      BUILT_HELPER_PATHS+=("${fallback_path}")
      return
    fi

    cat "${build_log}" >&2
    fail "swift build failed for ${arch}"
  done

  bin_path="$("${SWIFT_BIN}" build "${show_bin_args[@]}")/${HELPER_NAME}"

  if [[ ! -x "${bin_path}" ]]; then
    fallback_path="$(fallback_helper_path_for_architecture "${arch}" || true)"
    if [[ -n "${fallback_path}" ]]; then
      echo "build_backtick_mcp_helper: using existing helper artifact for ${arch}: ${fallback_path}"
      BUILT_HELPER_PATHS+=("${fallback_path}")
      return
    fi

    fail "built helper for ${arch} is missing or not executable: ${bin_path}"
  fi

  BUILT_HELPER_PATHS+=("${bin_path}")
}

assemble_helper_binary() {
  local staging_directory="${SCRATCH_ROOT}/staging"
  local assembled_path="${staging_directory}/${HELPER_NAME}"

  mkdir -p "${staging_directory}"
  rm -f "${assembled_path}"

  if [[ ${#BUILT_HELPER_PATHS[@]} -eq 1 ]]; then
    ditto "${BUILT_HELPER_PATHS[0]}" "${assembled_path}"
  else
    /usr/bin/lipo -create "${BUILT_HELPER_PATHS[@]}" -output "${assembled_path}"
  fi

  chmod 755 "${assembled_path}"
  mkdir -p "$(dirname "${HELPER_DESTINATION}")"
  rm -f "${HELPER_DESTINATION}"
  ditto "${assembled_path}" "${HELPER_DESTINATION}"
  chmod 755 "${HELPER_DESTINATION}"
}

sign_helper_binary() {
  local -a codesign_args=("--force" "--sign" "${SIGNING_REFERENCE}")

  case "${SIGNING_MODE}" in
    skip)
      echo "build_backtick_mcp_helper: skipping helper codesign"
      return
      ;;
    adhoc)
      codesign_args+=("--timestamp=none")
      ;;
    identity)
      if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
        codesign_args+=("--options" "runtime" "--timestamp")
      else
        codesign_args+=("--timestamp=none")
      fi
      ;;
    *)
      fail "unexpected signing mode '${SIGNING_MODE}'"
      ;;
  esac

  /usr/bin/codesign "${codesign_args[@]}" "${HELPER_DESTINATION}"
  echo "build_backtick_mcp_helper: signed helper (${SIGNING_LABEL})"
}

require_command "xcrun"
require_command "ditto"
require_command "codesign"
require_command "lipo"
require_command "file"

[[ -x "${VERIFY_SCRIPT}" ]] || fail "missing helper verifier: ${VERIFY_SCRIPT}"

SWIFT_BIN="$(xcrun --find swift)"
[[ -n "${SWIFT_BIN}" ]] || fail "unable to resolve swift toolchain path"

declare -a ARCHITECTURES=()
declare -a BUILT_HELPER_PATHS=()
declare -a SWIFTPM_BUILD_ARGS=()
SWIFTPM_STATE_MODE="shared"

resolve_architectures
resolve_destination
resolve_scratch_path
resolve_deployment_target
resolve_swiftpm_state_paths
resolve_codesign_strategy

echo "build_backtick_mcp_helper: packaging ${HELPER_NAME} for ${ARCHITECTURES[*]} -> ${HELPER_DESTINATION} (${SWIFTPM_STATE_MODE} SwiftPM state)"

for architecture in "${ARCHITECTURES[@]}"; do
  build_for_architecture "${architecture}"
done

assemble_helper_binary
sign_helper_binary

VERIFY_ARGS=(
  "--helper-path" "${HELPER_DESTINATION}"
  "--expected-archs" "${ARCHITECTURES[*]}"
)

if [[ "${SIGNING_MODE}" == "skip" ]]; then
  VERIFY_ARGS+=("--allow-unsigned")
else
  VERIFY_ARGS+=("--require-signed")
fi

"${VERIFY_SCRIPT}" "${VERIFY_ARGS[@]}"
