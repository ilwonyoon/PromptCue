#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_CONFIG_PATH="${PROJECT_ROOT}/Config/Local.xcconfig"

SOURCE_PACKAGES_DIR=""
ARCHIVES_DIR=""
DOWNLOAD_URL_PREFIX=""
RELEASE_URL=""
OUTPUT_PATH=""
KEY_ACCOUNT=""
GENERATOR_PATH=""

print_usage() {
  cat <<'EOF'
Usage: scripts/generate_sparkle_appcast.sh [options]

Generate a Sparkle appcast for a directory containing notarized update archives.

Options:
  --source-packages-dir PATH   Source packages root produced by xcodebuild
  --archives-dir PATH          Directory containing Sparkle update archives
  --download-url-prefix URL    Prefix used for appcast enclosure URLs
  --release-url URL            GitHub release URL used for release notes / link
  --output-path PATH           Output appcast path
  --key-account NAME           Sparkle keychain account (default: Local.xcconfig or "backtick")
  --generator PATH             Explicit path to generate_appcast binary
  --help                       Show this help
EOF
}

fail() {
  echo "generate_sparkle_appcast: $*" >&2
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

resolve_generator_path() {
  if [[ -n "${GENERATOR_PATH}" ]]; then
    GENERATOR_PATH="$(absolute_path "${GENERATOR_PATH}")"
  elif [[ -n "${SOURCE_PACKAGES_DIR}" ]]; then
    GENERATOR_PATH="${SOURCE_PACKAGES_DIR}/artifacts/sparkle/Sparkle/bin/generate_appcast"
  fi

  [[ -n "${GENERATOR_PATH}" ]] || fail "missing Sparkle generator path; pass --generator or --source-packages-dir"
  [[ -x "${GENERATOR_PATH}" ]] || fail "Sparkle generate_appcast is missing or not executable: ${GENERATOR_PATH}"
}

sparkle_key_exists() {
  local account="$1"
  security find-generic-password \
    -s https://sparkle-project.org \
    -a "${account}" >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-packages-dir)
      [[ $# -ge 2 ]] || fail "--source-packages-dir requires a value"
      SOURCE_PACKAGES_DIR="$2"
      shift 2
      ;;
    --archives-dir)
      [[ $# -ge 2 ]] || fail "--archives-dir requires a value"
      ARCHIVES_DIR="$2"
      shift 2
      ;;
    --download-url-prefix)
      [[ $# -ge 2 ]] || fail "--download-url-prefix requires a value"
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --release-url)
      [[ $# -ge 2 ]] || fail "--release-url requires a value"
      RELEASE_URL="$2"
      shift 2
      ;;
    --output-path)
      [[ $# -ge 2 ]] || fail "--output-path requires a value"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --key-account)
      [[ $# -ge 2 ]] || fail "--key-account requires a value"
      KEY_ACCOUNT="$2"
      shift 2
      ;;
    --generator)
      [[ $# -ge 2 ]] || fail "--generator requires a value"
      GENERATOR_PATH="$2"
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

[[ -n "${ARCHIVES_DIR}" ]] || fail "--archives-dir is required"
[[ -n "${DOWNLOAD_URL_PREFIX}" ]] || fail "--download-url-prefix is required"
[[ -n "${RELEASE_URL}" ]] || fail "--release-url is required"
[[ -n "${OUTPUT_PATH}" ]] || fail "--output-path is required"

ARCHIVES_DIR="$(absolute_path "${ARCHIVES_DIR}")"
OUTPUT_PATH="$(absolute_path "${OUTPUT_PATH}")"
if [[ -n "${SOURCE_PACKAGES_DIR}" ]]; then
  SOURCE_PACKAGES_DIR="$(absolute_path "${SOURCE_PACKAGES_DIR}")"
fi

if [[ -z "${KEY_ACCOUNT}" ]]; then
  KEY_ACCOUNT="$(read_local_config_value PROMPTCUE_SPARKLE_KEY_ACCOUNT)"
fi
[[ -n "${KEY_ACCOUNT}" ]] || KEY_ACCOUNT="backtick"

[[ -d "${ARCHIVES_DIR}" ]] || fail "archives dir does not exist: ${ARCHIVES_DIR}"
resolve_generator_path

ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"

if [[ -z "${ED_KEY_FILE}" ]] && ! sparkle_key_exists "${KEY_ACCOUNT}"; then
  fail "Sparkle keychain item for account '${KEY_ACCOUNT}' is missing. Run generate_keys --account ${KEY_ACCOUNT} and set PROMPTCUE_SPARKLE_PUBLIC_ED_KEY in Config/Local.xcconfig"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

GENERATOR_ARGS=(
  --download-url-prefix "${DOWNLOAD_URL_PREFIX}"
  --full-release-notes-url "${RELEASE_URL}"
  --link "${RELEASE_URL}"
  -o "${OUTPUT_PATH}"
)

if [[ -n "${ED_KEY_FILE}" ]]; then
  GENERATOR_ARGS+=(--ed-key-file "${ED_KEY_FILE}")
else
  GENERATOR_ARGS+=(--account "${KEY_ACCOUNT}")
fi

GENERATOR_ARGS+=("${ARCHIVES_DIR}")

run "${GENERATOR_PATH}" "${GENERATOR_ARGS[@]}"

echo "Sparkle appcast: ${OUTPUT_PATH}"
