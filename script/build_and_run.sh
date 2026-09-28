#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_DISPLAY_NAME="Teleport Desktop"
APP_EXECUTABLE_NAME="teleport-desktop"
BUNDLE_ID="com.kernelp4nic.teleport-desktop"
APP_ICON_NAME="TeleportDesktop.icns"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/$APP_ICON_NAME"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
LEGACY_APP_BUNDLE="$DIST_DIR/$APP_EXECUTABLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

# SwiftTerm's shaders require full Xcode and its Metal Toolchain. Prefer the
# selected tools, but fall back to the standard Xcode install when only CLT is
# selected. Respect an explicit DEVELOPER_DIR override.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcrun --find metal >/dev/null 2>&1; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

if ! xcrun --find metal >/dev/null 2>&1; then
  echo "error: SwiftTerm requires full Xcode with the Metal Toolchain." >&2
  echo "Install Xcode and set DEVELOPER_DIR to its Contents/Developer directory." >&2
  exit 1
fi
if ! xcrun metal --version >/dev/null 2>&1; then
  echo "error: The selected Xcode's Metal compiler is unavailable. Install its toolchain:" >&2
  printf '  DEVELOPER_DIR=%q xcodebuild -downloadComponent MetalToolchain\n' "${DEVELOPER_DIR:-$(xcode-select -p)}" >&2
  exit 1
fi

cd "$ROOT_DIR"
xcrun swift build
BUILD_DIR="$(xcrun swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_EXECUTABLE_NAME"

pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true

rm -rf "$APP_BUNDLE"
if [[ "$LEGACY_APP_BUNDLE" != "$APP_BUNDLE" ]]; then
  rm -rf "$LEGACY_APP_BUNDLE"
fi
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/$APP_ICON_NAME"
# Preserve SwiftPM resources, including SwiftTerm's compiled Metal shaders.
for resource_bundle in "$BUILD_DIR"/*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$APP_RESOURCES/"
done

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
