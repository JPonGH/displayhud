#!/bin/sh
# Package a Display HUD public-preview release from this checkout.
#
# Portable: takes no identity or path arguments, installs nothing, launches
# nothing. Produces an ad-hoc signed arm64 app ZIP, a source archive, and
# SHA256SUMS in dist/. The app is NOT notarized and NOT Developer ID signed.
#
# Usage: ./scripts/package-release.sh [VERSION]
#   VERSION defaults to 0.9.0-public-preview.1
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:-0.9.0-public-preview.1}
case $VERSION in
  *"/"* | "" | -*)
    echo "Refusing unsafe version: $VERSION" >&2; exit 2 ;;
esac

RELEASE_DIR="$PROJECT_ROOT/dist/release-$VERSION"
ZIP_NAME="Display-HUD-$VERSION-arm64.zip"
SRC_NAME="Display-HUD-$VERSION-source.tar.gz"

APP_PATH=$("$PROJECT_ROOT/scripts/build-app.sh")
if [ ! -d "$APP_PATH" ]; then
  echo "Build did not produce an app bundle: $APP_PATH" >&2
  exit 1
fi

fail_gate() {
  echo "package-release: pre-zip gate FAILED: $1" >&2
  exit 1
}

EXEC="$APP_PATH/Contents/MacOS/DisplayHUD"
[ -f "$EXEC" ] || fail_gate "missing bundle executable: $EXEC"
command -v /usr/bin/nm >/dev/null 2>&1 || fail_gate "missing /usr/bin/nm"
command -v /usr/bin/grep >/dev/null 2>&1 || fail_gate "missing /usr/bin/grep"
command -v /usr/bin/vtool >/dev/null 2>&1 || fail_gate "missing /usr/bin/vtool"

# Privacy gate (fail-closed): the executable must carry no STABS debug-map
# entries and no raw workstation-path bytes. Checked on raw bytes, not via
# strings(1), which misses the string table. Any inspection failure refuses
# to package.
NM_OUT=$(/usr/bin/nm -pa "$EXEC" 2>/dev/null) \
  || fail_gate "could not inspect executable with nm -pa"
if printf '%s\n' "$NM_OUT" | /usr/bin/grep -qE ' (SO|OSO|SOL) '; then
  fail_gate "STABS debug entries (N_SO/N_OSO/N_SOL) present; strip -S before signing"
fi
for PAT in '/Users/' '/var/folders/' '/private/'; do
  if /usr/bin/grep -a -q -F -e "$PAT" "$EXEC"; then
    fail_gate "raw executable bytes contain workstation path pattern: $PAT"
  fi
done
if [ -n "${HOME:-}" ]; then
  if /usr/bin/grep -a -q -F -e "$HOME" "$EXEC"; then
    fail_gate "raw executable bytes contain the build HOME directory path"
  fi
fi
if /usr/bin/grep -a -q -F -e "$PROJECT_ROOT" "$EXEC"; then
  fail_gate "raw executable bytes contain the project root path"
fi

# SDK gate (fail-closed): LC_BUILD_VERSION must stamp a current SDK.
# The default swiftbuild engine mis-stamps sdk 15.0, which changes AppKit
# compatibility behavior; release builds must use --build-system native.
SDK_VER=$(/usr/bin/vtool -show-build "$EXEC" 2>/dev/null \
  | /usr/bin/awk '/^[[:space:]]*sdk / { print $2; exit }')
case $SDK_VER in
  '' | *[!0-9.]* | *.*.*) fail_gate "could not determine LC_BUILD_VERSION sdk" ;;
esac
SDK_MAJOR=${SDK_VER%%.*}
if [ "$SDK_MAJOR" -lt 26 ]; then
  fail_gate "LC_BUILD_VERSION sdk $SDK_VER < 26.0; rebuild with --build-system native"
fi
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/display-hud-release.XXXXXX")
trap '/bin/rm -rf -- "$STAGING_DIR"' EXIT INT TERM

/bin/rm -rf -- "$RELEASE_DIR"
/bin/mkdir -p "$RELEASE_DIR"
/usr/bin/ditto --norsrc -c -k --keepParent "$APP_PATH" "$STAGING_DIR/$ZIP_NAME"
/usr/bin/ditto "$STAGING_DIR/$ZIP_NAME" "$RELEASE_DIR/$ZIP_NAME"

git -C "$PROJECT_ROOT" archive --format=tar.gz --prefix="displayhud-$VERSION/" HEAD > "$RELEASE_DIR/$SRC_NAME"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$ZIP_NAME" "$SRC_NAME" > SHA256SUMS.txt
)
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "$RELEASE_DIR"
