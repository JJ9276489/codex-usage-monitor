#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexUsageMonitor"
LABEL="io.github.jj9276489.codex-usage-monitor"
LEGACY_LABEL="com.jeraldyuan.codex-usage-monitor"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/$APP_NAME.app"
INSTALL_BINARY="$INSTALL_APP/Contents/MacOS/$APP_NAME"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PLIST="$LAUNCH_AGENT_DIR/$LABEL.plist"
LEGACY_PLIST="$LAUNCH_AGENT_DIR/$LEGACY_LABEL.plist"

"$ROOT_DIR/script/build_and_run.sh" --build-only

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENT_DIR" "$LOG_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$INSTALL_APP"
cp -R "$SOURCE_APP" "$INSTALL_APP"
test -x "$INSTALL_BINARY"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

environment_plist=""
for name in CODEX_HOME CODEX_USAGE_DB CODEX_LOGS_DB; do
  value="${!name:-}"
  if [[ -n "$value" ]]; then
    if [[ -z "$environment_plist" ]]; then
      environment_plist="  <key>EnvironmentVariables</key>
  <dict>"
    fi
    environment_plist="$environment_plist
    <key>$name</key>
    <string>$(xml_escape "$value")</string>"
  fi
done
if [[ -n "$environment_plist" ]]; then
  environment_plist="$environment_plist
  </dict>"
fi

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_BINARY</string>
  </array>
$environment_plist
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/$APP_NAME.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/$APP_NAME.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" >/dev/null 2>&1 || true
rm -f "$LEGACY_PLIST"
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "Installed $INSTALL_APP"
echo "Registered login item $PLIST"
