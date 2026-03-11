#!/usr/bin/env bash

set -euo pipefail

if [[ "${CONFIGURATION:-}" != "DevSigned" ]]; then
  exit 0
fi

PROJECT_ROOT="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOCAL_CONFIG_PATH="${PROJECT_ROOT}/Config/Local.xcconfig"
APP_PATH="${CODESIGNING_FOLDER_PATH:-${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "sign_dev_app: app bundle does not exist: ${APP_PATH}" >&2
  exit 1
fi

SIGNING_REFERENCE="${PROMPTCUE_DEV_SIGNING_SHA1:-}"
SIGNING_LABEL=""

if [[ -z "${SIGNING_REFERENCE}" && -f "${LOCAL_CONFIG_PATH}" ]]; then
  SIGNING_REFERENCE="$(
    awk -F '=' '
      /^[[:space:]]*PROMPTCUE_DEV_SIGNING_SHA1[[:space:]]*=/ {
        value=$2
        gsub(/[[:space:]]/, "", value)
        print value
        exit
      }
    ' "${LOCAL_CONFIG_PATH}"
  )"
fi

if [[ -n "${SIGNING_REFERENCE}" ]]; then
  SIGNING_LABEL="${SIGNING_REFERENCE}"
else
  SIGNING_LABEL="${PROMPTCUE_DEV_SIGNING_IDENTITY:-}"
  SIGNING_REFERENCE="${SIGNING_LABEL}"
fi

if [[ -z "${SIGNING_REFERENCE}" ]]; then
  SIGNING_REFERENCE="$(
    security find-identity -v -p codesigning \
      | awk '/Apple Development:/ && $0 !~ /REVOKED/ { print $2; exit }'
  )"
  SIGNING_LABEL="$(
    security find-identity -v -p codesigning \
      | awk -F '"' '/Apple Development:/ && $0 !~ /REVOKED/ { print $2; exit }'
  )"
fi

if [[ -z "${SIGNING_REFERENCE}" ]]; then
  echo "sign_dev_app: no valid Apple Development signing identity found." >&2
  echo "sign_dev_app: set PROMPTCUE_DEV_SIGNING_SHA1 in Config/Local.xcconfig." >&2
  exit 1
fi

if [[ -z "${SIGNING_LABEL}" ]]; then
  SIGNING_LABEL="${SIGNING_REFERENCE}"
fi

echo "sign_dev_app: signing ${APP_PATH} with ${SIGNING_LABEL}"
/usr/bin/codesign --force --deep --sign "${SIGNING_REFERENCE}" --timestamp=none "${APP_PATH}"
/usr/bin/codesign --verify --deep --strict "${APP_PATH}"
