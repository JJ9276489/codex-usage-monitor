#!/usr/bin/env python3
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "script" / "audit_usage.py"


def epoch(year, month, day, hour=0, minute=0, second=0):
    return datetime(year, month, day, hour, minute, second).astimezone().timestamp()


def iso(epoch_value, fractional=True):
    value = datetime.fromtimestamp(epoch_value, tz=timezone.utc)
    if fractional:
        return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def token_count_line(
    epoch_value,
    total_tokens,
    last_tokens=None,
    primary=None,
    secondary=None,
    limit_id="codex",
    plan_type="plus",
    fractional=True,
    include_last_usage=True,
):
    last_tokens = total_tokens if last_tokens is None else last_tokens
    info = {
        "total_token_usage": {
            "total_tokens": total_tokens,
        },
    }
    if include_last_usage:
        info["last_token_usage"] = {
            "total_tokens": last_tokens,
        }

    payload = {
        "type": "event_msg",
        "timestamp": iso(epoch_value, fractional=fractional),
        "payload": {
            "type": "token_count",
            "info": info,
        },
    }

    if primary is not None or secondary is not None:
        payload["payload"]["rate_limits"] = {
            "limit_id": limit_id,
            "plan_type": plan_type,
            "primary": primary,
            "secondary": secondary,
            "credits": {
                "has_credits": False,
                "unlimited": False,
                "balance": "0",
            },
            "rate_limit_reached_type": None,
        }

    return json.dumps(payload, separators=(",", ":"))


def empty_limit_line(epoch_value, total_tokens, last_tokens=0):
    payload = json.loads(token_count_line(epoch_value, total_tokens, last_tokens=last_tokens))
    payload["payload"]["rate_limits"] = {
        "limit_id": "premium",
        "plan_type": "plus",
        "primary": None,
        "secondary": None,
        "credits": {
            "has_credits": False,
            "unlimited": False,
            "balance": "0",
        },
        "rate_limit_reached_type": None,
    }
    return json.dumps(payload, separators=(",", ":"))


def write_lines(path, lines):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def create_state_db(path, rows):
    connection = sqlite3.connect(path)
    try:
        connection.execute(
            """
            CREATE TABLE threads (
              id TEXT PRIMARY KEY,
              rollout_path TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              tokens_used INTEGER NOT NULL,
              title TEXT NOT NULL DEFAULT '',
              source TEXT NOT NULL DEFAULT '',
              model TEXT
            )
            """
        )
        connection.executemany(
            """
            INSERT INTO threads (id, rollout_path, updated_at, tokens_used, title, source, model)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        connection.commit()
    finally:
        connection.close()


def run_audit(codex_home, usage_db, now_epoch):
    environment = os.environ.copy()
    environment["CODEX_HOME"] = str(codex_home)
    environment["CODEX_USAGE_DB"] = str(usage_db)
    result = subprocess.run(
        [str(AUDIT), "--json", "--now-epoch", str(now_epoch)],
        cwd=ROOT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return json.loads(result.stdout)


def assert_equal(actual, expected, label):
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def main():
    now = epoch(2026, 6, 3, 12)
    today_7 = epoch(2026, 6, 3, 7)
    today_9 = epoch(2026, 6, 3, 9)
    today_10 = epoch(2026, 6, 3, 10)
    six_days_ago = epoch(2026, 5, 28, 12)
    two_days_ago = epoch(2026, 6, 1, 12)
    thirty_one_days_ago = epoch(2026, 5, 3, 12)
    eight_days_ago = epoch(2026, 5, 26, 12)

    with tempfile.TemporaryDirectory(prefix="codex-usage-fixture-") as temp:
        root = Path(temp)
        codex_home = root / ".codex"
        usage_db = codex_home / "state_5.sqlite"
        sessions = codex_home / "sessions" / "2026" / "06" / "03"
        archived = codex_home / "archived_sessions"
        codex_home.mkdir(parents=True)

        active_path = sessions / "rollout-active.jsonl"
        discovered_by_db_path = archived / "rollout-db.jsonl"
        discovered_by_filesystem_path = sessions / "rollout-filesystem-only.jsonl"
        unreadable_candidate_path = sessions / "unreadable-candidate.jsonl"
        missing_path = sessions / "missing.jsonl"

        write_lines(
            active_path,
            [
                token_count_line(today_7, 50_100, last_tokens=100),
                token_count_line(today_9, 50_180, last_tokens=80),
                token_count_line(today_9 + 1800, 50_180, include_last_usage=False),
                token_count_line(
                    today_10,
                    50_250,
                    last_tokens=70,
                    primary={"used_percent": 33.0, "window_minutes": 300, "resets_at": int(now + 1000)},
                    secondary={
                        "used_percent": 44.0,
                        "window_minutes": 10080,
                        "resets_at": int(now + 2000),
                    },
                    fractional=False,
                ),
                empty_limit_line(today_10 + 60, 50_250),
            ],
        )
        write_lines(
            discovered_by_db_path,
            [
                token_count_line(six_days_ago, 200_000, last_tokens=1_000),
                token_count_line(two_days_ago, 200_300, last_tokens=300),
            ],
        )
        write_lines(
            discovered_by_filesystem_path,
            [
                token_count_line(thirty_one_days_ago, 1_005_000, last_tokens=5_000),
                token_count_line(eight_days_ago, 1_005_600, last_tokens=600),
                token_count_line(six_days_ago, 1_005_900, last_tokens=300),
            ],
        )
        unreadable_candidate_path.mkdir(parents=True)

        create_state_db(
            usage_db,
            [
                ("active", str(active_path), int(today_10), 250, "active", "codex", "gpt-test"),
                ("db", str(discovered_by_db_path), int(two_days_ago), 1300, "db", "codex", "gpt-test"),
                (
                    "unreadable",
                    str(unreadable_candidate_path),
                    int(today_10),
                    0,
                    "unreadable",
                    "codex",
                    "gpt-test",
                ),
                ("missing", str(missing_path), int(today_10), 999999, "missing", "codex", "gpt-test"),
            ],
        )

        result = run_audit(codex_home, usage_db, now)

        assert_equal(result["session_file_count"], 5, "session_file_count")
        assert_equal(result["failed_session_file_count"], 2, "failed_session_file_count")
        assert_equal(result["token_count_event_count"], 10, "token_count_event_count")
        assert_equal(result["missing_last_usage_event_count"], 1, "missing_last_usage_event_count")
        assert_equal(result["tokens_last_5_hours"], 250, "tokens_last_5_hours")
        assert_equal(result["tokens_today"], 250, "tokens_today")
        assert_equal(result["tokens_last_7_days"], 1850, "tokens_last_7_days")
        assert_equal(result["tokens_last_30_days"], 2450, "tokens_last_30_days")
        assert_equal(result["tokens_all_time_db"], 1001549, "tokens_all_time_db")
        assert_equal(result["tokens_all_time_reconciled"], 2256449, "tokens_all_time_reconciled")
        assert_equal(
            result["tokens_all_time_reconciled_delta"],
            1254900,
            "tokens_all_time_reconciled_delta",
        )
        assert_equal(
            result["latest_limit"]["rate_limits"]["primary"]["used_percent"],
            33.0,
            "latest primary percent",
        )
        assert_equal(
            result["latest_limit"]["rate_limits"]["secondary"]["used_percent"],
            44.0,
            "latest secondary percent",
        )
        assert_equal(result["latest_limit"]["rate_limits"]["limit_id"], "codex", "latest limit id")

    print("usage accuracy fixture tests passed")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"usage accuracy fixture tests failed: {error}", file=sys.stderr)
        sys.exit(1)
