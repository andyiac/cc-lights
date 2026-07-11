# Claude Code Status Light

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="CC Lights logo" />
</p>

<p align="center">
  <a href="README.md">English</a> · <b>中文</b>
</p>

Claude Code Status Light 是一个 macOS 状态栏红绿灯 App。它通过监控本地 session 状态文件，实时显示一个或多个 Claude Code session 的当前状态。

这个项目主要解决的问题是：当 Claude Code 在终端或编辑器里运行时，开发者不需要频繁切回窗口查看它到底是在工作、等待输入、空闲、离线，还是遇到了错误。

## 功能概览

- 每个 Claude Code session 在状态栏显示一个独立圆形灯。
- 使用交通灯颜色和动画表达当前状态。
- 可在偏好设置的「通用」分页切换默认圆形灯和像素风格状态灯。
- 鼠标悬停可查看 session 名称/目录、终端、状态、任务/消息和最后更新时间。
- 点击状态灯可回到对应的终端窗口或标签页。
- 提供 `cc-lights` 命令行工具，便于 Claude Code hooks 或手动命令更新状态。
- 所有 session 状态都存储在本地 JSON 文件中。

## 状态模型

| 灯色 | 状态值 | 红绿灯指示 | 含义 |
| --- | --- | --- | --- |
| 灰色 | `offline` | 无活跃会话 | 没有可跟踪的 Claude Code session，或 session 已退出。 |
| 绿色闪烁 | `working` | 绿灯表示 Claude Code 正在运行 | Claude Code 正在自动执行任务，不需要用户干预。 |
| 黄色常亮，30 秒未响应后黄色慢呼吸 | `waiting` | 黄灯表示需要用户注意 | Claude Code 需要用户授权、确认、选择或输入。 |
| 绿色常亮 | `idle` | 绿灯表示可继续使用 | 有 Claude Code session，且当前空闲或上次任务已正常完成。 |
| 红色，初次变红时短暂闪烁 | `error` | 红灯表示 API 层错误 | 这一轮对话因 API 错误中断，例如限流、认证失败、额度或服务器错误。 |

`working` 与 `idle` 都是绿色，通过呼吸动画区分；`waiting` 使用黄色，避免与空闲/完成混淆。红灯只表示 API 层错误，不表示普通 shell 命令或工具执行失败。

多个 session 同时存在时，每个 session 独立显示一个灯；右键菜单里的状态汇总按以下优先级展示：`error` > `waiting` > `working` > `idle` > `offline`。

## 快速开始

```bash
# 编译
make build

# 直接运行（调试模式）
make run

# 打包为 macOS App
make bundle

# 生成可分发的 .dmg 安装文件（输出到 dist/）
make dmg

# 安装到 /Applications，并把 CLI 安装到 ~/bin
make install
```

打包后在 `dist/` 目录下会生成：

- `CC Lights.app` - 菜单栏 App
- `cc-lights` - 命令行工具，也可用 `swift run cc-lights`
- `CC-Status-Light-<版本>.dmg` - 拖拽到 Applications 的安装镜像（执行 `make dmg` 后生成）

启动后，菜单栏会出现一个圆形状态灯。默认灰色表示尚未检测到 Claude Code session。App 平时以 accessory 模式运行，不会显示 Dock 图标；打开「偏好设置」窗口时会临时切换到 regular 模式，在 Dock 中显示应用图标，关闭窗口后重新隐藏。灯样式可在偏好设置中切换为像素风格，选择会在下次启动时保留。

## 使用方法

### 菜单栏操作

| 操作 | 行为 |
| --- | --- |
| 左键点击某个灯 | 直接回到该灯对应的 Claude Code 终端 session。 |
| 悬停某个灯 | 显示 session 名称/目录、终端、状态、任务/消息和最后更新时间。 |
| 右键点击某个灯 | 打开菜单（含「偏好设置…」入口）。 |
| 按住 Option 后左键点击 | 打开同一个菜单。 |

### 多 session 状态灯

每个 Claude Code session 会在状态栏显示一个独立圆形灯，不显示文字。灯色和动画表示该 session 的当前状态；鼠标悬停可查看详情，左键点击会回到正在运行该 Claude Code session 的终端窗口或标签页：

- iTerm2 / Terminal.app：按终端 TTY 精确定位窗口或标签页。
- cmux：通过 `cmux://` 深链接按 workspace 和 surface 精确定位面板。
- Ghostty：按 session 工作目录匹配终端并 focus，因为 Ghostty 未暴露 TTY。

如果没有 session，会显示一个灰灯占位；右键仍然可打开菜单。

### 右键菜单选项

| 菜单项 | 说明 |
| --- | --- |
| 当前状态 | 显示右键点击灯对应 session 的名称、状态、更新时间、任务/消息、目录/终端，以及 session 总数。 |
| 重置此 session 为绿灯 | 将右键点击的 session 重置为 `idle`。 |
| 清除所有错误 | 将所有红灯 session 重置为 `idle`。 |
| 偏好设置… | 打开偏好设置窗口（⌘,），并在 Dock 中显示应用图标。 |
| 打开 Claude Code 上下文 | 切回当前选中 session 所属的终端 App/面板。 |
| 退出 | 退出 App，会二次确认。 |

### 偏好设置窗口

从右键菜单选择「偏好设置…」（或按 ⌘,）打开一个参考 macOS 系统设置 / Shottr 风格的窗口，顶部工具栏分为以下分页；打开期间 Dock 会显示应用图标，关闭后自动隐藏：

| 分页 | 内容 |
| --- | --- |
| 通用 | 「登录时自动启动」开关；状态灯样式（圆形灯 / 像素风格）切换并实时预览。 |
| 通知 | 「启用系统通知」开关，在 session 进入等待决策或出错时提醒。 |
| 集成 | Claude Code Hook 配置状态，并提供「自动配置 Hook」「重新检查」「打开 settings.json」。 |
| 关于 | 应用图标、名称、版本与简介。 |

## 使用 CLI 更新状态

```bash
# 设置状态
cc-lights working --task "编译 main.go"
cc-lights waiting --message "需要确认危险操作"
cc-lights idle
cc-lights offline --message "Claude Code session 已退出"
cc-lights error --message "API 请求失败"

# 指定 session，推荐用于多个 Claude Code session
cc-lights working \
  --session "$CLAUDE_SESSION_ID" \
  --cwd "$PWD" \
  --title "$(basename "$PWD")"

# 重置为绿色，等价于 cc-lights idle
cc-lights reset

# 移除某个 session 的灯
cc-lights remove --session "$CLAUDE_SESSION_ID"

# 查看状态
cc-lights show
cc-lights show --session "$CLAUDE_SESSION_ID"
cc-lights path
```

未打包时，用 `swift run cc-lights` 代替 `cc-lights`。

### CLI 选项

| 选项 | 缩写 | 说明 |
| --- | --- | --- |
| `--message <文本>` | `-m` | 附加消息，例如错误信息或等待原因。 |
| `--task <任务名>` | `-t` | 当前任务名称。 |
| `--session <ID>` | `-s` | session 标识；未提供时依次使用 Claude session 环境变量、当前终端 TTY、当前工作目录。 |
| `--cwd <路径>` | | session 对应的工作目录。 |
| `--title <名称>` | | session 在 hover 详情中的显示名称。 |
| `--terminal-bundle <ID>` | | 终端 App 的 bundle identifier，例如 `com.googlecode.iterm2`。 |
| `--tty <TTY>` | | 终端 TTY，例如 `/dev/ttys001`，用于点击灯时回到具体窗口或标签页。 |
| `--cmux-workspace <ID>` | | cmux workspace ID 或 ref；在 cmux 中会自动从 `CMUX_WORKSPACE_ID` 读取。 |
| `--cmux-surface <ID>` | | cmux surface/panel ID 或 ref；在 cmux 中会自动从 `CMUX_SURFACE_ID` 读取。 |
| `--cmux-socket <路径>` | | cmux socket 路径；在 cmux 中会自动从 `CMUX_SOCKET_PATH` 读取。 |

`cc-lights` 会自动尝试从 `TERM_PROGRAM`、`TTY`、`SSH_TTY` 和 `tty` 命令推断终端信息；在 cmux 中还会自动读取 `CMUX_WORKSPACE_ID`、`CMUX_SURFACE_ID` 和 `CMUX_SOCKET_PATH`。hook 子进程里 `tty` 通常失效时，会沿父进程链用 `ps` 找回控制终端。Ghostty 通过工作目录定位窗口，无需 TTY。

## 状态文件

多 session 状态文件位于：

```text
~/Library/Application Support/ClaudeCodeStatusLight/sessions/
```

每个 session 一个 JSON 文件：

```json
{
  "message": "编译成功",
  "sessionID": "session-123",
  "sessionTitle": "cc-status",
  "state": "working",
  "taskName": "构建项目",
  "terminalBundleIdentifier": "com.googlecode.iterm2",
  "terminalTTY": "/dev/ttys001",
  "cmuxWorkspaceID": "workspace-id",
  "cmuxSurfaceID": "surface-id",
  "cmuxSocketPath": "/tmp/cmux.sock",
  "updatedAt": "2024-01-01T12:00:00Z",
  "workingDirectory": "/Users/example/Developer/cc-status"
}
```

多个进程通过此目录共享状态：App 监控目录变更实时更新灯色，CLI 工具按 session 写入新状态。App 和 CLI 不需要同时启动；可以只用 CLI 写入状态，由 App 负责显示。

状态更新会保留已有的终端定位信息。App 启动时会清理超过 24 小时未更新的残留 session。`SessionEnd` 正常退出时应立即调用 `cc-lights remove --session "$CLAUDE_SESSION_ID"` 移除对应灯。

`idle` 和 `offline` 的区别：

- `idle` / 绿灯：Claude Code session 仍然存在，只是当前没有任务，可以继续发新任务。
- `offline` / 灰灯：没有活跃 Claude Code session，或用户已经退出 Claude Code。

## 通知

App 自动推送系统通知的场景：

- 进入 `waiting`：Claude Code 需要你回到终端做选择。
- 任意状态变为 `error`：这轮对话因 API 层错误中断，需要关注。

可在偏好设置的「通知」分页关闭通知。

## 与 Claude Code 集成

推荐将 `cc-lights` 与 Claude Code hooks 结合，自动更新状态：

```bash
# 任务开始或工具执行前
cc-lights working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# 需要用户决策
cc-lights waiting --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "请确认后续操作"

# 任务正常结束
cc-lights idle --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"

# API 层错误导致本轮中断
cc-lights error --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "请求失败"

# Claude Code session 退出
cc-lights remove --session "$CLAUDE_SESSION_ID"
```

也可以在 Claude Code 会话中按需手动调用：

```bash
!cc-lights working --task "重构用户模块"
!cc-lights waiting --message "请确认接口变更"
!cc-lights error --message "API 请求失败"
!cc-lights idle
!cc-lights offline --message "Claude Code session 已退出"
```

在 Claude Code 中，以 `!` 开头的命令会直接在终端执行。

## 开发

```bash
make build
make test
make run
make bundle
make install
make clean
```

### 自动化授权

点击状态灯回到 Terminal.app、iTerm2 或 Ghostty 窗口依赖 macOS 自动化（TCC）授权，因为 App 会通过 AppleScript 控制这些终端。cmux 聚焦通过 `cmux://` 深链接完成，不走 AppleScript，也不需要 cmux socket。

本项目的 `Info.plist` 已包含 `NSAppleEventsUsageDescription`，否则后台菜单栏 App 可能会被系统静默拒绝且不弹授权框。首次点灯时，系统可能会弹出授权请求。

`make install` 使用 ad-hoc 签名。由于 ad-hoc 的签名标识每次重新编译都可能变化，重新安装后通常需要再次授权。

## 项目结构

```text
cc-status/
├── Sources/
│   ├── StatusLightCore/        # 核心库：状态模型和状态文件读写
│   ├── ClaudeCodeStatusLight/  # 菜单栏 App
│   └── CCLights/               # CLI 工具
├── Tests/
│   └── StatusLightCoreTests/
├── Resources/
│   └── Info.plist
├── Package.swift
├── Makefile
├── README.md
└── README.zh-CN.md
```
