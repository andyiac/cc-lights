# Claude Code Status Light

macOS 状态栏五色状态灯 App，通过监控本地 session 状态文件，实时显示一个或多个 Claude Code session 的当前状态。

![状态灯颜色](./docs/status-colors.png)

## 状态说明

| 灯色 | 状态值 | 含义 | 显示效果 | 说明 |
| --- | --- | --- | --- | --- |
| ⚪️ 灰色 | `offline` | 无会话 | 常亮 | 没有可跟踪的 Claude Code session，或 session 已退出 |
| 🔵 蓝色 | `working` | 工作中 | 脉冲呼吸（30% ↔ 100% 透明度，1 秒周期） | Claude Code 正在自动执行任务 |
| 🟡 黄色 | `waiting` | 等待决策 | 常亮 | 需要用户做决策或确认 |
| 🟢 绿色 | `idle` | 空闲 | 常亮 | 有 Claude Code session，且当前空闲或上次任务完成 |
| 🔴 红色 | `error` | 错误 | 常亮 | 执行失败或异常 |

---

## 快速开始

### 1. 构建并运行

```bash
# 编译
make build

# 直接运行（调试模式）
make run

# 打包为 macOS App
make bundle

# 安装到 /Applications（含自动打包）
make install
```

打包后在 `dist/` 目录下会生成：

- `dist/Claude Code Status Light.app` — 菜单栏 App
- `dist/cc-statusctl` — 命令行工具（也可用 `swift run cc-statusctl`）

### 2. 运行 App

双击 `Claude Code Status Light.app` 或在终端运行：

```bash
make run
```

启动后，菜单栏会出现一个圆形状态灯（默认灰色，表示尚未检测到 Claude Code session）。App 以 **accessory** 模式运行，不会有 Dock 图标。

---

## 使用方法

### 菜单栏操作

| 操作 | 行为 |
| --- | --- |
| **左键点击某个灯** | 直接回到该灯对应的 Claude Code 终端 session |
| **悬停某个灯** | 显示 session 名称/目录、终端、状态、任务/消息和最后更新时间 |
| **右键点击某个灯** | 打开设置菜单（或按住 `Option` + 左键） |

#### 多 session 状态灯

每个 Claude Code session 会在状态栏显示一个独立圆形灯，不显示文字。灯色表示该 session 的当前状态；鼠标悬停可查看详情，左键点击会优先按终端 TTY 回到正在运行 Claude Code 的 iTerm2/Terminal 窗口或标签页。

没有 session 时会显示一个灰灯占位；右键可打开设置菜单。

#### 右键菜单选项

| 菜单项 | 说明 |
| --- | --- |
| 当前状态 | 显示最高优先级状态、session 数和任务名/消息 |
| 重置为绿灯 (`⌘R`) | 将当前最高优先级 session 重置为 `idle` |
| 在登录时启动 | 添加/移除 LaunchAgent 实现开机自启 |
| 启用通知 | 切换系统通知开关（状态从工作中→等待决策 或 →错误 时推送通知） |
| 打开 Claude Code 上下文 (`⌘O`) | 打开终端/VS Code |
| 退出 | 退出 App（会二次确认） |

### 使用 CLI 工具更新状态

```bash
# 设置状态
cc-statusctl working --task "编译 main.go"
cc-statusctl waiting --message "需要确认危险操作"
cc-statusctl idle
cc-statusctl offline --message "Claude Code session 已退出"
cc-statusctl error --message "构建失败：编译器报错"

# 指定 session（推荐用于多个 Claude Code session）
cc-statusctl working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "cc-status"

# 重置为绿色（等价于 cc-statusctl idle）
cc-statusctl reset

# 移除某个 session 的灯（session 退出时清理，避免残留）
cc-statusctl remove --session "$CLAUDE_SESSION_ID"

# 查看所有 session 状态
cc-statusctl show

# 查看单个 session 状态
cc-statusctl show --session "$CLAUDE_SESSION_ID"

# 查看 session 状态目录
cc-statusctl path
```

**未打包时**，用 `swift run cc-statusctl` 代替：

```bash
swift run cc-statusctl working --task "编译 main.go"
swift run cc-statusctl waiting --message "需要确认危险操作"
swift run cc-statusctl idle
swift run cc-statusctl offline --message "Claude Code session 已退出"
swift run cc-statusctl error --message "构建失败"
swift run cc-statusctl reset
swift run cc-statusctl show
swift run cc-statusctl path
```

#### CLI 选项

| 选项 | 缩写 | 说明 |
| --- | --- | --- |
| `--message <文本>` | `-m` | 附加消息（如错误信息、等待原因） |
| `--task <任务名>` | `-t` | 当前任务名称 |
| `--session <ID>` | `-s` | session 标识；未提供时默认使用当前工作目录 |
| `--cwd <路径>` |  | session 对应的工作目录 |
| `--title <名称>` |  | session 在 hover 详情中的显示名称 |
| `--terminal-bundle <ID>` |  | 终端 App 的 bundle identifier，如 `com.googlecode.iterm2` |
| `--tty <TTY>` |  | 终端 TTY，如 `/dev/ttys001`，用于点击灯时回到具体窗口/标签页 |

未显式传入时，`cc-statusctl` 会自动尝试从 `TERM_PROGRAM`、`TTY`、`SSH_TTY` 和 `tty` 命令推断终端信息。

### 状态文件

多 session 状态文件位于 `~/Library/Application Support/ClaudeCodeStatusLight/sessions/`，每个 session 一个 JSON 文件。格式：

```json
{
  "message" : "编译成功",
  "sessionID" : "session-123",
  "sessionTitle" : "cc-status",
  "state" : "working",
  "taskName" : "构建项目",
  "terminalBundleIdentifier" : "com.googlecode.iterm2",
  "terminalTTY" : "/dev/ttys001",
  "updatedAt" : "2024-01-01T12:00:00Z",
  "workingDirectory" : "/Users/example/Developer/cc-status"
}
```

多个进程间通过此目录共享状态：App 监控目录变更实时更新灯色，CLI 工具按 session 写入新状态。App 和 CLI 无需同时启动——可以只使用 CLI 写入状态，App 负责显示。

`idle` 和 `offline` 的区别：

- `idle` / 绿灯：Claude Code session 仍然存在，只是当前没有任务，可以继续发新任务。
- `offline` / 灰灯：没有活跃 Claude Code session，或用户已经退出 Claude Code。

---

## 通知

App 自动推送系统通知的场景：

- **工作中 → 等待决策**：Claude Code 需要你回到终端做选择
- **任意状态 → 错误**：执行出错需要关注

可在右键菜单中关闭通知。

---

## 与 Claude Code 集成

### 方案一：Claude Code Hooks（推荐）

将 `cc-statusctl` 与 Claude Code 的 hook 系统结合，自动更新状态。

创建 `~/.claude/hooks/` 目录和对应的 hook 脚本，示例：

```bash
#!/bin/bash
# ~/.claude/hooks/on_task_start.sh  — 任务开始时
/usr/local/bin/cc-statusctl working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --task "$CLAUDE_TASK_NAME"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_task_end.sh  — 任务完成
/usr/local/bin/cc-statusctl idle --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_session_end.sh  — Claude Code session 退出时（移除对应的灯，避免残留）
/usr/local/bin/cc-statusctl remove --session "$CLAUDE_SESSION_ID"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_task_error.sh  — 任务出错
/usr/local/bin/cc-statusctl error --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "任务执行失败，退出码：$?"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_ask.sh  — 需要用户决策
/usr/local/bin/cc-statusctl waiting --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")" --message "请确认后续操作"
```

> ⚠️ Hook 文件需要 `chmod +x` 赋予执行权限。
> `cc-statusctl` 会尽量自动记录当前终端信息；若你的 hook 环境拿不到 TTY，可以显式追加 `--tty "$(tty)" --terminal-bundle "com.googlecode.iterm2"` 或对应终端的 bundle identifier。

### 方案二：手动调用

在 Claude Code 会话中按需调用：

```bash
# 让 Claude 自己调用 CLI 更新状态
!cc-statusctl working --task "重构用户模块"
!cc-statusctl waiting --message "请确认接口变更"
!cc-statusctl error --message "测试失败"
!cc-statusctl idle
!cc-statusctl offline --message "Claude Code session 已退出"

# 多 session 时建议显式指定 session
!cc-statusctl working --session "$CLAUDE_SESSION_ID" --cwd "$PWD" --title "$(basename "$PWD")"
```

在 Claude Code 中，以 `!` 开头的命令会直接在终端执行，输出会回到对话中。

---

## 开发

```bash
# 构建
make build

# 运行测试
make test

# 清理构建产物
make clean
```

### 项目结构

```
cc-status/
├── Sources/
│   ├── StatusLightCore/       # 核心库
│   │   ├── StatusState.swift   # 状态枚举（offline/working/waiting/idle/error）
│   │   ├── StatusPayload.swift # 状态数据模型
│   │   └── StatusFileStore.swift # 状态文件读写
│   ├── ClaudeCodeStatusLight/  # 菜单栏 App
│   │   └── main.swift
│   └── CCStatusCtl/           # CLI 工具
│       └── main.swift
├── Tests/
│   └── StatusLightCoreTests/
│       └── StatusPayloadTests.swift
├── Resources/
│   └── Info.plist
├── Package.swift              # SwiftPM 配置
├── Makefile                   # 构建/打包/安装
└── README.md
```
