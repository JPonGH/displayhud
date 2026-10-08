#!/bin/sh
# Build Display HUD.app from this checkout.
#
# Portable: no signing identity, team ID, or personal path is hard-coded.
# The app is ad-hoc signed only. It is NOT notarized and NOT Developer ID
# signed. This script never installs or launches anything.
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_ROOT=${DISPLAY_HUD_BUILD_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/displayhud-build.XXXXXX")}
SWIFT_SCRATCH="$BUILD_ROOT/swiftpm-release"
APP_PATH="$BUILD_ROOT/Display HUD.app"
CONTENTS="$APP_PATH/Contents"

case $APP_PATH in
  "$BUILD_ROOT"/*) ;;
  *) echo "Refusing unexpected app path: $APP_PATH" >&2; exit 2 ;;
esac

# NOTE: the native build engine is required here. The default swiftbuild
# engine mis-stamps LC_BUILD_VERSION with sdk 15.0 on this toolchain,
# which changes AppKit compatibility behavior; the native engine stamps
# the current SDK while keeping minos 15.0. package-release.sh gates on it.
swift build \
  --package-path "$PROJECT_ROOT" \
  --scratch-path "$SWIFT_SCRATCH" \
  -c release \
  --arch arm64 \
  --build-system native >&2
BIN_PATH=$(swift build \
  --package-path "$PROJECT_ROOT" \
  --scratch-path "$SWIFT_SCRATCH" \
  -c release \
  --arch arm64 \
  --build-system native \
  --show-bin-path)
/bin/rm -rf -- "$APP_PATH"
/bin/mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
/usr/bin/ditto "$BIN_PATH/DisplayHUD" "$CONTENTS/MacOS/DisplayHUD"
/usr/bin/ditto "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Strip local symbol-table debug info from the bundled copy BEFORE signing:
# release binaries otherwise carry STABS debug-map entries (N_SO/N_OSO)
# with absolute workstation source paths. Stripping invalidates any prior
# signature, so the ad-hoc sign below must stay after this step.
/usr/bin/strip -S "$CONTENTS/MacOS/DisplayHUD"

ICON_WORK=$(mktemp -d "${TMPDIR:-/tmp}/display-hud-icon.XXXXXX")
trap '/bin/rm -rf -- "$ICON_WORK"' EXIT INT TERM
/usr/bin/swift "$PROJECT_ROOT/scripts/generate-icon.swift" "$ICON_WORK/icon_1024x1024.png"
/bin/mkdir -p "$ICON_WORK/DisplayHUD.iconset"
for SPEC in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  set -- $SPEC
  /usr/bin/sips -z "$1" "$1" "$ICON_WORK/icon_1024x1024.png" \
    --out "$ICON_WORK/DisplayHUD.iconset/$2" >/dev/null
done
/usr/bin/iconutil -c icns "$ICON_WORK/DisplayHUD.iconset" -o "$CONTENTS/Resources/DisplayHUD.icns"

/usr/bin/xattr -cr "$APP_PATH"
/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >&2
echo "$APP_PATH"
