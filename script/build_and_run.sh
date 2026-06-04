#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexUsageMonitor"
BUNDLE_ID="io.github.jj9276489.CodexUsageMonitor"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

case "$MODE" in
  --build-only|build)
    ;;
  *)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    ;;
esac

build_with_swiftpm() {
  local log_file="$ROOT_DIR/.build/swiftpm-build.log"
  mkdir -p "$(dirname "$log_file")"
  swift build >"$log_file" 2>&1 || return 1
  BUILD_BINARY="$(swift build --show-bin-path 2>>"$log_file")/$APP_NAME"
  test -x "$BUILD_BINARY"
}

build_with_swiftc() {
  local manual_dir="$ROOT_DIR/.build/manual"
  mkdir -p "$manual_dir"
  local swift_files=()
  while IFS= read -r -d '' file; do
    swift_files+=("$file")
  done < <(find "$ROOT_DIR/Sources/CodexUsageMonitor" -name '*.swift' -print0 | sort -z)

  # Fallback for machines where SwiftPM's PackageDescription toolchain is broken.
  swiftc -parse-as-library \
    "${swift_files[@]}" \
    -o "$manual_dir/$APP_NAME" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    -lsqlite3
  BUILD_BINARY="$manual_dir/$APP_NAME"
}

if ! build_with_swiftpm; then
  echo "SwiftPM build failed; falling back to direct swiftc build. Details: .build/swiftpm-build.log" >&2
  build_with_swiftc
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Usage Monitor</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
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
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --build-only|build)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2
    exit 2
    ;;
esac
