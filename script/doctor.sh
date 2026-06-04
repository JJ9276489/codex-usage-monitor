#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME_PATH="${CODEX_HOME:-$HOME/.codex}"
USAGE_DB_PATH="${CODEX_USAGE_DB:-$CODEX_HOME_PATH/state_5.sqlite}"
LOGS_DB_PATH="${CODEX_LOGS_DB:-$CODEX_HOME_PATH/logs_2.sqlite}"

failures=0

pass() {
  printf 'PASS %s\n' "$1"
}

warn() {
  printf 'WARN %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

check_path() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    pass "$label: $path"
  else
    fail "$label missing: $path"
  fi
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  pass "macOS host detected"
else
  fail "Codex Usage Monitor requires macOS"
fi

if command -v swift >/dev/null 2>&1; then
  swift_version="$(swift --version 2>&1 | sed -n '/Apple Swift/p' | head -n 1)"
  if [[ -z "$swift_version" ]]; then
    swift_version="$(swift --version 2>&1 | head -n 1)"
  fi
  pass "$swift_version"
else
  fail "Swift toolchain not found"
fi

if command -v python3 >/dev/null 2>&1; then
  pass "$(python3 --version)"
else
  fail "python3 not found"
fi

check_path "CODEX_HOME" "$CODEX_HOME_PATH"
check_path "Usage database" "$USAGE_DB_PATH"
check_path "Logs database" "$LOGS_DB_PATH"

if find "$CODEX_HOME_PATH/sessions" "$CODEX_HOME_PATH/archived_sessions" \
  -name '*.jsonl' -type f -print -quit 2>/dev/null | grep -q .; then
  pass "Codex session JSONL files found"
else
  warn "No session JSONL files found yet; use local Codex first"
fi

audit_file="$(mktemp)"
if "$ROOT_DIR/script/audit_usage.py" --json >"$audit_file"; then
  token_count_events="$(python3 - "$audit_file" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("token_count_event_count", 0))
PY
)"
  if [[ "$token_count_events" -gt 0 ]]; then
    pass "token_count events found: $token_count_events"
  else
    warn "No token_count events found; rolling totals will be unavailable"
  fi
else
  fail "audit script failed"
fi
rm -f "$audit_file"

case "${1:-}" in
  --build)
    "$ROOT_DIR/script/build_and_run.sh" --build-only
    pass "app bundle build completed"
    ;;
  "")
    ;;
  *)
    printf 'usage: %s [--build]\n' "$0" >&2
    exit 2
    ;;
esac

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
