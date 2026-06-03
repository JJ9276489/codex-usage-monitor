#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexUsageMonitor"
LABEL="io.github.jj9276489.codex-usage-monitor"
LEGACY_LABEL="com.jeraldyuan.codex-usage-monitor"

INSTALL_APP="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"

for label in "$LABEL" "$LEGACY_LABEL"; do
  plist="$LAUNCH_AGENT_DIR/$label.plist"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  rm -f "$plist"
done

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$INSTALL_APP"

echo "Removed $INSTALL_APP"
echo "Removed Codex Usage Monitor login items"
