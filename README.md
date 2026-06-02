# Claude Code Status Light

macOS 状态栏五色状态灯 App，通过监控本地状态文件，实时显示 Claude Code 当前状态。

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
| **左键点击** | 根据当前状态执行快捷操作（见下方） |
| **右键点击** | 打开菜单（或按住 `Option` + 左键） |

#### 左键点击的快捷行为

- **⚪️ 无会话 / 🔵 工作中 / 🟢 空闲**：打开终端或 VS Code（尝试按顺序打开 iTerm2 → Terminal → VS Code）
- **🟡 等待决策**：弹出对话框，显示等待消息，可选择"打开上下文"或"重置为绿灯"
- **🔴 错误**：弹出错误详情对话框，可选择"重置为绿灯"、"打开上下文"或"保留红灯"

#### 右键菜单选项

| 菜单项 | 说明 |
| --- | --- |
| 当前状态 | 显示当前状态和任务名/消息 |
| 重置为绿灯 (`⌘R`) | 将状态重置为 `idle` |
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

# 重置为绿色（等价于 cc-statusctl idle）
cc-statusctl reset

# 查看当前状态
cc-statusctl show

# 查看状态文件路径
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

### 状态文件

状态文件位于 `~/Library/Application Support/ClaudeCodeStatusLight/status.json`，格式：

```json
{
  "message" : "编译成功",
  "state" : "working",
  "taskName" : "构建项目",
  "updatedAt" : "2024-01-01T12:00:00Z"
}
```

多个进程间通过此文件共享状态：App 监控文件变更实时更新灯色，CLI 工具写入新状态。App 和 CLI 无需同时启动——可以只使用 CLI 写入状态，App 负责显示。

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
/usr/local/bin/cc-statusctl working --task "$CLAUDE_TASK_NAME"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_task_end.sh  — 任务完成
/usr/local/bin/cc-statusctl idle
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_session_end.sh  — Claude Code session 退出时
/usr/local/bin/cc-statusctl offline --message "Claude Code session 已退出"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_task_error.sh  — 任务出错
/usr/local/bin/cc-statusctl error --message "任务执行失败，退出码：$?"
```

```bash
#!/bin/bash
# ~/.claude/hooks/on_ask.sh  — 需要用户决策
/usr/local/bin/cc-statusctl waiting --message "请确认后续操作"
```

> ⚠️ Hook 文件需要 `chmod +x` 赋予执行权限。

### 方案二：手动调用

在 Claude Code 会话中按需调用：

```bash
# 让 Claude 自己调用 CLI 更新状态
!cc-statusctl working --task "重构用户模块"
!cc-statusctl waiting --message "请确认接口变更"
!cc-statusctl error --message "测试失败"
!cc-statusctl idle
!cc-statusctl offline --message "Claude Code session 已退出"
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
