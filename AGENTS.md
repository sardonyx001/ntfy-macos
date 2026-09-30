# AGENTS.md

This is jam's local fork of [laurentftech/ntfy-macos](https://github.com/laurentftech/ntfy-macos), maintained here instead of via the Homebrew formula (`brew uninstall`d 2026-09-30). Treat this repo as the source of truth for what's actually running on his machine.

## Why this fork exists

The stock app connects via a chunked/SSE streaming GET (`/{topic}/json`). On jam's corporate network, the Zscaler TLS-inspection proxy silently black-holes long-lived streaming HTTP responses — the connection succeeds (TLS handshake, 200-equivalent) but zero bytes ever arrive, indefinitely, with no error. This reproduced identically against `ntfy.sh` directly and against a reverse proxy on his own VPS (`p.jamell.dev/ntfy.sh`), ruling out anything ntfy.sh-specific. A raw WebSocket upgrade through the same corporate egress passes through untouched — Zscaler's buffering appears to be protocol-specific (streaming GET) rather than host-specific.

## Patches made (in `git log`, all TDD: test written first, confirmed RED, then GREEN)

1. **`Sources/NtfyClient.swift`** — connect via WebSocket (`/{topic}/ws`) instead of the chunked `/{topic}/json` GET. This is the actual fix for the above.
2. **`Sources/NtfyClient.swift` `buildConnectURL()`** — fixed a path-clobbering bug: `URLComponents.path = "/\(topics)/ws"` replaced the entire path instead of appending, which silently dropped the `/ntfy.sh` prefix needed when `serverURL` is itself a proxy with a path (e.g. `https://p.jamell.dev/ntfy.sh`). Pre-existing bug in upstream too, just never triggered because `serverURL` was always a bare host before.
3. **`Sources/NotificationManager.swift` `createAttachment`** — removed a `FileManager.removeItem` called immediately after creating the `UNNotificationAttachment`. `UNUserNotificationCenter` moves the attachment file into its own data store lazily, when the notification is actually delivered (`center.add(request:)`), not at `UNNotificationAttachment` init time. Deleting the source file immediately raced that later move and silently killed notification delivery ("Failed to move attachment file into data store"). Pre-existing upstream bug.
4. **`Sources/NotificationManager.swift`** — added `shouldShowContentWindow` + `showContentWindow`: tapping a notification with no explicit click target (no topic `click_url`, no message `Click:` header) now opens a native window with the full title/body (selectable + Copy button) instead of opening a browser tab to the raw ntfy topic URL. Explicit click targets (config `click_url` or message `Click:` header) still open in the browser as before — this only changes the *fallback* path.

## Deferred, not built

Discussed hosting message content as a real webpage on `p.jamell.dev` (via jam's Hermes agent on the VPS) instead of the native window — would give copy + image download/preview for free via the browser, closer to the full ntfy rich-message feature surface (attachments, markdown rendering). Explicitly parked for later, not started. If picked back up, open questions to resolve first: URL unguessability (UUID vs short slug), retention window (match ntfy.sh's ~12h cache vs. keep forever), and whether the native window stays as a fallback if the VPS call fails.

## Build / install / rebuild loop

No `swift`/`swiftly` toolchain is selected by default on this machine — must use Xcode's toolchain explicitly:

```bash
export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
cd ~/wip/ntfy-macos

xcrun swift test              # full suite — keep this green before rebuilding
./build-app.sh                # builds + ad-hoc signs .build/release/ntfy-macos.app

launchctl bootout gui/$(id -u)/com.laurentftech.ntfy-macos
sudo cp -r .build/release/ntfy-macos.app /Applications/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.laurentftech.ntfy-macos.plist
```

Bundle ID (`com.laurentftech.ntfy-macos`) is unchanged from upstream, so macOS notification permission carries over across reinstalls — no need to re-grant it.

- Config: `~/.config/ntfy-macos/config.yml` — server url is `https://p.jamell.dev/ntfy.sh` (proxied around the Zscaler issue above), not `https://ntfy.sh` directly.
- LaunchAgent: `~/Library/LaunchAgents/com.laurentftech.ntfy-macos.plist` (replaces the old Homebrew-managed `homebrew.mxcl.ntfy-macos.plist`).
- App logs: `~/.local/share/ntfy-macos/logs/ntfy-macos.log`.
- Crash reports (if any): `~/Library/Logs/DiagnosticReports/ntfy-macos-*.ips`.

## Ground rules for changes here

- TDD, no exceptions: write the failing test, confirm it fails for the right reason, then implement. This repo already has 188+ passing tests (`swift test`) — keep it green.
- Prefer the smallest diff that fixes the actual root cause over patching the symptom at a call site — this repo's own bugs so far (path-clobbering, premature file deletion) were both "smaller fix, one call site" traps that had the same root cause reachable from multiple places.
- When touching `NotificationManager.swift`'s AppKit/UNUserNotificationCenter code, remember delegate callbacks aren't guaranteed to run on the main thread — this file uses `DispatchQueue.main.async` + informal main-thread discipline rather than `@MainActor`, matching the existing (pre-fork) style. Don't mix in `@MainActor` on new code here; it fights the non-isolated dispatch closures already in place and turns into actor-isolation warnings for no benefit.
