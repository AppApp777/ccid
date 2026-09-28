# Changelog

## 1.0.2 · 2026-09-28

- The panel now labels Return correctly as “Copy Claude Link,” matching the `claude://threads/<session-id>` value it copies.
- The About panel and README hero now lead with the handoff use case: find a Claude Code session and give it to another AI agent to continue.

## 1.0.1 · 2026-09-28

- Pressing Return now copies Claude sessions as `claude://threads/<session-id>`, so the source is explicit when the link is handed to Codex or another agent.
- `ccid -c` copies the same Claude deep-link form; `ccid -1` still prints the raw session ID for scripts.
- The context menu keeps separate actions for copying the Claude link, the raw ID, or the `claude --resume` command.

## 1.0.0 · 2026-09-25

The first release.

- A menu bar panel that opens with <kbd>⌃</kbd><kbd>⌘</kbd><kbd>I</kbd>, filters sessions by title, folder, pinyin, or what you last said, and copies the ID with <kbd>↩</kbd>.
- <kbd>⌘</kbd><kbd>↩</kbd> searches every transcript for a phrase and shows who said it.
- The `ccid` command-line tool, with `--json` for scripts.
- Liquid Glass on macOS 26. Runs on macOS 14 and later, on Apple silicon and Intel.
- English and Simplified Chinese.