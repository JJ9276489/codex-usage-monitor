# Usage Accuracy

Codex Usage Monitor is designed to be conservative: it prefers showing partial-data warnings over inventing totals from thread timestamps.

## Sources

Rolling token totals:

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/archived_sessions/*.jsonl`
- recent `rollout_path` entries from `~/.codex/state_5.sqlite`

All-time token total:

- `~/.codex/state_5.sqlite`, `threads.tokens_used`

Rate limits:

- newest usable `rate_limits` payload from local `token_count` session events
- newest usable Codex response-header payload from `~/.codex/logs_2.sqlite`

## Rolling Windows

For each session file, the reader processes `event_msg` records whose payload type is `token_count`.

The first observed event in a file uses:

```text
payload.info.last_token_usage.total_tokens
```

Subsequent events use positive deltas between consecutive:

```text
payload.info.total_token_usage.total_tokens
```

That prevents two common overcounts:

- Reopened long-running threads counting their cumulative total as fresh usage
- Duplicate rate-limit-only events adding tokens again

Negative deltas are treated as a reset and use `last_token_usage` when available. Zero deltas do not add tokens.

## Limit Payloads

The app only displays a rate-limit payload when it contains a real primary or secondary window. Empty payloads such as `limit_id: "premium"` with `primary: null` and `secondary: null` are ignored so they cannot overwrite useful 5-hour/7-day limit data.

The widget marks limits as stale when their reset time has passed relative to the snapshot time.

## Diagnostics

The menu shows:

- session file count
- `token_count` event count
- failed session file count, when non-zero
- missing `last_token_usage` event count, when non-zero

If the app cannot read every local source precisely, the desktop widget shows `PARTIAL LOCAL` instead of silently presenting the number as complete.

## Known Limits

- The app updates after Codex writes `token_count` events, not continuously mid-response.
- All-time totals depend on Codex flushing `state_5.sqlite`.
- The local Codex file formats are not an official stability contract.
- The app cannot track ChatGPT browser usage or Codex usage from another machine unless that machine's local Codex files are used.
