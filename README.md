# Codex Usage Monitor

A brutalist macOS desktop widget prototype for viewing local Codex token usage.

The app reads Codex's local state database at `~/.codex/state_5.sqlite` and shows:

- tokens used today
- tokens used in the last 7 and 30 days
- all-time local token totals
- recent Codex threads and their token counts

It does **not** read `auth.json`, access tokens, or OpenAI credentials.

The first version runs as a menu bar app and opens a persistent floating desktop-style widget. It is intentionally stark: black panel, hard borders, monospaced type, high-contrast status tags, and no soft chrome. It is a desktop-style widget window, not a WidgetKit extension yet.

## Current Limitation

Codex exposes live context and rate-limit information through the interactive `/status` command, but this project does not currently have a stable machine-readable source for exact remaining ChatGPT/Codex quota. Until OpenAI exposes that as an API or local status feed, this app treats "remaining quota" as unavailable rather than guessing.

Business and Enterprise users may have access to Codex analytics APIs, but those are workspace analytics surfaces and can lag. They are not the same as a live personal remaining-limit meter.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Codex installed and used locally at least once

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

## Privacy

The app reads only the local `threads` table fields needed for usage totals:

- thread id
- title
- source
- model
- `tokens_used`
- `updated_at`

Thread titles may appear in the menu UI. Do not publish screenshots if your thread titles include private information.

## Roadmap

- Add a proper signed app bundle.
- Add an optional WidgetKit extension if a stable usage feed is available.
- Add a provider interface for Enterprise Analytics API usage.
- Add a stable integration for live remaining limits if OpenAI exposes one.

## License

MIT
