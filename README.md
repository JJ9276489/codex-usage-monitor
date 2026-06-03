# Codex Usage Monitor

A brutalist macOS desktop widget prototype for viewing local Codex token usage.

This is a local-only monitor. It does not call OpenAI APIs or send usage data anywhere.

The app reads Codex's local session logs and state database:

- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/archived_sessions/*.jsonl`
- `~/.codex/state_5.sqlite`

It shows:

- tokens used today
- tokens used in the last 5 hours
- tokens used in the last 7 and 30 days
- all-time local token totals
- latest observed 5-hour and 7-day Codex rate-limit usage, when Codex has logged a token count event
- recent Codex threads and their token counts
- manual refresh from the desktop widget or menu bar

It does **not** read `auth.json`, access tokens, or OpenAI credentials.

The first version runs as a menu bar app and opens a desktop-layer widget window. It is intentionally stark: dark material, monospaced type, high-contrast status tags, and compact metrics. It snaps its saved position to a small grid and refreshes local data every 5 seconds, but it is still a desktop-style widget window, not a WidgetKit extension yet.

## Usage Accuracy

Codex writes `token_count` events into local session JSONL files. This app uses those events as its primary source for token totals and rate-limit percentages.

For time-window totals, the app computes positive deltas between consecutive cumulative `total_token_usage.total_tokens` values per session. That avoids the inaccurate older approach of grouping whole thread totals by `updated_at`.

If no session `token_count` event is available, rolling totals stay at zero instead of falling back to inaccurate thread `updated_at` buckets. The all-time total still comes from Codex's local state database.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain from Xcode or Xcode Command Line Tools
- Codex installed and used locally at least once on the same Mac
- Local Codex files under `~/.codex`, or a custom `CODEX_HOME`

This is not a signed/notarized binary distribution yet. The supported public path is to clone the repo and build locally.

## Quick Start

```bash
git clone https://github.com/JJ9276489/codex-usage-monitor.git
cd codex-usage-monitor
./script/build_and_run.sh
```

## Build And Run

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM target, stages a local app bundle in `dist/`, and opens it as a menu bar app with the desktop widget visible.

Useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
./script/build_and_run.sh --build-only
```

## Install At Login

```bash
./script/install_login_item.sh
```

This builds the app, copies it to `~/Applications/CodexUsageMonitor.app`, and registers a user LaunchAgent so it opens when you log in.

If you use custom paths, set them while installing so the LaunchAgent keeps them:

```bash
CODEX_HOME=/path/to/.codex ./script/install_login_item.sh
CODEX_USAGE_DB=/path/to/state_5.sqlite ./script/install_login_item.sh
```

To uninstall:

```bash
./script/uninstall.sh
```

If SwiftPM fails before compiling source with a PackageDescription or SDK mismatch, the run script automatically falls back to direct `swiftc` compilation.

For a long-term SwiftPM fix, update or reinstall Xcode Command Line Tools, or install full Xcode and select it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Custom Database Path

Set `CODEX_USAGE_DB` before launch:

```bash
CODEX_USAGE_DB=/path/to/state_5.sqlite ./script/build_and_run.sh
```

Set `CODEX_HOME` to read a different Codex home folder:

```bash
CODEX_HOME=/path/to/.codex ./script/build_and_run.sh
```

## Privacy

The app reads local session `token_count` events for numeric usage. It also reads these `threads` table fields for recent-thread labels:

- thread id
- title
- source
- model
- `tokens_used`
- `updated_at`

Thread titles may appear in the menu UI. Session JSONL files can contain conversation/tool content, but the app only parses `token_count` event fields and does not transmit file contents. Do not publish screenshots if your thread titles include private information.

## Public Compatibility

This project depends on Codex's local file formats, especially session JSONL `token_count` events and `state_5.sqlite`. Those are not a public stability contract, so a future Codex release can break the reader. If the widget shows zeros or stale limit bars after a Codex update, check whether new `token_count` events are still being written.

The widget will not work for people who only use ChatGPT in a browser, people without local Codex session files, or non-macOS systems.

## Roadmap

- Add a proper signed app bundle.
- Add an optional WidgetKit extension if a stable usage feed is available.
- Add a provider interface for Enterprise Analytics API usage.
- Add a stable integration for live remaining limits if OpenAI exposes one.

## License

MIT
