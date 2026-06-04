# Security And Privacy

Codex Usage Monitor is a local-only macOS utility.

## Data Read

The app reads:

- local Codex session JSONL files for numeric `token_count` events
- local Codex SQLite state for all-time totals and recent thread labels
- local Codex logs for rate-limit headers

The app does not read:

- `auth.json`
- access tokens
- OpenAI API keys
- browser cookies

The app does not transmit usage data.

## Sensitive UI

Recent thread titles may appear in the menu bar popover. Session JSONL files can contain conversation/tool content, but the app only parses token-count and rate-limit fields.

Do not publish screenshots if your thread titles, desktop, or widget placement reveal private information.

## Reporting Issues

Open a GitHub issue with:

- macOS version
- Codex Usage Monitor commit or release
- output from `./script/doctor.sh`
- output from `./script/audit_usage.py`, with paths or thread titles redacted if needed

Do not attach Codex session JSONL files unless you have reviewed them for private content.
