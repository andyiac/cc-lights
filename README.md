# Claude Code Status Light

Claude Code Status Light is a macOS menu bar app that shows the live status of one or more Claude Code sessions as small colored lights.

The project is built for developers who keep Claude Code running in a terminal or editor and do not want to constantly switch back just to check whether it is still working, waiting for input, idle, offline, or blocked by an error.

## What it does

- Shows a separate menu bar light for each tracked Claude Code session.
- Uses color and animation to make the current session state visible at a glance.
- Lets you hover a light to inspect session details such as title, working directory, terminal, current task, message, and update time.
- Lets you click a light to return to the matching terminal window or tab when terminal automation is available.
- Provides a small CLI, `cc-statusctl`, so Claude Code hooks or manual commands can update session status.
- Stores session state locally in JSON files under the user's Application Support directory.

## Status model

| Light | State | Meaning |
| --- | --- | --- |
| Gray | `offline` | No tracked Claude Code session exists, or the session has exited. |
| Pulsing green | `working` | Claude Code is actively running a task and does not need user input. |
| Solid green, then pulsing green after 15s without a follow-up update | `waiting` | Claude Code needs user confirmation, authorization, selection, or input; details are shown in notifications, hover text, and the right-click menu. |
| Solid green | `idle` | A session exists and is ready for the next prompt. |
| Red | `error` | The current turn stopped because of an API-level failure such as rate limiting, authentication, quota, or server errors. |

The app can show multiple sessions at the same time. Each session gets its own light, and the right-click status summary uses this priority order: `error` > `waiting` > `working` > `idle` > `offline`.

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

# Install the app into /Applications and the CLI into ~/bin
make install
```

After packaging, `dist/` contains:

- `Claude Code Status Light.app` - the macOS menu bar app
- `cc-statusctl` - the CLI used to update session status

The app runs as a menu bar accessory app, so it does not show a Dock icon.

## Using the menu bar app

| Action | Behavior |
| --- | --- |
| Left click a light | Focus the matching Claude Code terminal session when possible. |
| Hover a light | Show session details and the latest status message. |
| Right click a light | Open the settings and status menu. |
| Option + left click | Open the same menu as right click. |

Terminal focusing is supported for Terminal.app and iTerm2 by matching the TTY. Ghostty is matched by working directory because it does not expose TTY information in the same way.

macOS automation permission is required before the app can focus another terminal application. The first click may trigger a system permission prompt.

## Using the CLI

```bash
# Set the current session state
cc-statusctl working --task "Build project"
cc-statusctl waiting --message "Approval required"
cc-statusctl idle
cc-statusctl offline --message "Claude Code session exited"
cc-statusctl error --message "API request failed"

# Track a specific Claude Code session
cc-statusctl working \
  --session "$CLAUDE_SESSION_ID" \
  --cwd "$PWD" \
  --title "$(basename "$PWD")"

# Reset to idle
cc-statusctl reset

# Remove a session light
cc-statusctl remove --session "$CLAUDE_SESSION_ID"

# Inspect stored status
cc-statusctl show
cc-statusctl show --session "$CLAUDE_SESSION_ID"
cc-statusctl path
```

When running from source, use `swift run cc-statusctl` instead of `cc-statusctl`.

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
  "updatedAt": "2024-01-01T12:00:00Z",
  "workingDirectory": "/Users/example/Developer/cc-status"
}
```

The menu bar app watches this directory and updates lights in real time. The CLI writes status files, so the app and CLI communicate through local filesystem state rather than a background server.

The app removes stale sessions that have not been updated for more than 24 hours. A normal session shutdown should call `cc-statusctl remove --session "$CLAUDE_SESSION_ID"` to remove the light immediately.

## Integrating with Claude Code

The intended setup is to call `cc-statusctl` from Claude Code hooks:

```bash
# When a turn starts or before a tool runs
cc-statusctl working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# When Claude Code needs a user decision
cc-statusctl waiting --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "User input required"

# When a turn finishes normally
cc-statusctl idle --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# When an API-level failure stops the turn
cc-statusctl error --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "Request failed"

# When the session exits
cc-statusctl remove --session "$CLAUDE_SESSION_ID"
```

You can also call the CLI manually from a Claude Code session by prefixing commands with `!`.

## Development

```bash
make build
make test
make run
make bundle
make install
make clean
```

## Project structure

```text
cc-status/
├── Sources/
│   ├── StatusLightCore/        # Shared state model and file store
│   ├── ClaudeCodeStatusLight/  # macOS menu bar app
│   └── CCStatusCtl/            # CLI tool
├── Tests/
│   └── StatusLightCoreTests/
├── Resources/
│   └── Info.plist
├── Package.swift
├── Makefile
└── README.md
```
