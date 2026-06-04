#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Audit Codex token usage directly from local token_count events."
    )
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--codex-home", default=os.environ.get("CODEX_HOME"))
    parser.add_argument("--usage-db", default=os.environ.get("CODEX_USAGE_DB"))
    parser.add_argument(
        "--now-epoch",
        type=float,
        default=None,
        help="override the current epoch time, primarily for deterministic tests",
    )
    return parser.parse_args()


def timestamp(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def int_value(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def has_limit_window(window):
    if not isinstance(window, dict):
        return False
    return any(key in window for key in ("used_percent", "window_minutes", "resets_at"))


def usable_rate_limits(rate_limits):
    if not isinstance(rate_limits, dict):
        return None
    if has_limit_window(rate_limits.get("primary")) or has_limit_window(rate_limits.get("secondary")):
        return rate_limits
    return None


def normalized_path(path):
    return path.expanduser().resolve()


def session_index_from_db(database_path):
    if not database_path.exists():
        return {}, 0, None

    connection = sqlite3.connect(database_path)
    try:
        rows = connection.execute(
            """
            SELECT rollout_path, COALESCE(SUM(tokens_used), 0)
            FROM threads
            WHERE rollout_path IS NOT NULL
              AND rollout_path != ''
            GROUP BY rollout_path
            ORDER BY MAX(updated_at) DESC
            """,
        ).fetchall()
        unlinked_tokens = connection.execute(
            """
            SELECT COALESCE(SUM(tokens_used), 0)
            FROM threads
            WHERE rollout_path IS NULL
               OR rollout_path = ''
            """
        ).fetchone()[0]
        all_time = connection.execute(
            "SELECT COALESCE(SUM(tokens_used), 0) FROM threads"
        ).fetchone()[0]
    finally:
        connection.close()

    path_tokens = {}
    for raw_path, tokens in rows:
        if not raw_path:
            continue
        path = normalized_path(Path(raw_path))
        path_tokens[path] = path_tokens.get(path, 0) + int(tokens)

    return path_tokens, int(unlinked_tokens), int(all_time)


def recent_paths_from_filesystem(codex_home, since_epoch):
    paths = []
    roots = [
        codex_home / "sessions",
        codex_home / "archived_sessions",
    ]

    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*.jsonl"):
            try:
                if path.stat().st_mtime >= since_epoch:
                    paths.append(path)
            except OSError:
                continue

    return paths


def unique_sorted(paths):
    return sorted({normalized_path(path) for path in paths}, key=lambda p: str(p))


def read_session_usage(path):
    previous_total = None
    latest_total = None
    events = []

    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            if '"token_count"' not in line or '"total_token_usage"' not in line:
                continue

            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            payload = record.get("payload") or {}
            if record.get("type") != "event_msg" or payload.get("type") != "token_count":
                continue

            observed_at = timestamp(record.get("timestamp"))
            total_tokens = (
                ((payload.get("info") or {}).get("total_token_usage") or {}).get("total_tokens")
            )
            last_tokens = (
                ((payload.get("info") or {}).get("last_token_usage") or {}).get("total_tokens")
            )
            total_tokens = int_value(total_tokens)
            last_tokens = int_value(last_tokens)
            if observed_at is None or total_tokens is None:
                continue
            latest_total = total_tokens

            if previous_total is None:
                increment = last_tokens if last_tokens is not None else total_tokens
            else:
                delta = total_tokens - previous_total
                if delta > 0:
                    increment = delta
                elif delta < 0:
                    increment = last_tokens if last_tokens is not None else total_tokens
                else:
                    increment = 0
            increment = max(increment, 0)
            previous_total = total_tokens

            events.append(
                {
                    "timestamp": observed_at,
                    "increment": increment,
                    "rate_limits": usable_rate_limits(payload.get("rate_limits")),
                    "missing_last_usage": last_tokens is None,
                }
            )

    return {
        "events": events,
        "latest_total_tokens": latest_total,
    }


def audit(codex_home, database_path, now=None):
    now = time.time() if now is None else now
    today_start = datetime.fromtimestamp(now).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).timestamp()
    five_hours_ago = now - (5 * 60 * 60)
    seven_days_ago = now - (7 * 24 * 60 * 60)
    thirty_days_ago = now - (30 * 24 * 60 * 60)

    db_path_tokens, db_unlinked_tokens, all_time_db = session_index_from_db(database_path)
    fs_paths = recent_paths_from_filesystem(codex_home, thirty_days_ago)
    paths = unique_sorted(list(db_path_tokens.keys()) + fs_paths)

    totals = {
        "tokens_last_5_hours": 0,
        "tokens_today": 0,
        "tokens_last_7_days": 0,
        "tokens_last_30_days": 0,
    }
    tokens_all_time_reconciled = db_unlinked_tokens
    latest_limit = None
    event_count = 0
    missing_last_usage_event_count = 0
    failed_session_file_count = 0

    for path in paths:
        database_tokens = db_path_tokens.get(path)
        try:
            usage = read_session_usage(path)
            tokens_all_time_reconciled += max(
                usage["latest_total_tokens"] or 0,
                database_tokens or 0,
            )

            for event in usage["events"]:
                event_count += 1
                if event["missing_last_usage"]:
                    missing_last_usage_event_count += 1
                observed_at = event["timestamp"]
                increment = event["increment"]
                if increment:
                    if observed_at >= five_hours_ago:
                        totals["tokens_last_5_hours"] += increment
                    if observed_at >= today_start:
                        totals["tokens_today"] += increment
                    if observed_at >= seven_days_ago:
                        totals["tokens_last_7_days"] += increment
                    if observed_at >= thirty_days_ago:
                        totals["tokens_last_30_days"] += increment

                if event["rate_limits"] and (
                    latest_limit is None or observed_at > latest_limit["observed_at_epoch"]
                ):
                    latest_limit = {
                        "observed_at_epoch": observed_at,
                        "observed_at": datetime.fromtimestamp(observed_at).isoformat(timespec="seconds"),
                        "rate_limits": event["rate_limits"],
                    }
        except OSError:
            failed_session_file_count += 1
            tokens_all_time_reconciled += database_tokens or 0

    return {
        "codex_home": str(codex_home),
        "database_path": str(database_path),
        "session_file_count": len(paths),
        "failed_session_file_count": failed_session_file_count,
        "token_count_event_count": event_count,
        "missing_last_usage_event_count": missing_last_usage_event_count,
        **totals,
        "tokens_all_time_db": all_time_db,
        "tokens_all_time_reconciled": tokens_all_time_reconciled,
        "tokens_all_time_reconciled_delta": (
            None if all_time_db is None else tokens_all_time_reconciled - all_time_db
        ),
        "latest_limit": latest_limit,
    }


def compact(value):
    if value is None:
        return "unknown"
    if abs(value) >= 1_000_000_000:
        return f"{value / 1_000_000_000:.1f}B"
    if abs(value) >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if abs(value) >= 1_000:
        return f"{value / 1_000:.1f}K"
    return str(value)


def main():
    args = parse_args()
    codex_home = Path(args.codex_home or Path.home() / ".codex").expanduser()
    database_path = Path(args.usage_db).expanduser() if args.usage_db else codex_home / "state_5.sqlite"
    result = audit(codex_home, database_path, now=args.now_epoch)

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return

    print(f"Codex home: {result['codex_home']}")
    print(f"Usage DB: {result['database_path']}")
    print(f"Session files: {result['session_file_count']}")
    if result["failed_session_file_count"]:
        print(f"failed session files: {result['failed_session_file_count']}")
    print(f"token_count events: {result['token_count_event_count']}")
    if result["missing_last_usage_event_count"]:
        print(f"missing last_token_usage events: {result['missing_last_usage_event_count']}")
    print(f"5h: {compact(result['tokens_last_5_hours'])}")
    print(f"today: {compact(result['tokens_today'])}")
    print(f"7d: {compact(result['tokens_last_7_days'])}")
    print(f"30d: {compact(result['tokens_last_30_days'])}")
    print(f"all-time: {compact(result['tokens_all_time_reconciled'])}")
    if result["tokens_all_time_db"] != result["tokens_all_time_reconciled"]:
        delta = result["tokens_all_time_reconciled_delta"]
        delta_text = "no DB baseline" if delta is None else f"{delta:+d} reconciled"
        print(
            "all-time DB: "
            f"{compact(result['tokens_all_time_db'])} "
            f"({delta_text})"
        )

    latest_limit = result["latest_limit"]
    if latest_limit:
        limits = latest_limit["rate_limits"]
        print(f"latest limit seen: {latest_limit['observed_at']}")
        print(f"primary: {limits.get('primary')}")
        print(f"secondary: {limits.get('secondary')}")
        print(f"plan: {limits.get('plan_type')} / {limits.get('limit_id')}")
    else:
        print("latest limit: none")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"audit failed: {error}", file=sys.stderr)
        sys.exit(1)
