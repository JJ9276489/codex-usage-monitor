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
    return parser.parse_args()


def timestamp(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def recent_paths_from_db(database_path, since_epoch):
    if not database_path.exists():
        return [], None

    connection = sqlite3.connect(database_path)
    try:
        rows = connection.execute(
            """
            SELECT rollout_path
            FROM threads
            WHERE updated_at >= ?
              AND rollout_path != ''
            GROUP BY rollout_path
            ORDER BY MAX(updated_at) DESC
            """,
            (int(since_epoch),),
        ).fetchall()
        all_time = connection.execute(
            "SELECT COALESCE(SUM(tokens_used), 0) FROM threads"
        ).fetchone()[0]
    finally:
        connection.close()

    paths = [Path(row[0]) for row in rows if row[0] and Path(row[0]).exists()]
    return paths, int(all_time)


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
    return sorted({path.expanduser().resolve() for path in paths}, key=lambda p: str(p))


def token_count_events(path):
    previous_total = None
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
            if observed_at is None or total_tokens is None:
                continue

            total_tokens = int(total_tokens)
            if previous_total is None:
                increment = total_tokens
            else:
                increment = max(total_tokens - previous_total, 0)
            previous_total = total_tokens

            yield {
                "timestamp": observed_at,
                "increment": increment,
                "rate_limits": payload.get("rate_limits"),
            }


def audit(codex_home, database_path):
    now = time.time()
    today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    five_hours_ago = now - (5 * 60 * 60)
    seven_days_ago = now - (7 * 24 * 60 * 60)
    thirty_days_ago = now - (30 * 24 * 60 * 60)

    db_paths, all_time = recent_paths_from_db(database_path, thirty_days_ago)
    fs_paths = recent_paths_from_filesystem(codex_home, thirty_days_ago)
    paths = unique_sorted(db_paths + fs_paths)

    totals = {
        "tokens_last_5_hours": 0,
        "tokens_today": 0,
        "tokens_last_7_days": 0,
        "tokens_last_30_days": 0,
    }
    latest_limit = None
    event_count = 0

    for path in paths:
        for event in token_count_events(path):
            event_count += 1
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

    return {
        "codex_home": str(codex_home),
        "database_path": str(database_path),
        "session_file_count": len(paths),
        "token_count_event_count": event_count,
        **totals,
        "tokens_all_time_db": all_time,
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
    result = audit(codex_home, database_path)

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return

    print(f"Codex home: {result['codex_home']}")
    print(f"Usage DB: {result['database_path']}")
    print(f"Session files: {result['session_file_count']}")
    print(f"token_count events: {result['token_count_event_count']}")
    print(f"5h: {compact(result['tokens_last_5_hours'])}")
    print(f"today: {compact(result['tokens_today'])}")
    print(f"7d: {compact(result['tokens_last_7_days'])}")
    print(f"30d: {compact(result['tokens_last_30_days'])}")
    print(f"all-time DB: {compact(result['tokens_all_time_db'])}")

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
