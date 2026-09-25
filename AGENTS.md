# Working on ccid

ccid is a macOS menu bar app and command-line tool that finds Claude Code session IDs. It only reads: it never writes to Claude's files and never opens a network connection.

## Layout

- `Sources/CCIDCore`: finding sessions, reading transcripts, ranking search results, formatting. No AppKit, and covered by `Tests/CCIDCoreTests`.
- `Sources/CCIDApp`: the panel (SwiftUI in a non-activating `NSPanel`), the menu bar item and the hotkey.
- `Sources/ccid`: the command-line tool.
- `Bundle`: `Info.plist`, the icon and the localized strings. `scripts/build-app.sh` puts them together into `dist/ccid.app`.

## Commands

```bash
swift test
swift run ccid                   # the command-line tool
CCID_DEMO=1 swift run ccid       # with made-up sessions
scripts/build-app.sh             # dist/ccid.app
```

## Rules

- No dependencies beyond Apple's frameworks.
- Stay read-only and offline.
- Every string people see is localized. The keys are the English text, so add the Chinese to `Bundle/zh-Hans.lproj/Localizable.strings` in the same change.
- Screenshots use demo mode, never real sessions.
- Tests build their own sessions with `Tests/CCIDCoreTests/Fixture.swift` and never read the real home folder.
- Keep building on macOS 14 and Xcode 16: wrap Liquid Glass in `#if compiler(>=6.2)` and `if #available(macOS 26.0, *)`.
