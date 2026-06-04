# Troubleshooting

Run these first:

```bash
./script/doctor.sh
./script/audit_usage.py
```

## Widget Shows Zero Tokens

Likely causes:

- Local Codex has not written any `token_count` events yet.
- `CODEX_HOME` points at the wrong folder.
- You only use ChatGPT in a browser, not local Codex.

Check:

```bash
find ~/.codex/sessions ~/.codex/archived_sessions -name '*.jsonl' -type f | head
./script/audit_usage.py --json
```

## Limit Bars Show Stale

The token totals can still be accurate while limit bars are stale. Limit bars need a recent usable `rate_limits` payload with reset times.

Check:

```bash
./script/audit_usage.py --json
```

If `latest_limit` is `null`, Codex has not logged a usable local rate-limit payload yet.

## Widget Says Partial Local

The app found some local data, but one or more accuracy diagnostics failed:

- a session file could not be read
- no `token_count` events were found
- some events omitted `last_token_usage`

Open the menu bar popover for the exact warning.

## Login Item Does Not Start

Reinstall the LaunchAgent:

```bash
./script/install_login_item.sh
launchctl print "gui/$(id -u)/io.github.jj9276489.codex-usage-monitor"
```

Startup logs are written to:

```text
~/Library/Logs/CodexUsageMonitor.out.log
~/Library/Logs/CodexUsageMonitor.err.log
```

## SwiftPM Manifest Fails

The build script automatically falls back to direct `swiftc` compilation. If you want SwiftPM itself fixed, reinstall or update Xcode Command Line Tools, or select full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Reset Everything

```bash
./script/uninstall.sh
./script/install_login_item.sh
```
