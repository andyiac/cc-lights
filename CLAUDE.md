# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `make build` — Build all targets (debug)
- `make test` — Run all tests (`swift test`)
- `make run` — Run the menu bar app for development
- `make bundle` — Release build + create `CC Lights.app` and `cc-lights` CLI in `dist/`
- `make dmg` — bundle + create DMG installer in `dist/`
- `make install` — bundle + copy app to `/Applications`
- `make clean` — Remove `.build/` and `dist/`
- `swift test --filter <test-name>` — Run a specific test
- `swift run cc-lights -- <args>` — Run CLI from source (e.g. `swift run cc-lights -- working --task "Build"`)

## Architecture

Three SPM targets, all macOS 11+:

- **StatusLightCore** (library) — State model (`StatusState`, `StatusPayload`) and file store (`StatusFileStore`). No AppKit dependency. Writes/reads per-session JSON files under `~/Library/Application Support/ClaudeCodeStatusLight/sessions/`.
- **ClaudeCodeStatusLight** (executable) — macOS menu bar AppKit app. Single-file at `Sources/ClaudeCodeStatusLight/main.swift` (~1860 lines). Contains: `AppDelegate`, `StatusBarController` (status items, animations, terminal focusing via AppleScript/cmux URL), `StatusFileMonitor` (kqueue directory watcher + cmux poller), `CmuxClaudeSessionStore`, `NotificationController`, `ClaudeCodeConfigChecker` (hook installer/config monitor), `LaunchAtLoginManager`. Preferences window at `Sources/ClaudeCodeStatusLight/Preferences.swift`.
- **CCLights** (executable) — CLI (`Sources/CCLights/main.swift`) called by Claude Code hooks. Argument parsing, TTY resolution from process tree, session ID resolution from env vars. Communicates with the app exclusively through JSON files — no network, no XPC.

## Key design decisions

- **File-based IPC** — CLI writes status JSON files to `~/Library/Application Support/ClaudeCodeStatusLight/sessions/`. The app monitors this directory via kqueue (`DispatchSourceFileSystemObject`). No background server.
- **Terminal focusing** — Three strategies: TTY matching (Terminal.app, iTerm2 via AppleScript), working directory matching (Ghostty), and `cmux://` deep links (cmux).
- **Claude Code hooks** — On first launch, the app copies its bundled CLI to a stable path under Application Support and writes hooks into `~/.claude/settings.json` with a backup. Hooks are idempotent and auto-repaired on each launch.
- **Animation** — `working` state uses smooth cosine pulsing (0.3-1.0 alpha, 1s period). `waiting` transitions from solid yellow to slow pulse after 30s. `error` flashes 3 times on transition.
- **cmux integration** — Polls `~/.cmuxterm/claude-hook-sessions.json` every 2s and merges with file store sessions. Also reads `CMUX_*` env vars.
- **Status priority** — `error` > `waiting` > `working` > `idle` > `offline` for aggregate display.
- **All UI text is Chinese** — display names, tooltips, menus, alerts are all in Chinese.

## Testing

Tests live in `Tests/StatusLightCoreTests/`. Uses `XCTest`. Tests cover payload JSON round-tripping, legacy decoding, file store merge semantics, stale-pruning, and aggregate priority. No UI tests.

## Release

GitHub Actions workflow in `.github/workflows/release.yml`. Triggered by tag `v*.*.*` or workflow_dispatch. Runs `make dmg` on `macos-14`, publishes to GitHub Releases. The `Makefile` builds a universal binary (arm64 + x86_64).
