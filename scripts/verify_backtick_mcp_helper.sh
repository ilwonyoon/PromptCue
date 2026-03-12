#!/usr/bin/env bash

set -euo pipefail

readonly EXPECTED_HELPER_NAME="BacktickMCP"

HELPER_PATH=""
EXPECTED_ARCHITECTURES_SOURCE=""
REQUIRE_SIGNED=0
ALLOW_UNSIGNED=0

fail() {
  echo "verify_backtick_mcp_helper: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/verify_backtick_mcp_helper.sh --helper-path <path> [options]

Options:
  --expected-archs <arch list>  Space- or comma-delimited architecture list.
  --require-signed              Fail if the helper is not code signed.
  --allow-unsigned              Accept an unsigned helper artifact.
  -h, --help                    Show this message.
EOF
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

parse_architectures() {
  local source="$1"
  local parsed=()
  local token=""
  local normalized=""

  for token in ${source//,/ }; do
    normalized="$(normalize_architecture "${token}")"
    if [[ ${#parsed[@]} -eq 0 ]] \
      || ! array_contains "${normalized}" "${parsed[@]}"; then
      parsed+=("${normalized}")
    fi
  done

  if [[ ${#parsed[@]} -eq 0 ]]; then
    fail "unable to parse any architectures from '${source}'"
  fi

  printf '%s\n' "${parsed[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --helper-path)
      [[ $# -ge 2 ]] || fail "--helper-path requires a value"
      HELPER_PATH="$2"
      shift 2
      ;;
    --expected-archs)
      [[ $# -ge 2 ]] || fail "--expected-archs requires a value"
      EXPECTED_ARCHITECTURES_SOURCE="$2"
      shift 2
      ;;
    --require-signed)
      REQUIRE_SIGNED=1
      shift
      ;;
    --allow-unsigned)
      ALLOW_UNSIGNED=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument '${1}'"
      ;;
  esac
done

[[ -n "${HELPER_PATH}" ]] || {
  usage >&2
  exit 1
}

if [[ ${REQUIRE_SIGNED} -eq 1 && ${ALLOW_UNSIGNED} -eq 1 ]]; then
  fail "--require-signed and --allow-unsigned are mutually exclusive"
fi

[[ -f "${HELPER_PATH}" ]] || fail "helper does not exist: ${HELPER_PATH}"
[[ -x "${HELPER_PATH}" ]] || fail "helper is not executable: ${HELPER_PATH}"

if [[ "$(basename "${HELPER_PATH}")" != "${EXPECTED_HELPER_NAME}" ]]; then
  fail "helper path must end with ${EXPECTED_HELPER_NAME}: ${HELPER_PATH}"
fi

FILE_OUTPUT="$(/usr/bin/file "${HELPER_PATH}")"
[[ "${FILE_OUTPUT}" == *"Mach-O"* ]] || fail "helper is not a Mach-O executable: ${FILE_OUTPUT}"

ACTUAL_ARCHITECTURES_OUTPUT="$(/usr/bin/lipo -archs "${HELPER_PATH}")"
ACTUAL_ARCHITECTURES=()
while IFS= read -r architecture; do
  ACTUAL_ARCHITECTURES+=("${architecture}")
done < <(parse_architectures "${ACTUAL_ARCHITECTURES_OUTPUT}")

if [[ -n "${EXPECTED_ARCHITECTURES_SOURCE}" ]]; then
  EXPECTED_ARCHITECTURES=()
  while IFS= read -r architecture; do
    EXPECTED_ARCHITECTURES+=("${architecture}")
  done < <(parse_architectures "${EXPECTED_ARCHITECTURES_SOURCE}")

  if [[ ${#EXPECTED_ARCHITECTURES[@]} -ne ${#ACTUAL_ARCHITECTURES[@]} ]]; then
    fail "expected architectures '${EXPECTED_ARCHITECTURES[*]}', found '${ACTUAL_ARCHITECTURES[*]}'"
  fi

  for architecture in "${EXPECTED_ARCHITECTURES[@]}"; do
    if ! array_contains "${architecture}" "${ACTUAL_ARCHITECTURES[@]}"; then
      fail "expected architecture '${architecture}' is missing from '${ACTUAL_ARCHITECTURES[*]}'"
    fi
  done
fi

SIGNED_STATE="unsigned"
if /usr/bin/codesign -dvv "${HELPER_PATH}" >/dev/null 2>&1; then
  /usr/bin/codesign --verify --strict --verbose=4 "${HELPER_PATH}" >/dev/null
  SIGNED_STATE="signed"
elif [[ ${REQUIRE_SIGNED} -eq 1 ]]; then
  fail "helper is not code signed: ${HELPER_PATH}"
elif [[ ${ALLOW_UNSIGNED} -ne 1 ]]; then
  fail "helper signature state is unknown and unsigned helpers were not allowed"
fi

printf 'verify_backtick_mcp_helper: path=%s\n' "${HELPER_PATH}"
printf 'verify_backtick_mcp_helper: architectures=%s\n' "${ACTUAL_ARCHITECTURES[*]}"
printf 'verify_backtick_mcp_helper: signature=%s\n' "${SIGNED_STATE}"
