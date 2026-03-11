#!/bin/sh

set -eu

SWIFT_BUILD_CONFIGURATION="debug"
if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
  SWIFT_BUILD_CONFIGURATION="release"
fi

SWIFT_BIN="$(xcrun --find swift)"
SCRATCH_PATH="${DERIVED_FILE_DIR}/BacktickMCPScratch"
HELPER_DESTINATION="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/BacktickMCP"

"$SWIFT_BIN" build \
  --package-path "$SRCROOT" \
  --scratch-path "$SCRATCH_PATH" \
  --configuration "$SWIFT_BUILD_CONFIGURATION" \
  --product BacktickMCP >/dev/null

HELPER_BIN_PATH="$("$SWIFT_BIN" build \
  --package-path "$SRCROOT" \
  --scratch-path "$SCRATCH_PATH" \
  --configuration "$SWIFT_BUILD_CONFIGURATION" \
  --show-bin-path)/BacktickMCP"

mkdir -p "$(dirname "$HELPER_DESTINATION")"
ditto "$HELPER_BIN_PATH" "$HELPER_DESTINATION"
chmod 755 "$HELPER_DESTINATION"
