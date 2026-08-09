<div align="center">

# CC Lights

### Traffic lights for Claude Code, Codex, and OpenCode in your menu bar — glance to see if each session is working, waiting, or errored; click to jump straight there

<img src="Resources/AppIcon.png" width="120" alt="CC Lights — AI Coding Status Light for macOS" />

[![Platform: macOS 11+](https://img.shields.io/badge/platform-macOS%2011%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![Menu bar app](https://img.shields.io/badge/type-menu%20bar%20app-brightgreen)](#features)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-8A2BE2)](https://docs.anthropic.com/en/docs/claude-code)
[![Also works with Codex & OpenCode](https://img.shields.io/badge/also-Codex%20%26%20OpenCode-blue)](#integrating-with-coding-agents)
[![Download .dmg](https://img.shields.io/badge/download-.dmg-blue?logo=apple&logoColor=white)](https://github.com/andyiac/cc-lights/releases/latest)

**English** · [中文](README.zh-CN.md)

</div>

**Claude Code Status Light** (**CC Lights**) is a lightweight **macOS menu bar app** that shows the live status of one or more **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)**, **[Codex](https://developers.openai.com/codex/)** , and **[OpenCode](https://opencode.ai)** sessions as small, color-coded **traffic lights** — green while working or idle, yellow when it needs your input, red on error, and gray when offline.

Keep your AI coding agents running in your terminal or editor and stop switching back just to check on them: a glance at the menu bar tells you whether each session is **working, waiting for a decision, idle, offline, or blocked by an error**. **Click a light to jump straight to the exact session that needs you** — the right **Terminal.app, iTerm2, Ghostty, or cmux** tab, window, or pane. Status updates are driven by **Claude Code / Codex hooks** and the **OpenCode plugin** through a tiny bundled CLI, `cc-lights`.

<p align="center">
  <a href="https://www.youtube.com/watch?v=yQwQsnS-PSc">

  <img width="800" height="450" alt="Image" src="https://github.com/user-attachments/assets/556f9fb2-14b1-4435-911c-88f48b4a2f24" />
  
  </a>
</p>

## ⭐ One click back to the session that needs you

> [!TIP]
> **When a light turns yellow (waiting for your input) or red (error), just click it — CC Lights instantly brings that exact session to the front.** No more hunting through a dozen terminal windows and tabs to find which one is blocked on your approval.

- 🟡 **Waiting** → click the yellow light → you land right in the prompt asking for your approval, choice, or input.
- 🔴 **Error** → click the red light → jump straight to the session that failed.
- Works across **Terminal.app, iTerm2, Ghostty, and cmux** — the correct tab / window / pane is focused via TTY, working directory, or the `cmux://` deep link.

## Features

- **One-click jump to the right session** — click any light to focus its Terminal.app, iTerm2, Ghostty, or cmux tab / window / pane. Perfect for pouncing on a session that is waiting for your input.
- **Per-session status lights** — a separate menu bar light for every tracked Claude Code / Codex / OpenCode session.
- **Multi-agent support** — status driven by Claude Code hooks, Codex hooks, and the OpenCode plugin.
- **Traffic-light cues** — color and animation make the state obvious at a glance: breathing green while working, solid yellow when waiting for you, flashing red on error, gray when offline.
- **Native macOS notifications** — get notified the moment a session needs a decision or hits an API error.
- **Zero-config integration** — on first launch the app installs its `cc-lights` CLI and wires up the Claude Code hooks in `~/.claude/settings.json`, Codex hooks in `~/.codex/hooks.json`, and the OpenCode plugin in `~/.config/opencode/plugins/` automatically (each with a backup).
- **Preferences window** — a macOS System Settings / Shottr-style window for launch-at-login, light style, notifications, and integration.
- **Round or pixel-art lights** — pick a style in Preferences; the choice is remembered across launches.
- **Multi-session aware** — many parallel sessions each get their own light, with a priority-based summary (`error` > `waiting` > `working` > `idle` > `offline`).
- **Local-first** — session state lives in plain JSON files under Application Support; no background server, no account, no telemetry.
- **Tiny CLI** — `cc-lights` lets hooks or manual commands update session status.

## Status model

| | Light | State | Traffic-light cue | Meaning |
| :---: | --- | --- | --- | --- |
| ⚪ | Gray | `offline` | No active session | No tracked Claude Code / Codex / OpenCode session exists, or the sessions have exited. |
| 🟢 | Pulsing green | `working` | Green means the agent is running | The agent is actively running a task and does not need user input. |
| 🟡 | Solid yellow, then slow pulsing yellow after 30s without a response | `waiting` | Yellow means user attention is needed | The agent needs user confirmation, authorization, selection, or input. |
| 🟢 | Solid green | `idle` | Green means ready | A session exists and is ready for the next prompt. |
| 🔴 | Red, flashing briefly when it first turns red. | `error` | Red means API-level failure | The current turn stopped because of an API-level failure such as rate limiting, authentication, quota, or server errors. |

`working` and `idle` are both green and are distinguished by breathing animation. `waiting` is yellow so it is visually separate from idle/complete, and red is reserved for API-level failures, not for ordinary tool or shell command failures.

When multiple sessions are visible, each session gets its own light. The right-click status summary uses this priority order: `error` > `waiting` > `working` > `idle` > `offline`.

## Download

Grab the latest packaged `.dmg` from the **[Releases page](https://github.com/andyiac/cc-lights/releases/latest)**:

1. Download `CC-Lights-<version>.dmg` from the newest release.
2. Open the DMG and drag **CC Lights.app** into **Applications**.
3. First launch: the app is ad-hoc signed (not notarized), so **right-click the app → Open**, then confirm.

On first launch CC Lights installs its `cc-lights` CLI and configures the Claude Code hooks automatically — just restart Claude Code afterward. Prefer building from source? See [Quick start](#quick-start).

> The release `.dmg` is a **universal binary** and runs natively on both Apple Silicon and Intel Macs (macOS 11+).

## Requirements

**To run the app:**

- macOS 11 Big Sur or later
- Apple Silicon or Intel — the release `.dmg` ships a **universal binary** that runs natively on both

**To build from source, also:**

- Swift 5.9 or later
- Xcode Command Line Tools

## Quick start

```bash
# Build
make build

# Run the menu bar app in development
make run

# Package the macOS app and CLI into dist/
make bundle

# Build a distributable .dmg installer into dist/
make dmg

# Install the app into /Applications and the CLI into ~/bin
make install
```

After packaging, `dist/` contains:

- `CC Lights.app` - the macOS menu bar app
- `cc-lights` - the CLI used to update session status
- `CC-Lights-<version>.dmg` - a drag-to-Applications installer (after `make dmg`)

The app normally runs as a menu bar accessory app with no Dock icon. While the Preferences window is open it temporarily switches to a regular app and shows a Dock icon, then hides it again when the window closes.

## Using the menu bar app

| Action | Behavior |
| --- | --- |
| Left click a light | Focus the matching agent terminal session when possible. |
| Hover a light | Show session details and the latest status message. |
| Right click a light | Open the actions menu. |
| Option + left click | Open the same menu as right click. |

Terminal focusing is supported for Terminal.app and iTerm2 by matching the TTY. cmux sessions are focused through the `cmux://` URL scheme using the captured workspace and surface IDs, and the app also reads live Claude sessions from cmux's own hook records. Ghostty is matched by working directory because it does not expose TTY information in the same way.

macOS automation permission is required before the app can focus Terminal.app, iTerm2, or Ghostty through AppleScript. cmux focusing uses the `cmux://` URL scheme (opened through LaunchServices) and does not use AppleScript or the cmux socket. The first click may trigger a system permission prompt.

The right-click menu contains the current session details and count, **Reset this session to green** (⌘R), **Clear all errors**, **Preferences…** (⌘,), **Open agent context** (⌘O), and **Quit** (⌘Q).

## Preferences

Open Preferences from the right-click menu (**Preferences…**, or ⌘,). It is a macOS System Settings / Shottr style window with a top toolbar. While it is open the app shows a Dock icon, which is hidden again when you close the window.

| Tab | Contents |
| --- | --- |
| General | "Launch at login" toggle; status light style (round / pixel-art) with a live preview. The choice is saved in `UserDefaults` for future launches. |
| Notifications | "Enable system notifications" toggle. |
| Integration | Configuration status for each supported agent (Claude Code / Codex / OpenCode), with **Auto-configure Hook**, **Re-check**, and **Open config**. |
| About | App icon, name, version, and a short description. |

## Using the CLI

```bash
# Set the current session state
cc-lights working --task "Build project"
cc-lights waiting --message "Approval required"
cc-lights idle
cc-lights offline --message "Session exited"
cc-lights error --message "API request failed"

# Track a specific session
cc-lights working \
  --session "$CLAUDE_SESSION_ID" \
  --cwd "$PWD" \
  --title "$(basename "$PWD")"

# Reset to idle
cc-lights reset

# Remove a session light
cc-lights remove --session "$CLAUDE_SESSION_ID"

# codex / opencode hooks: a short form that reads session_id/cwd from stdin JSON (codex) or CLI args
cc-lights hook working   # SessionStart / UserPromptSubmit / PreToolUse / PostToolUse
cc-lights hook waiting   # PermissionRequest
cc-lights hook idle      # Stop
cc-lights hook remove    # SessionEnd

# Inspect stored status
cc-lights show
cc-lights show --session "$CLAUDE_SESSION_ID"
cc-lights path
```

When running from source, use `swift run cc-lights` instead of `cc-lights`.

> The `hook` subcommand reads a codex hook JSON payload from stdin (containing `session_id`, `cwd`, `hook_event_name`) and suppresses normal output so the JSON isn't injected into the agent's context. For the `Stop` event it prints `{"continue":true}` as codex requires.

### CLI options

| Option | Short | Description |
| --- | --- | --- |
| `--message <text>` | `-m` | Extra status message, such as an error or waiting reason. |
| `--task <name>` | `-t` | Current task name. |
| `--session <id>` | `-s` | Session identifier. If omitted, the CLI tries agent environment variables (Claude Code / codex), terminal TTY, then working directory. |
| `--cwd <path>` | | Working directory for the session. |
| `--title <name>` | | Display title shown in hover details. |
| `--terminal-bundle <id>` | | Terminal app bundle identifier, such as `com.googlecode.iterm2`. |
| `--tty <tty>` | | Terminal TTY, such as `/dev/ttys001`, used to focus Terminal.app or iTerm2 sessions. |
| `--cmux-workspace <id>` | | cmux workspace ID or ref used to focus sessions running inside cmux. Auto-detected from `CMUX_WORKSPACE_ID` when available. |
| `--cmux-surface <id>` | | cmux surface/panel ID or ref used to focus sessions running inside cmux. Auto-detected from `CMUX_SURFACE_ID` when available. |
| `--cmux-socket <path>` | | cmux socket path for focusing sessions from outside cmux. Auto-detected from `CMUX_SOCKET_PATH` when available. |

## Local status files

Session state is stored in:

```text
~/Library/Application Support/ClaudeCodeStatusLight/sessions/
```

Each session is represented by one JSON file:

```json
{
  "message": "Build succeeded",
  "sessionID": "session-123",
  "sessionTitle": "cc-status",
  "state": "working",
  "taskName": "Build project",
  "terminalBundleIdentifier": "com.googlecode.iterm2",
  "terminalTTY": "/dev/ttys001",
  "cmuxWorkspaceID": "workspace-id",
  "cmuxSurfaceID": "surface-id",
  "cmuxSocketPath": "/tmp/cmux.sock",
  "updatedAt": "2024-01-01T12:00:00Z",
  "workingDirectory": "/Users/example/Developer/cc-status"
}
```

The menu bar app watches this directory and updates lights in real time. The CLI writes status files, so the app and CLI communicate through local filesystem state rather than a background server.

The app removes stale sessions that have not been updated for more than 24 hours. A normal session shutdown should call `cc-lights remove --session "$CLAUDE_SESSION_ID"` to remove the light immediately.

`idle` and `offline` are different:

- `idle` / green: the agent session still exists and is ready for more work.
- `offline` / gray: no active agent session exists, or the user has exited the agent.

## Notifications

The app can send system notifications when:

- A session enters `waiting`, meaning the agent needs a user decision.
- A session changes to `error`, meaning the turn needs attention.

Notifications can be disabled in Preferences → Notifications.

## Integrating with coding agents

Session updates are driven per agent:

- **Claude Code** — via hooks in `~/.claude/settings.json`.
- **Codex** — via hooks in `~/.codex/hooks.json`.
- **OpenCode** — via a plugin at `~/.config/opencode/plugins/cc-lights.js`.
  OpenCode has no CLI hooks, so it subscribes to session events
  (`session.created`, `session.status`, `session.idle`, `session.error`,
  `session.deleted`, `permission.updated`) and calls the bundled `cc-lights` CLI.

Setup is automatic. On first launch the app:

1. Installs its bundled `cc-lights` helper to a stable, PATH-independent
   location: `~/Library/Application Support/ClaudeCodeStatusLight/cc-lights`.
2. Writes the Claude Code hooks into `~/.claude/settings.json` (backing the
   file up first), the Codex hooks into `~/.codex/hooks.json` (backing it up
   first), and the OpenCode plugin into
   `~/.config/opencode/plugins/cc-lights.js`.
3. Symlinks the helper into a writable `PATH` directory (such as
   `/opt/homebrew/bin` or `/usr/local/bin`) as both `cc-lights` and the
   legacy name `cc-statusctl`, so even a bare-command hook from any
   settings file resolves.

The CLI used to be called `cc-statusctl`. On launch the app automatically
migrates any old `cc-statusctl` hooks to `cc-lights` and keeps a
`cc-statusctl` compatibility alias (both in the managed folder and on
`PATH`), so existing setups keep working without manual changes.

Because the helper path is independent of the app's display name and
install location, renaming or moving the app does not break the hooks. On
every launch the app refreshes the helper and repairs already-configured
hooks to point at it (idempotent; a `settings.json.bak-*` / `hooks.json.bak-*`
backup is made only when something actually changes). So you never install
the CLI by hand — just install the app, launch it once, and restart the
agent.

You can re-run the configuration any time from **Preferences → Integration**
(**Auto-configure Hook**).

Under the hood the hooks call `cc-lights` like this:

```bash
# When a turn starts or before a tool runs (Claude Code)
cc-lights working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# Codex hooks read session_id / cwd from the JSON on stdin instead of env vars
cc-lights hook working   # SessionStart / UserPromptSubmit / PreToolUse / PostToolUse
cc-lights hook waiting   # PermissionRequest
cc-lights hook idle      # Stop
cc-lights hook remove    # SessionEnd

# OpenCode plugin passes sessionID / cwd explicitly
cc-lights working --session "$OPENCODE_SESSION_ID" --cwd "$PWD"
```

If you want to call the CLI yourself from a terminal or with `!` inside an agent session, symlink the managed helper onto your `PATH`, for example:

```bash
ln -sf "$HOME/Library/Application Support/ClaudeCodeStatusLight/cc-lights" /usr/local/bin/cc-lights
```

## FAQ

### What is CC Lights?

CC Lights (Claude Code Status Light) is an open-source macOS menu bar app that turns each Claude Code / Codex / OpenCode session into a small colored status light, so you can tell at a glance whether your agent is working, waiting for input, idle, offline, or errored — without switching windows.

### Which terminals does it support?

Clicking a light returns you to the right session in **Terminal.app, iTerm2, Ghostty, and cmux**. Terminal.app and iTerm2 are matched by TTY, cmux via the `cmux://` deep link, and Ghostty by working directory.

### Does it work with agent hooks?

Yes. On first launch CC Lights installs its `cc-lights` CLI and writes the Claude Code hooks to `~/.claude/settings.json`, the Codex hooks to `~/.codex/hooks.json`, and the OpenCode plugin to `~/.config/opencode/plugins/cc-lights.js` (each backed up first). The hooks / plugin call `cc-lights` on each lifecycle event, so the lights update in real time. Restart the agent once after the initial setup.

### Does CC Lights show a Dock icon?

No — it runs as a menu bar accessory app. It only shows a Dock icon while the Preferences window is open, then hides it again when you close the window.

### Where is session state stored?

In per-session JSON files under `~/Library/Application Support/ClaudeCodeStatusLight/sessions/`. The app watches that folder and updates lights live, and the CLI writes to it — there is no background server.

### How do I install it?

Download the latest `CC-Lights-<version>.dmg` from the [Releases page](https://github.com/andyiac/cc-lights/releases/latest), then drag `CC Lights.app` into `/Applications`. Prefer building yourself? Use `make bundle` (or `make dmg`). Requires macOS 11+ and, to build, Swift 5.9+.

### Is it free and open source?

Yes. CC Lights is a Swift Package Manager project you can build, audit, and modify yourself.

## Development

```bash
make build
make test
make run
make bundle
make install
make clean
```

### Automation permission

Clicking a status light to focus Terminal.app, iTerm2, or Ghostty depends on macOS Automation (TCC) permission because the app uses AppleScript for those terminals. cmux focusing goes through the `cmux://` URL scheme instead.

The bundled `Info.plist` includes `NSAppleEventsUsageDescription`; without it, macOS may silently deny automation from a background menu bar app. The first click may show a prompt asking whether CC Lights can control the terminal app.

`make install` uses ad-hoc signing. Reinstalling after rebuilding can make macOS treat the app as a new identity, so automation permission may need to be granted again.

## Project structure

```text
cc-status/
├── Sources/
│   ├── StatusLightCore/        # Shared state model and file store
│   ├── ClaudeCodeStatusLight/  # macOS menu bar app
│   └── CCLights/               # CLI tool
├── Tests/
│   └── StatusLightCoreTests/
├── Resources/
│   └── Info.plist
├── Package.swift
├── Makefile
├── README.md
└── README.zh-CN.md
```
