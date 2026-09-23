import Foundation
import StatusLightCore

// MARK: - 语言选择 / Language selection

/// 支持的界面语言。新增语言时：加一个 case，给 `tr(...)` 增加一个可选参数，
/// 并在各字符串处按需补充翻译（缺失自动回退英文），已有调用点无需改动。
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh"

    static let overrideDefaultsKey = "appLanguageOverride"

    /// 用户在偏好设置里的显式选择；为 nil 表示跟随系统。
    static var override: AppLanguage? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overrideDefaultsKey) else {
                return nil
            }
            return AppLanguage(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: overrideDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: overrideDefaultsKey)
            }
        }
    }

    /// 当前生效语言：优先用户选择，否则按系统首选语言推断，最后回退英文。
    static var current: AppLanguage {
        override ?? systemDefault
    }

    static var systemDefault: AppLanguage {
        for language in Locale.preferredLanguages {
            let lower = language.lowercased()
            if lower.hasPrefix("zh") { return .chinese }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }

    /// 在语言选择器里显示的名称（用各自语言书写，便于识别）。
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

/// 通知：界面语言发生变化，需要刷新菜单栏、主菜单与已打开的偏好设置窗口。
extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("ClaudeCodeStatusLight.appLanguageDidChange")
}

/// 选取当前语言对应的字符串。`en` 为基准，缺失翻译时回退英文。
/// 新增第三种语言时给此函数加一个带默认值的可选参数即可，不影响既有调用。
func tr(_ en: String, zh: String) -> String {
    switch AppLanguage.current {
    case .english: return en
    case .chinese: return zh
    }
}

// MARK: - 字符串目录 / String catalog

/// 全部界面字符串集中在此，方便统一维护与新增语言。
enum Loc {
    // 状态名（菜单/悬停里展示）
    static func stateName(_ state: StatusState) -> String {
        switch state {
        case .offline: return tr("No session", zh: "无会话")
        case .working: return tr("Working", zh: "工作中")
        case .waiting: return tr("Waiting", zh: "等待决策")
        case .idle: return tr("Idle", zh: "空闲/完成")
        case .error: return tr("Error", zh: "错误")
        }
    }

    static var stateWaitingTimedOut: String {
        tr("Waiting (timed out)", zh: "等待决策超时")
    }

    // 灯样式
    static var lightStyleRound: String { tr("Round", zh: "圆形灯") }
    static var lightStylePixel: String { tr("Pixel", zh: "像素风格") }
    static var lightStylePixelRing: String { tr("Ring", zh: "像素圆环") }
    static var lightStylePixelSquare: String { tr("Square", zh: "像素方块") }
    static var lightStylePixelDiamond: String { tr("Diamond", zh: "像素菱形") }
    static var lightStylePixelGlow: String { tr("Glow", zh: "像素光晕") }
    static var lightStylePixelCrab: String { tr("Crab", zh: "像素螃蟹") }
    static var lightStylePixelRobot: String { tr("Robot", zh: "像素机器人") }
    static var lightStylePixelCat: String { tr("Cat", zh: "像素猫咪") }
    static var lightStylePixelBlock: String { tr("Blocks", zh: "大像素块") }
    static var lightStylePixelBlock3x3: String { tr("Blocks 3×3", zh: "3×3 大像素块") }
    static var lightStylePixelBlockRing: String { tr("Hollow Circle", zh: "空心圆") }

    // 状态栏菜单
    static var noSession: String { tr("No agent session", zh: "无 agent 会话") }
    static var tooltipNoSession: String {
        tr("No agent session\nRight-click for options", zh: "无 agent 会话\n右键打开设置")
    }
    static func sessionsCount(_ count: Int) -> String {
        tr("Sessions: \(count)", zh: "Sessions：\(count)")
    }
    static var lightStyleMenu: String { tr("Light style", zh: "灯样式") }
    static var resetSessionToGreen: String { tr("Reset this session to green", zh: "重置此 session 为绿灯") }
    static var clearAllErrors: String { tr("Clear all errors", zh: "清除所有错误") }
    static var clearAllLights: String { tr("Clear all lights", zh: "清空所有灯") }
    static var preferences: String { tr("Preferences…", zh: "偏好设置…") }
    static var openAgentContext: String { tr("Open agent context", zh: "打开会话上下文") }
    static var quitCCLights: String { tr("Quit CC Lights…", zh: "退出 CC Lights...") }

    // 悬停/详情行
    static func lineStatus(_ value: String) -> String { tr("Status: \(value)", zh: "状态：\(value)") }
    static func lineUpdated(_ value: String) -> String { tr("Updated: \(value)", zh: "更新：\(value)") }
    static func lineTask(_ value: String) -> String { tr("Task: \(value)", zh: "任务：\(value)") }
    static func lineMessage(_ value: String) -> String { tr("Message: \(value)", zh: "消息：\(value)") }
    static func lineDirectory(_ value: String) -> String { tr("Directory: \(value)", zh: "目录：\(value)") }
    static func lineTerminal(_ value: String) -> String { tr("Terminal: \(value)", zh: "终端：\(value)") }
    static func lineCmux(_ value: String) -> String { tr("cmux: \(value)", zh: "cmux：\(value)") }

    // 相对时间
    static var timeJustNow: String { tr("just now", zh: "刚刚") }
    static func timeSecondsAgo(_ n: Int) -> String { tr("\(n)s ago", zh: "\(n) 秒前") }
    static func timeMinutesAgo(_ n: Int) -> String { tr("\(n)m ago", zh: "\(n) 分钟前") }
    static func timeHoursAgo(_ n: Int) -> String { tr("\(n)h ago", zh: "\(n) 小时前") }
    static func timeDaysAgo(_ n: Int) -> String { tr("\(n)d ago", zh: "\(n) 天前") }

    // 通用按钮
    static var buttonOK: String { tr("OK", zh: "知道了") }
    static var buttonQuit: String { tr("Quit", zh: "退出") }
    static var buttonCancel: String { tr("Cancel", zh: "取消") }

    // 主菜单
    static func menuAbout(_ appName: String) -> String { tr("About \(appName)", zh: "关于 \(appName)") }
    static func menuHide(_ appName: String) -> String { tr("Hide \(appName)", zh: "隐藏 \(appName)") }
    static var menuHideOthers: String { tr("Hide Others", zh: "隐藏其他") }
    static var menuShowAll: String { tr("Show All", zh: "全部显示") }
    static func menuQuit(_ appName: String) -> String { tr("Quit \(appName)", zh: "退出 \(appName)") }
    static var menuEdit: String { tr("Edit", zh: "编辑") }
    static var menuUndo: String { tr("Undo", zh: "撤销") }
    static var menuRedo: String { tr("Redo", zh: "重做") }
    static var menuCut: String { tr("Cut", zh: "剪切") }
    static var menuCopy: String { tr("Copy", zh: "复制") }
    static var menuPaste: String { tr("Paste", zh: "粘贴") }
    static var menuSelectAll: String { tr("Select All", zh: "全选") }
    static var menuWindow: String { tr("Window", zh: "窗口") }
    static var menuMinimize: String { tr("Minimize", zh: "最小化") }
    static var menuZoom: String { tr("Zoom", zh: "缩放") }
    static var menuClose: String { tr("Close", zh: "关闭") }

    // 通用/系统告警
    static var initFileErrorTitle: String { tr("Couldn't initialize the status file", zh: "无法初始化状态文件") }
    static var resetFailedTitle: String { tr("Reset failed", zh: "重置失败") }
    static var resetFailedUnknownSession: String {
        tr("Couldn't determine which session to reset.", zh: "无法确定要重置的 session。")
    }
    static var clearErrorsFailedTitle: String { tr("Couldn't clear errors", zh: "清除错误失败") }
    static var clearAllLightsFailedTitle: String { tr("Couldn't clear lights", zh: "清空灯失败") }
    static var readSessionErrorTitle: String { tr("Couldn't read session status", zh: "无法读取 session 状态") }

    // 退出确认
    static var quitConfirmTitle: String { tr("Quit CC Lights?", zh: "退出 CC Lights？") }
    static var quitConfirmBody: String {
        tr("The menu bar lights will stop showing agent status.", zh: "状态栏指示灯将停止显示 agent 状态。")
    }

    // 打开上下文失败
    static var cannotOpenSessionTitle: String {
        tr("Couldn't open the agent session", zh: "无法打开该会话")
    }
    static func cannotOpenSessionBody(command: String) -> String {
        tr(
            """
            The status is missing terminal info to locate the session, or the terminal app isn't running.

            Have your hook or the CLI write the terminal info for the current session, for example:
            \(command)

            If the session runs in cmux, include --cmux-workspace and --cmux-surface.
            """,
            zh: """
            状态里缺少可定位的终端信息，或对应终端 App 当前没有运行。

            请让 hook 或 CLI 写入当前 session 实际所在的终端信息，例如：
            \(command)

            如果 session 在 cmux 中，请写入 --cmux-workspace 和 --cmux-surface。
            """
        )
    }
    static var noSessionToOpenBody: String {
        tr("There's no agent session to open right now.", zh: "当前没有可打开的会话。")
    }

    // 通知
    static var notifyWaitingTitle: String { tr("Agent needs your decision", zh: "Agent 需要你的决定") }
    static var notifyWaitingBody: String {
        tr("Return to the agent session to make a choice.", zh: "请回到对应会话完成选择。")
    }
    static var notifyErrorTitle: String { tr("Agent hit an error", zh: "Agent 执行出错") }
    static var notifyErrorBody: String { tr("Check the agent session logs.", zh: "请查看对应会话的日志。") }

    // Claude Code 集成检查
    static var autoConfiguredTitle: String {
        tr("Claude Code integration configured automatically", zh: "已自动配置 Claude Code 集成")
    }
    static var autoConfiguredBody: String {
        tr(
            "The status-light hooks were written to ~/.claude/settings.json (the original was backed up).\n\nRestart Claude Code for the change to take effect.",
            zh: "已把状态灯 hook 写入 ~/.claude/settings.json（原文件已备份）。\n\n请重启 Claude Code 使配置生效。"
        )
    }
    static var hookConfiguredTitle: String { tr("✅ Claude Code hooks configured", zh: "✅ Claude Code Hook 已配置") }
    static var hookNotConfiguredTitle: String {
        tr("⚠️ No Claude Code hook configuration detected", zh: "⚠️ 未检测到 Claude Code Hook 配置")
    }
    static var hookConfiguredBody: String {
        tr(
            "The lights will follow Claude Code's status automatically.\n\nTo adjust, edit the hooks in ~/.claude/settings.json.",
            zh: "状态灯将自动跟随 Claude Code 的状态变化。\n\n如需调整，请编辑 ~/.claude/settings.json 中的 hooks 配置。"
        )
    }
    /// hook 未配置时的说明；`json` 为示例配置块，两种语言共用。
    static func hookNotConfiguredBody(json: String) -> String {
        tr(
            """
            The lights need Claude Code's hook configuration to change color automatically.

            Add the following to ~/.claude/settings.json:

            \(json)

            Or click "Auto-configure Hook" in the right-click menu and the app will merge it in (backing up the original).
            """,
            zh: """
            状态灯需要 Claude Code 的 Hook 配置才能自动变化颜色。

            请在 ~/.claude/settings.json 中添加以下配置：

            \(json)

            或在右键菜单中点击「为我自动配置 Hook」，App 会自动合并（并备份原文件）。
            """
        )
    }
    static var autoConfigureButton: String { tr("Auto-configure for me", zh: "为我自动配置") }
    static var invalidSettingsError: String {
        tr(
            "~/.claude/settings.json isn't valid JSON. Please fix it manually and try again.",
            zh: "~/.claude/settings.json 不是合法的 JSON，请先手动修复后再试。"
        )
    }
    static var hooksWrittenTitle: String { tr("✅ Claude Code hooks written", zh: "✅ 已写入 Claude Code Hook 配置") }
    static var hooksMergedBody: String {
        tr(
            "The status-light hooks were merged into ~/.claude/settings.json (the original was backed up as settings.json.bak-*).\n\nRestart Claude Code for the change to take effect.",
            zh: "已把状态灯 hook 合并进 ~/.claude/settings.json（原文件已备份为 settings.json.bak-*）。\n\n请重启 Claude Code 使配置生效。"
        )
    }
    static var hooksNoChangeBody: String { tr("No changes needed — the hooks already exist.", zh: "无需改动，hook 已存在。") }
    static var writeConfigFailedTitle: String { tr("Couldn't write the configuration", zh: "写入配置失败") }

    // MARK: 偏好设置窗口

    static var prefsWindowTitle: String { tr("CC Lights Preferences", zh: "CC Lights 偏好设置") }

    static var tabGeneral: String { tr("General", zh: "通用") }
    static var tabNotifications: String { tr("Notifications", zh: "通知") }
    static var tabIntegration: String { tr("Integration", zh: "集成") }
    static var tabAbout: String { tr("About", zh: "关于") }

    // 通用分页
    static var generalStartupHeader: String { tr("Startup", zh: "启动") }
    static var launchAtLoginCheckbox: String { tr("Launch CC Lights at login", zh: "登录时自动启动 CC Lights") }
    static var launchAtLoginHelp: String {
        tr(
            "When enabled, a launch item is installed in ~/Library/LaunchAgents to start the menu bar lights automatically at login.",
            zh: "开启后会在 ~/Library/LaunchAgents 中安装启动项，登录时自动拉起菜单栏指示灯。"
        )
    }
    static var lightStyleHeader: String { tr("Status light style", zh: "状态灯样式") }
    static var lightStylePreviewHelp: String {
        tr(
            "Preview, left to right: no session / idle / waiting / error.",
            zh: "预览从左到右依次为：无会话 / 空闲 / 等待决策 / 错误。"
        )
    }
    static var perSessionStyleHeader: String { tr("Per-session light style", zh: "每个会话的灯样式") }
    static var perSessionStyleEmpty: String { tr("No active sessions right now", zh: "当前没有活动会话") }
    static var perSessionStyleHelp: String {
        tr(
            "Override the light style for a specific session. You can also right-click a light to switch it.",
            zh: "为单个会话单独设置灯样式（覆盖上面的默认样式）；也可以右键某盏灯快速切换。"
        )
    }
    static var launchToggleErrorTitle: String {
        tr("Couldn't update the launch-at-login setting", zh: "无法更新登录启动设置")
    }

    // 语言
    static var languageHeader: String { tr("Language", zh: "语言") }
    static var languageSystemOption: String { tr("System", zh: "跟随系统") }
    static var languageHelp: String {
        tr(
            "Choose the interface language. \"System\" follows your macOS language settings.",
            zh: "选择界面语言。「跟随系统」会使用 macOS 的语言设置。"
        )
    }

    // 通知分页
    static var notificationsHeader: String { tr("System notifications", zh: "系统通知") }
    static var enableNotificationsCheckbox: String { tr("Enable system notifications", zh: "启用系统通知") }
    static var notificationsHelp: String {
        tr(
            "Send a system notification when an agent session starts \"waiting\" (needs your approval/confirmation) or hits an error. Available only when running as a .app.",
            zh: "当某个会话进入「等待决策」（需要你授权/确认）或「执行出错」时，发送一条系统通知提醒你。仅在以 .app 形式运行时可用。"
        )
    }

    // 集成分页
    static var integrationHeader: String { tr("Tool integrations", zh: "工具集成") }
    static var integrationHelp: String {
        tr(
            "Configure status light integration for Claude Code, Codex, OpenCode, pi, and Hermes. Each tool is auto-configured on first launch.",
            zh: "为 Claude Code、Codex、OpenCode、pi、Hermes 配置状态灯接入。每个工具都会在首次启动时自动配置。"
        )
    }
    static var integrationAutoConfigureButton: String { tr("Auto-configure Hook", zh: "自动配置 Hook") }
    static var integrationRecheckButton: String { tr("Re-check", zh: "重新检查") }
    static var integrationOpenSettingsButton: String { tr("Open config", zh: "打开配置") }
    static var integrationConfiguredStatusFormat: String {
        tr("%@ is configured — the lights follow its status automatically.", zh: "%@ 已配置，指示灯会自动跟随其状态。")
    }
    static var integrationNotConfiguredStatusFormat: String {
        tr("%@ isn't configured — tap Auto-configure to enable it.", zh: "%@ 未配置，点击「自动配置」即可启用。")
    }
    // 各工具说明（紧跟在每块状态下方）。
    static var integrationClaudeHelp: String {
        tr(
            "Lights via hooks in ~/.claude/settings.json.",
            zh: "通过 ~/.claude/settings.json 中的 hooks 驱动。"
        )
    }
    static var integrationCodexHelp: String {
        tr(
            "Lights via hooks in ~/.codex/hooks.json.",
            zh: "通过 ~/.codex/hooks.json 中的 hooks 驱动。"
        )
    }
    static var integrationOpenCodeHelp: String {
        tr(
            "Lights via the plugin at ~/.config/opencode/plugins/cc-lights.js.",
            zh: "通过 ~/.config/opencode/plugins/cc-lights.js 插件驱动。"
        )
    }

    // pi 集成
    static var piAutoConfiguredTitle: String {
        tr("pi integration configured automatically", zh: "已自动配置 pi 集成")
    }
    static var piAutoConfiguredBody: String {
        tr(
            "The status-light extension was written to ~/.pi/agent/extensions/.\n\nRestart pi for the change to take effect.",
            zh: "已把状态灯扩展写入 ~/.pi/agent/extensions/。\n\n请重启 pi 使配置生效。"
        )
    }
    static var piConfiguredTitle: String { tr("✅ pi extension installed", zh: "✅ pi 扩展已安装") }
    static var piNotConfiguredTitle: String {
        tr("⚠️ No pi extension detected", zh: "⚠️ 未检测到 pi 扩展")
    }
    static var piConfiguredBody: String {
        tr(
            "The lights will follow pi's status automatically.\n\nTo adjust, edit ~/.pi/agent/extensions/cc-lights.ts.",
            zh: "状态灯将自动跟随 pi 的状态变化。\n\n如需调整，请编辑 ~/.pi/agent/extensions/cc-lights.ts。"
        )
    }
    static var piNotConfiguredBody: String {
        tr(
            "The lights need the pi extension to change color automatically.\n\nClick \"Auto-configure for me\" and the app will write ~/.pi/agent/extensions/cc-lights.ts.",
            zh: "状态灯需要 pi 扩展才能自动变化颜色。\n\n点击「为我自动配置」后，App 会写入 ~/.pi/agent/extensions/cc-lights.ts。"
        )
    }
    static var piExtensionWrittenTitle: String { tr("✅ pi extension written", zh: "✅ 已写入 pi 扩展") }
    static var piExtensionWrittenBody: String {
        tr(
            "The status-light extension was written to ~/.pi/agent/extensions/cc-lights.ts.\n\nRestart pi for the change to take effect.",
            zh: "已把状态灯扩展写入 ~/.pi/agent/extensions/cc-lights.ts。\n\n请重启 pi 使配置生效。"
        )
    }
    static var integrationPiHelp: String {
        tr(
            "Lights via the extension at ~/.pi/agent/extensions/cc-lights.ts.",
            zh: "通过 ~/.pi/agent/extensions/cc-lights.ts 扩展驱动。"
        )
    }

    // Hermes Agent 集成
    static var hermesAutoConfiguredTitle: String {
        tr("Hermes integration configured automatically", zh: "已自动配置 Hermes 集成")
    }
    static var hermesAutoConfiguredBody: String {
        tr(
            "The status-light plugin was written to ~/.hermes/plugins/cc-lights/.\n\nStart a new Hermes session for the change to take effect.",
            zh: "已把状态灯插件写入 ~/.hermes/plugins/cc-lights/。\n\n请新开 Hermes 会话使配置生效。"
        )
    }
    static var hermesConfiguredTitle: String { tr("✅ Hermes plugin installed", zh: "✅ Hermes 插件已安装") }
    static var hermesNotConfiguredTitle: String {
        tr("⚠️ No Hermes plugin detected", zh: "⚠️ 未检测到 Hermes 插件")
    }
    static var hermesConfiguredBody: String {
        tr(
            "The lights will follow Hermes session status automatically.\n\nTo adjust, edit ~/.hermes/plugins/cc-lights/__init__.py.",
            zh: "状态灯将自动跟随 Hermes 会话的状态变化。\n\n如需调整，请编辑 ~/.hermes/plugins/cc-lights/__init__.py。"
        )
    }
    static var hermesNotConfiguredBody: String {
        tr(
            "The lights need the Hermes plugin to change color automatically.\n\nClick \"Auto-configure for me\" and the app will write ~/.hermes/plugins/cc-lights/ and run `hermes plugins enable cc-lights`.",
            zh: "状态灯需要 Hermes 插件才能自动变化颜色。\n\n点击「为我自动配置」后，App 会写入 ~/.hermes/plugins/cc-lights/ 并执行 `hermes plugins enable cc-lights`。"
        )
    }
    static var hermesPluginWrittenTitle: String { tr("✅ Hermes plugin written", zh: "✅ 已写入 Hermes 插件") }
    static var hermesPluginWrittenBody: String {
        tr(
            "The status-light plugin was written to ~/.hermes/plugins/cc-lights/ and enabled.\n\nStart a new Hermes session for the change to take effect.",
            zh: "已把状态灯插件写入 ~/.hermes/plugins/cc-lights/ 并启用。\n\n请新开 Hermes 会话使配置生效。"
        )
    }
    static var hermesEnableManualBody: String {
        tr(
            "The plugin files were written to ~/.hermes/plugins/cc-lights/, but the hermes CLI was not found, so the plugin could not be enabled automatically.\n\nPlease run manually: hermes plugins enable cc-lights",
            zh: "插件文件已写入 ~/.hermes/plugins/cc-lights/，但未找到 hermes CLI，无法自动启用。\n\n请手动执行：hermes plugins enable cc-lights"
        )
    }
    static var integrationHermesHelp: String {
        tr(
            "Lights via the plugin at ~/.hermes/plugins/cc-lights/.",
            zh: "通过 ~/.hermes/plugins/cc-lights/ 插件驱动。"
        )
    }

    // Codex 集成
    static var codexAutoConfiguredTitle: String {
        tr("Codex integration configured automatically", zh: "已自动配置 Codex 集成")
    }
    static var codexAutoConfiguredBody: String {
        tr(
            "The status-light hooks were written to ~/.codex/hooks.json (the original was backed up).\n\nRestart Codex for the change to take effect.",
            zh: "已把状态灯 hook 写入 ~/.codex/hooks.json（原文件已备份）。\n\n请重启 Codex 使配置生效。"
        )
    }
    static var codexHookConfiguredTitle: String { tr("✅ Codex hooks configured", zh: "✅ Codex Hook 已配置") }
    static var codexHookNotConfiguredTitle: String {
        tr("⚠️ No Codex hook configuration detected", zh: "⚠️ 未检测到 Codex Hook 配置")
    }
    static var codexHookConfiguredBody: String {
        tr(
            "The lights will follow Codex's status automatically.\n\nTo adjust, edit the hooks in ~/.codex/hooks.json.",
            zh: "状态灯将自动跟随 Codex 的状态变化。\n\n如需调整，请编辑 ~/.codex/hooks.json 中的 hooks 配置。"
        )
    }
    static var codexHookNotConfiguredBody: String {
        tr(
            "The lights need Codex's hook configuration to change color automatically.\n\nClick \"Auto-configure for me\" and the app will write ~/.codex/hooks.json (backing up the original).",
            zh: "状态灯需要 Codex 的 Hook 配置才能自动变化颜色。\n\n点击「为我自动配置」后，App 会写入 ~/.codex/hooks.json（并备份原文件）。"
        )
    }
    static var codexInvalidHooksError: String {
        tr(
            "~/.codex/hooks.json isn't valid JSON. Please fix it manually and try again.",
            zh: "~/.codex/hooks.json 不是合法的 JSON，请先手动修复后再试。"
        )
    }
    static var codexHooksWrittenTitle: String { tr("✅ Codex hooks written", zh: "✅ 已写入 Codex Hook 配置") }
    static var codexHooksMergedBody: String {
        tr(
            "The status-light hooks were merged into ~/.codex/hooks.json (the original was backed up as hooks.json.bak-*).\n\nRestart Codex for the change to take effect.",
            zh: "已把状态灯 hook 合并进 ~/.codex/hooks.json（原文件已备份为 hooks.json.bak-*）。\n\n请重启 Codex 使配置生效。"
        )
    }

    // OpenCode 集成
    static var opencodeAutoConfiguredTitle: String {
        tr("OpenCode integration configured automatically", zh: "已自动配置 OpenCode 集成")
    }
    static var opencodeAutoConfiguredBody: String {
        tr(
            "The status-light plugin was written to ~/.config/opencode/plugins/.\n\nRestart OpenCode for the change to take effect.",
            zh: "已把状态灯插件写入 ~/.config/opencode/plugins/。\n\n请重启 OpenCode 使配置生效。"
        )
    }
    static var opencodeConfiguredTitle: String { tr("✅ OpenCode plugin installed", zh: "✅ OpenCode 插件已安装") }
    static var opencodeNotConfiguredTitle: String {
        tr("⚠️ No OpenCode plugin detected", zh: "⚠️ 未检测到 OpenCode 插件")
    }
    static var opencodeConfiguredBody: String {
        tr(
            "The lights will follow OpenCode's status automatically.\n\nTo adjust, edit ~/.config/opencode/plugins/cc-lights.js.",
            zh: "状态灯将自动跟随 OpenCode 的状态变化。\n\n如需调整，请编辑 ~/.config/opencode/plugins/cc-lights.js。"
        )
    }
    static var opencodeNotConfiguredBody: String {
        tr(
            "The lights need the OpenCode plugin to change color automatically.\n\nClick \"Auto-configure for me\" and the app will write ~/.config/opencode/plugins/cc-lights.js.",
            zh: "状态灯需要 OpenCode 插件才能自动变化颜色。\n\n点击「为我自动配置」后，App 会写入 ~/.config/opencode/plugins/cc-lights.js。"
        )
    }
    static var opencodePluginWrittenTitle: String { tr("✅ OpenCode plugin written", zh: "✅ 已写入 OpenCode 插件") }
    static var opencodePluginWrittenBody: String {
        tr(
            "The status-light plugin was written to ~/.config/opencode/plugins/cc-lights.js.\n\nRestart OpenCode for the change to take effect.",
            zh: "已把状态灯插件写入 ~/.config/opencode/plugins/cc-lights.js。\n\n请重启 OpenCode 使配置生效。"
        )
    }

    // 检查更新
    static var checkForUpdates: String { tr("Check for Updates…", zh: "检查更新…") }
    static func updateAvailable(_ version: String) -> String {
        tr("New version \(version) is available", zh: "发现新版本 \(version)")
    }
    static var updateUpToDateTitle: String { tr("You're up to date", zh: "已是最新版本") }
    static var updateUpToDateBody: String {
        tr("CC Lights is up to date.", zh: "当前已是最新版本的 CC Lights。")
    }
    static var updateAvailableTitle: String { tr("A new version is available", zh: "发现新版本") }
    static func updateAvailableBody(current: String, latest: String) -> String {
        tr(
            "You're running \(current). Version \(latest) is available. Open the GitHub Releases page to download it.",
            zh: "当前版本 \(current)，最新版本 \(latest)。打开 GitHub Releases 页面即可下载。"
        )
    }
    static var buttonUpdate: String { tr("Update", zh: "去更新") }
    static var updateCheckFailedTitle: String { tr("Update check failed", zh: "检查更新失败") }
    static var updateCheckFailedBody: String {
        tr(
            "Couldn't reach GitHub to check for updates. Please try again later.",
            zh: "无法访问 GitHub 检查更新，请稍后再试。"
        )
    }

    // 关于分页
    static var aboutDescription: String {
        tr(
            "Shows each agent session's status in the menu bar with traffic lights: green for idle/working, yellow when waiting for a decision, red on error. Click a light to jump back to its terminal.",
            zh: "在菜单栏用交通灯的方式展示每个 agent 会话的状态：绿色空闲/工作、黄色等待决策、红色出错。点击指示灯可直接切回对应终端。"
        )
    }
    static func aboutVersion(_ short: String) -> String { tr("Version \(short)", zh: "版本 \(short)") }
    static func aboutVersionBuild(_ short: String, _ build: String) -> String {
        tr("Version \(short) (\(build))", zh: "版本 \(short) (\(build))")
    }
}
