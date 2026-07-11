# Claude Code Status Light

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="CC Lights logo" />
</p>

<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">中文</a>
</p>

Claude Code Status Light is a macOS menu bar app that shows the live status of one or more Claude Code sessions as small colored lights.

The project is built for developers who keep Claude Code running in a terminal or editor and do not want to constantly switch back just to check whether it is still working, waiting for input, idle, offline, or blocked by an error.

## What it does

- Shows a separate menu bar light for each tracked Claude Code session.
- Uses traffic-light color cues and animation to make the current session state visible at a glance.
- Lets you choose the default round light style or a pixel-art light style from Preferences.
- Lets you hover a light to inspect session details such as title, working directory, terminal, current task, message, and update time.
- Lets you click a light to return to the matching terminal window or tab when terminal automation is available.
- Provides a small CLI, `cc-lights`, so Claude Code hooks or manual commands can update session status.
- Stores session state locally in JSON files under the user's Application Support directory.

## Status model

| Light | State | Traffic-light cue | Meaning |
| --- | --- | --- | --- |
| Gray | `offline` | No active session | No tracked Claude Code session exists, or the session has exited. |
| Pulsing green | `working` | Green means Claude Code is running | Claude Code is actively running a task and does not need user input. |
| Solid yellow, then slow pulsing yellow after 30s without a response | `waiting` | Yellow means user attention is needed | Claude Code needs user confirmation, authorization, selection, or input. |
| Solid green | `idle` | Green means ready | A session exists and is ready for the next prompt. |
| Red, flashing briefly when it first turns red | `error` | Red means API-level failure | The current turn stopped because of an API-level failure such as rate limiting, authentication, quota, or server errors. |

`working` and `idle` are both green and are distinguished by breathing animation. `waiting` is yellow so it is visually separate from idle/complete, and red is reserved for API-level failures, not for ordinary tool or shell command failures.

When multiple sessions are visible, each session gets its own light. The right-click status summary uses this priority order: `error` > `waiting` > `working` > `idle` > `offline`.

## Requirements

- macOS 11 Big Sur or later
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
- `CC-Status-Light-<version>.dmg` - a drag-to-Applications installer (after `make dmg`)

The app normally runs as a menu bar accessory app with no Dock icon. While the Preferences window is open it temporarily switches to a regular app and shows a Dock icon, then hides it again when the window closes.

## Using the menu bar app

| Action | Behavior |
| --- | --- |
| Left click a light | Focus the matching Claude Code terminal session when possible. |
| Hover a light | Show session details and the latest status message. |
| Right click a light | Open the actions menu. |
| Option + left click | Open the same menu as right click. |

Terminal focusing is supported for Terminal.app and iTerm2 by matching the TTY. cmux sessions are focused through the `cmux://` URL scheme using the captured workspace and surface IDs, and the app also reads live Claude sessions from cmux's own hook records. Ghostty is matched by working directory because it does not expose TTY information in the same way.

macOS automation permission is required before the app can focus Terminal.app, iTerm2, or Ghostty through AppleScript. cmux focusing uses the `cmux://` URL scheme (opened through LaunchServices) and does not use AppleScript or the cmux socket. The first click may trigger a system permission prompt.

The right-click menu contains the current session details and count, **Reset this session to green** (⌘R), **Clear all errors**, **Preferences…** (⌘,), **Open Claude Code context** (⌘O), and **Quit** (⌘Q).

## Preferences

Open Preferences from the right-click menu (**Preferences…**, or ⌘,). It is a macOS System Settings / Shottr style window with a top toolbar. While it is open the app shows a Dock icon, which is hidden again when you close the window.

| Tab | Contents |
| --- | --- |
| General | "Launch at login" toggle; status light style (round / pixel-art) with a live preview. The choice is saved in `UserDefaults` for future launches. |
| Notifications | "Enable system notifications" toggle. |
| Integration | Claude Code hook configuration status, with **Auto-configure Hook**, **Re-check**, and **Open settings.json**. |
| About | App icon, name, version, and a short description. |

## Using the CLI

```bash
# Set the current session state
cc-lights working --task "Build project"
cc-lights waiting --message "Approval required"
cc-lights idle
cc-lights offline --message "Claude Code session exited"
cc-lights error --message "API request failed"

# Track a specific Claude Code session
cc-lights working \
  --session "$CLAUDE_SESSION_ID" \
  --cwd "$PWD" \
  --title "$(basename "$PWD")"

# Reset to idle
cc-lights reset

# Remove a session light
cc-lights remove --session "$CLAUDE_SESSION_ID"

# Inspect stored status
cc-lights show
cc-lights show --session "$CLAUDE_SESSION_ID"
cc-lights path
```

When running from source, use `swift run cc-lights` instead of `cc-lights`.

### CLI options

| Option | Short | Description |
| --- | --- | --- |
| `--message <text>` | `-m` | Extra status message, such as an error or waiting reason. |
| `--task <name>` | `-t` | Current task name. |
| `--session <id>` | `-s` | Session identifier. If omitted, the CLI tries Claude Code environment variables, terminal TTY, then working directory. |
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

- `idle` / green: the Claude Code session still exists and is ready for more work.
- `offline` / gray: no active Claude Code session exists, or the user has exited Claude Code.

## Notifications

The app can send system notifications when:

- A session enters `waiting`, meaning Claude Code needs a user decision.
- A session changes to `error`, meaning the turn needs attention.

Notifications can be disabled in Preferences → Notifications.

## Integrating with Claude Code

Setup is automatic. On first launch the app:

1. Installs its bundled `cc-lights` helper to a stable, PATH-independent
   location: `~/Library/Application Support/ClaudeCodeStatusLight/cc-lights`.
2. Writes the Claude Code hooks into `~/.claude/settings.json` using the
   absolute path to that helper (backing up the file first).
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
hooks to point at it (idempotent; a `settings.json.bak-*` backup is made
only when something actually changes). So you never install the CLI by
hand — just install the app, launch it once, and restart Claude Code.

You can re-run the configuration any time from **Preferences → Integration**
(**Auto-configure Hook**).

Under the hood the hooks call `cc-lights` like this:

```bash
# When a turn starts or before a tool runs
cc-lights working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# When Claude Code needs a user decision
cc-lights waiting --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "User input required"

# When a turn finishes normally
cc-lights idle --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# When an API-level failure stops the turn
cc-lights error --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "Request failed"

# When the session exits
cc-lights remove --session "$CLAUDE_SESSION_ID"
```

If you want to call the CLI yourself from a terminal or with `!` inside a
Claude Code session, symlink the managed helper onto your `PATH`, for example:

```bash
ln -sf "$HOME/Library/Application Support/ClaudeCodeStatusLight/cc-lights" /usr/local/bin/cc-lights
```

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
