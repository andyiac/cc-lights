好的，以下是根据我们讨论结果整理的完整 PRD（产品需求文档），适用于 **macOS 状态栏红绿灯** 功能。

---

# 产品需求文档：Claude Code 状态栏红绿灯

| 文档版本 | 1.2 |
|---------|-----|
| 更新日期 | 2026-07-11 |
| 产品名称 | Claude Code Status Light（App 显示名：**CC Lights**） |
| 命令行工具 | `cc-lights`（旧名 `cc-statusctl`，自动迁移并保留兼容别名） |
| 平台 | macOS 11 Big Sur 及以上（状态栏 / menu bar） |

---

## 版本更新记录

### v1.2（2026-07-11）——同步当前实现

- **改名**：App 显示名统一为 **CC Lights**；CLI 从 `cc-statusctl` 更名为 `cc-lights`，启动时自动迁移旧 hook 并保留 `cc-statusctl` 兼容别名。
- **零配置集成**：首次启动自动把内置 `cc-lights` 安装到 `~/Library/Application Support/ClaudeCodeStatusLight/`，写入 Claude Code hooks（先备份 `settings.json`）并软链到 `PATH`；此后每次启动做幂等修复。偏好设置「集成」分页可随时重跑配置。
- **cmux 支持**：新增 cmux session 定位——通过 `cmux://` 深链接按 workspace + surface 精确切换面板，无需 TCC 授权；并读取 cmux 自身 hook 记录识别 Claude session。
- **偏好设置窗口**：参考 macOS 系统设置 / Shottr 的顶部工具栏分页窗口（通用 / 通知 / 集成 / 关于），从菜单「偏好设置…」（⌘,）打开；打开期间 App 切到 regular 模式，在 Dock 显示应用图标，关闭后回到 accessory（纯菜单栏）。登录启动、通知开关、灯样式、Hook 配置等设置统一收纳其中。
- **可切换灯样式**：可在偏好设置「通用」分页在默认**圆形灯**与**像素风格**间切换（带实时预览），偏好持久保存。
- **菜单增强**：新增「清除所有错误」（一键把所有红灯重置为空闲）。
- **hook 事件**：新增 `PostToolUse`，工具执行后保持工作中绿呼吸。

### v1.1（2026-06-03）

- 初始 PRD：状态模型、状态流转、交互与通知。

---

## 1. 背景与目标

Claude Code 在终端或 IDE 中运行时，用户无法直观感知其当前状态：是在自动执行任务、是需要用户做决策，还是已经完成或报错。

**目标**：在 macOS 状态栏提供一个状态灯，让用户**一眼判断**当前应采取的注意程度。

---

## 2. 用户与场景

| 用户 | 场景 | 期望 |
|------|------|------|
| 开发者 | 正在用 Claude Code 写代码/重构 | 不想频繁切到终端看它在干嘛 |
| 开发者 | 任务执行中离开电脑 | 回来时通过颜色知道是否需要操作或出错 |
| 开发者 | 多个 Claude Code session 并行 | 能在状态栏直接看到每个 session 的独立状态灯，并点击对应灯打开该 session（支持 iTerm2 / Terminal.app / Ghostty / cmux） |

---

## 3. 状态定义（核心）

| 颜色 | 名称 | 含义 | 用户心理预期 |
|------|------|------|-------------|
| ⚪️ 灰色 | **无会话** | 没有可跟踪的 Claude Code session，或用户已经退出 Claude Code | “它现在不在线/没有上下文” |
| 🟢 绿色（**呼吸闪烁**） | **工作中** | Claude Code 正在执行自动化任务（写文件、运行命令、搜索代码等），无需用户干预 | “它在忙，我不用管” |
| 🟡 黄色（常亮；30 秒未响应后慢呼吸） | **等待决策** | 任务被阻塞，需要用户授权/确认/选择/输入（批准权限、MCP 请求输入等），详情通过通知、hover 或右键菜单查看 | “需要我点一下” |
| 🟢 绿色（常亮） | **空闲/完成** | Claude Code session 存在，但没有正在执行的任务，上一次任务正常完成，也无挂起的决策请求 | “可以发新任务” |
| 🔴 红色（初次变红闪 3 次后常亮） | **错误** | 这一轮对话因 **API 错误**中断（限流、认证失败、额度、服务器错误等）| “出问题了，需要查看” |

> 注 1：**工作中**与**空闲/完成**同为绿色，靠**是否呼吸闪烁**区分——工作中呼吸，空闲常亮。等待决策使用黄灯，30 秒未响应后变为黄色慢呼吸。红色不用于表示忙碌。
> 注 2：红色仅表示对话因 API 层面错误中断（对应 `StopFailure` hook）；Claude 执行的命令/工具失败（如 bash 返回非 0）**不会**点红灯。

---

## 4. 状态流转规则（事件 → 颜色变化）

### 4.1 正常路径（对应 Claude Code hook 事件）

```text
启动且无 Claude Code session            → ⚪️ 灰色
UserPromptSubmit（用户发起一轮）          → 🟢 绿色闪烁（工作中）
PreToolUse（工具执行前）                  → 🟢 绿色闪烁（保持/刷回工作中）
PostToolUse（工具执行后）                 → 🟢 绿色闪烁（保持工作中）
Notification: permission_prompt /
  elicitation_dialog（需授权或输入）      → 🟡 黄色常亮（等待决策）
Stop（一轮正常结束）                      → 🟢 绿色常亮（空闲/完成）
SessionEnd（session 退出）               → 移除该灯
```

> 等待决策后，用户批准 → 工具开始执行触发 `PreToolUse` → 刷回绿色呼吸；若 30 秒内没有响应，App 侧显示黄色慢呼吸；本轮结束 `Stop` → 绿色常亮。

### 4.2 错误路径

| 当前状态 | 触发事件 | 下一状态 |
|----------|----------|----------|
| 🟢 绿色闪烁 / 🟡 等待决策 | `StopFailure`（API 错误：限流/认证/额度/服务器等） | 🔴 红色（初次变红闪 3 次后常亮） |
| 🔴 红色 | 用户点击/关闭，或发起新一轮 | 🟢 绿色（重新开始） |

### 4.3 额外规则

- **手动重置**：  
  用户可通过状态栏菜单中的“重置为绿灯”将红灯或等待态手动变回绿灯（空闲）。
- **session 生命周期**：
  `SessionEnd` 正常退出时立即移除对应灯；被强杀/崩溃而未触发 `SessionEnd` 的残留，App 启动时清理超过 24 小时未更新的 session。无任何 session 时显示一个灰灯占位。
- **同时多个 session**：
  每个 session 独立显示一个状态灯；右键菜单中的“当前状态”采用“最高优先级”聚合规则：
  错误(红) > 等待决策(黄) > 工作中(绿呼吸) > 空闲(绿) > 无会话(灰)。

---

## 5. 交互与界面要求

### 5.1 状态栏图标

- 每个 Claude Code session 对应一个圆形灯，直径 16–18 pt，位于 macOS 状态栏右侧。
- 灯旁边不显示 session 名称或文字。
- 灯样式可在偏好设置「通用」分页切换：默认**圆形灯**或**像素风格**，偏好持久保存。
- 没有 session 时显示一个灰灯占位。
- 颜色使用系统近似色：
  - ⚪️ 灰色：`#8E8E93`
  - 🟢 绿色（工作中呼吸 / 空闲常亮）：`#34C759`
  - 🟡 黄色（等待决策）：`#FFCC00`
  - 🔴 红色：`#FF3B30`
- **工作中**为绿色呼吸动画（约 30% ↔ 100% 透明度，1 秒周期），**等待决策超时**为黄色慢呼吸（约 60% ↔ 100% 透明度，3 秒周期），**空闲**为绿色常亮。

### 5.2 鼠标悬停

- 悬停某个灯时显示工具提示（tooltip），包含：
  - session 名称或工作目录
  - 终端 TTY（如可用）
  - 当前状态
  - 当前任务或消息（如有）
  - 最后更新时间

### 5.3 点击行为

- **左键点击某个灯**：直接回到该灯对应的 Claude Code 终端 session。
  - iTerm2 / Terminal.app：按终端 TTY 精确定位窗口/标签页。
  - Ghostty：按 session 工作目录匹配终端并 `focus`（Ghostty 未暴露 TTY）。
  - cmux：通过 `cmux://` 深链接按 workspace + surface 精确切换面板，走 LaunchServices，**不依赖** TCC 授权或 cmux socket。
  - iTerm2 / Terminal.app / Ghostty 依赖 macOS 自动化(TCC)授权；Info.plist 已含 `NSAppleEventsUsageDescription`，首次点击需在弹框中点"允许"。
- 等待态/红灯不拦截点击；错误或等待详情通过 hover 或右键菜单查看。
- **右键 / Option 点击某个灯**：显示操作菜单（含「偏好设置…」入口）。

### 5.4 菜单项（右键 / 按住 Option 点击）

- 右键菜单显示可选项（按当前实现顺序）：
  - 当前状态（右键所指 session 的名称、状态、更新时间、任务/消息、目录/终端）
  - Sessions：数量
  - 重置此 session 为绿灯（⌘R）
  - 清除所有错误（把所有红灯 session 重置为空闲绿）
  - 偏好设置…（⌘,，打开偏好设置窗口，见 5.6）
  - 打开 Claude Code 上下文（⌘O，切回当前选中 session 的终端/面板）
  - 退出 CC Lights（⌘Q，带二次确认）

### 5.5 通知（可选）

- 当状态进入 🟡 等待决策时，发送系统通知：“Claude Code 需要你的决定”。
- 当状态变为 🔴 红色 时，发送系统通知：“Claude Code 执行出错”。
- 用户可在偏好设置「通知」分页关闭通知。

### 5.6 偏好设置窗口

- 从右键菜单「偏好设置…」（或 ⌘,）打开，参考 macOS 系统设置 / Shottr 风格，顶部工具栏分页。
- **Dock 图标**：打开窗口时 App 从 accessory 切换到 regular，在 Dock 显示应用图标；关闭窗口后切回 accessory，重新隐藏 Dock 图标。App 处于 regular 时提供标准主菜单（App / 编辑 / 窗口）。
- 分页：
  - **通用**：「登录时自动启动」开关；状态灯样式（**圆形灯** 默认 / **像素风格**）切换并实时预览。样式通过 `UserDefaults`（键 `statusLightStyle`）持久保存，两种样式共用同一套状态配色与动画语义。
  - **通知**：「启用系统通知」开关（见 5.5）。
  - **集成**：Claude Code Hook 配置状态，并提供「自动配置 Hook」「重新检查」「打开 settings.json」（见第 6 节）。
  - **关于**：应用图标、名称、版本与简介。

---

## 6. 集成与自动配置（零配置）

目标：用户只需安装并启动一次 App，无需手动安装 CLI 或编辑配置文件。

### 6.1 首次启动自动完成

1. 把 App 内置的 `cc-lights` 释放到与显示名/安装位置无关的固定路径：
   `~/Library/Application Support/ClaudeCodeStatusLight/cc-lights`。
2. 用该绝对路径把 Claude Code hooks 写入 `~/.claude/settings.json`（写入前自动备份为 `settings.json.bak-*`）。
3. 把该 helper 软链到可写的 `PATH` 目录（如 `/opt/homebrew/bin` 或 `/usr/local/bin`），同时提供 `cc-lights` 与旧名 `cc-statusctl`，保证任何位置的裸命令 hook 都能解析。

### 6.2 迁移与幂等修复

- CLI 旧名为 `cc-statusctl`；启动时自动把旧 `cc-statusctl` hook 迁移为 `cc-lights`，并保留 `cc-statusctl` 兼容别名。
- helper 路径与 App 显示名/安装位置无关，重命名或移动 App 不会破坏 hook。
- 每次启动都会刷新 helper 并修复已配置的 hook（幂等；仅在确有变化时才写 `settings.json.bak-*` 备份）。
- 可随时在偏好设置「集成」分页重跑上述流程。

### 6.3 写入的 hook 事件

| Claude Code Hook | 命令 | 结果状态 |
|------------------|------|----------|
| `UserPromptSubmit` | `cc-lights working` | 🟢 工作中 |
| `PreToolUse` | `cc-lights working` | 🟢 工作中 |
| `PostToolUse` | `cc-lights working` | 🟢 工作中 |
| `Notification`（`permission_prompt` / `elicitation_dialog`） | `cc-lights waiting` | 🟡 等待决策 |
| `Stop` | `cc-lights idle` | 🟢 空闲/完成 |
| `StopFailure` | `cc-lights error` | 🔴 错误 |
| `SessionEnd` | `cc-lights remove` | 移除该灯 |

---

## 7. 非功能需求

| 项目 | 要求 |
|------|------|
| 性能 | 状态切换延迟 < 100ms，不占用显著 CPU |
| 可靠性 | 状态必须与 Claude Code 内部真实状态严格一致 |
| 兼容性 | macOS 11+（Big Sur 及以上） |
| 自启动 | 支持用户设置“登录时启动” |
| 终端兼容 | 点灯定位支持 iTerm2 / Terminal.app（TTY）、Ghostty（工作目录）、cmux（`cmux://` 深链接） |
| 集成 | 首次启动零配置：自动安装 CLI、写入并幂等修复 Claude Code hooks |
| 数据存储 | 每 session 一个 JSON 文件；新版尽量兼容旧字段（可选解析），必要时做迁移 |

---

## 8. 待讨论 / 未定事项（可选）

- 等待态慢呼吸的超时时长是否可配置？（当前固定 30 秒）
- 是否支持显示当前任务名称（例如 “工作中: 编译 main.go”）？  
  → **已实现**：`--task` / `--message` 会在 hover 详情与右键「当前状态」中展示。

---

## 9. 成功标准

- 用户能在 0.5 秒内通过颜色、动画和提示判断 Claude Code 的当前状态。
- 用户不再因为不知状态而频繁切换到终端窗口。
- 首次使用无须阅读文档即可理解状态含义（或通过一次悬停即可理解）。

---

**PRD 结束**

如果你需要我根据这份 PRD 继续写**技术方案**（例如如何与 Claude Code 通信、如何实现 macOS 状态栏图标、如何捕获等待态/红灯事件），请告诉我。