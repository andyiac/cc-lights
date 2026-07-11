import AppKit
import Darwin
import Foundation
import StatusLightCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var statusFileMonitor: StatusFileMonitor?
    private var configMonitor: ClaudeCodeConfigMonitor?
    private let notificationController = NotificationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try StatusFileStore.ensureDirectoryExists()
            // 兜底清理：被强杀/崩溃而未触发 SessionEnd 的残留 session（超过 24 小时未更新）。
            try StatusFileStore.pruneStale(olderThan: 24 * 60 * 60)
        } catch {
            NSAlert.showError(title: "无法初始化状态文件", message: error.localizedDescription)
        }

        notificationController.requestAuthorizationIfNeeded()

        let controller = StatusBarController(notificationController: notificationController)
        statusBarController = controller

        // 启动即自动落地内置 CLI 到稳定路径，并自动配置/修复 Claude Code hook（无需手动）。
        ClaudeCodeConfigChecker.setUpHooksOnLaunch()

        let monitor = StatusFileMonitor { [weak controller] payloads in
            controller?.apply(payloads)
        }
        statusFileMonitor = monitor
        monitor.start()

        let configMonitor = ClaudeCodeConfigMonitor { [weak controller] configured in
            controller?.updateHooksConfigured(configured)
        }
        self.configMonitor = configMonitor
        configMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusFileMonitor?.stop()
        configMonitor?.stop()
    }
}

final class StatusBarController: NSObject {
    private let notificationController: NotificationController
    private var currentPayload = StatusPayload(state: .offline)
    private var currentSessions: [StatusPayload] = []
    private var statusItems: [NSStatusItem] = []
    private var visiblePayloadsByTag: [Int: StatusPayload] = [:]
    private var statusAnimator: Timer?
    private var waitingTimeoutTimer: Timer?
    private var errorFlashStartBySessionID: [String: Date] = [:]
    private let waitingTimeoutDelay: TimeInterval = 30
    private let errorFlashStep: TimeInterval = 0.2
    private let errorFlashCount = 3
    private let placeholderTag = -1
    private let cmuxDefaultBundleIdentifier = "com.cmuxterm.app"
    private var isHooksConfigured = false
    private var iconStyle = StatusLightStyle.current

    init(notificationController: NotificationController) {
        self.notificationController = notificationController
        super.init()
        apply([])
    }

    func apply(_ payloads: [StatusPayload]) {
        DispatchQueue.main.async {
            let previousState = self.currentPayload.state
            var previousPayloadsBySessionID: [String: StatusPayload] = [:]
            for payload in self.currentSessions {
                previousPayloadsBySessionID[payload.sessionID] = payload
            }

            let payload = StatusFileStore.aggregate(payloads)
            let now = Date()
            self.updateErrorFlashes(
                for: payloads,
                previousPayloadsBySessionID: previousPayloadsBySessionID,
                now: now
            )

            self.currentSessions = payloads
            self.currentPayload = payload

            self.rebuildStatusItems()

            self.scheduleWaitingTimeout(now: now)
            self.updateStatusAnimation(now: now)

            if previousState != payload.state {
                self.notificationController.notifyIfNeeded(from: previousState, to: payload)
            }
        }
    }

    // MARK: - 状态动画

    private var animationStartTime: Date?

    private struct AnimationConfiguration {
        var minAlpha: CGFloat
        var period: TimeInterval
    }

    private var errorFlashDuration: TimeInterval {
        TimeInterval(errorFlashCount) * errorFlashStep * 2
    }

    private func animationConfiguration(for payload: StatusPayload, now: Date = Date()) -> AnimationConfiguration? {
        switch payload.state {
        case .working:
            return AnimationConfiguration(minAlpha: 0.3, period: 1.0)
        case .waiting:
            guard now.timeIntervalSince(payload.updatedAt) >= waitingTimeoutDelay else {
                return nil
            }
            return AnimationConfiguration(minAlpha: 0.6, period: 3.0)
        case .offline, .idle, .error:
            return nil
        }
    }

    private func scheduleWaitingTimeout(now: Date = Date()) {
        waitingTimeoutTimer?.invalidate()
        waitingTimeoutTimer = nil

        let nextDelay = currentSessions
            .filter { $0.state == .waiting }
            .map { waitingTimeoutDelay - now.timeIntervalSince($0.updatedAt) }
            .filter { $0 > 0 }
            .min()

        guard let nextDelay else {
            return
        }

        waitingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: max(nextDelay, 0.1), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.waitingTimeoutTimer = nil
            let now = Date()
            self.refreshStatusItemIcons()
            self.updateStatusAnimation(now: now)
        }
    }

    private func updateStatusAnimation(now: Date = Date()) {
        if hasActiveAnimation(now: now) {
            startStatusAnimation()
        } else {
            stopStatusAnimation()
        }
    }

    private func hasActiveAnimation(now: Date = Date()) -> Bool {
        currentSessions.contains { animationConfiguration(for: $0, now: now) != nil }
            || errorFlashStartBySessionID.values.contains { now.timeIntervalSince($0) < errorFlashDuration }
    }

    private func startStatusAnimation() {
        guard statusAnimator == nil else { return }

        animationStartTime = Date()

        statusAnimator = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.animationStartTime else { return }
            let now = Date()
            let elapsed = now.timeIntervalSince(startTime)
            var hasAnimation = false

            DispatchQueue.main.async {
                for statusItem in self.statusItems {
                    guard let button = statusItem.button else {
                        continue
                    }

                    guard let payload = self.visiblePayloadsByTag[button.tag] else {
                        button.alphaValue = 1.0
                        continue
                    }

                    if let alpha = self.errorFlashAlpha(for: payload, now: now) {
                        button.alphaValue = alpha
                        hasAnimation = true
                        continue
                    }

                    if let configuration = self.animationConfiguration(for: payload, now: now) {
                        button.alphaValue = self.pulsingAlpha(
                            elapsed: elapsed,
                            configuration: configuration
                        )
                        hasAnimation = true
                        continue
                    }

                    button.alphaValue = 1.0
                }

                if !hasAnimation {
                    self.stopStatusAnimation()
                }
            }
        }
    }

    private func stopStatusAnimation() {
        statusAnimator?.invalidate()
        statusAnimator = nil
        animationStartTime = nil
        statusItems.forEach { $0.button?.alphaValue = 1.0 }
    }

    private func pulsingAlpha(elapsed: TimeInterval, configuration: AnimationConfiguration) -> CGFloat {
        let phase = (elapsed / configuration.period).truncatingRemainder(dividingBy: 1.0)
        return configuration.minAlpha + (1 - configuration.minAlpha) * CGFloat(0.5 + 0.5 * cos(phase * 2 * .pi))
    }

    private func errorFlashAlpha(for payload: StatusPayload, now: Date) -> CGFloat? {
        guard payload.state == .error,
              let startTime = errorFlashStartBySessionID[payload.sessionID] else {
            return nil
        }

        let elapsed = now.timeIntervalSince(startTime)
        guard elapsed < errorFlashDuration else {
            errorFlashStartBySessionID[payload.sessionID] = nil
            return nil
        }

        let stepIndex = Int(elapsed / errorFlashStep)
        return stepIndex.isMultiple(of: 2) ? 1.0 : 0.2
    }

    private func updateErrorFlashes(
        for payloads: [StatusPayload],
        previousPayloadsBySessionID: [String: StatusPayload],
        now: Date
    ) {
        let activeSessionIDs = Set(payloads.map(\.sessionID))
        errorFlashStartBySessionID = errorFlashStartBySessionID.filter { activeSessionIDs.contains($0.key) }

        for payload in payloads where payload.state == .error {
            let previousPayload = previousPayloadsBySessionID[payload.sessionID]
            guard previousPayload?.state != .error || previousPayload?.updatedAt != payload.updatedAt else {
                continue
            }
            errorFlashStartBySessionID[payload.sessionID] = now
        }
    }

    private func rebuildStatusItems() {
        statusItems.forEach(NSStatusBar.system.removeStatusItem)
        statusItems.removeAll()
        visiblePayloadsByTag.removeAll()

        let sortedSessions = currentSessions.sorted(by: sessionSort)
        if sortedSessions.isEmpty {
            let statusItem = makeStatusItem(tag: placeholderTag)
            configure(statusItem, payload: nil)
            statusItems.append(statusItem)
            return
        }

        for (index, payload) in sortedSessions.enumerated() {
            let statusItem = makeStatusItem(tag: index)
            visiblePayloadsByTag[index] = payload
            configure(statusItem, payload: payload)
            statusItems.append(statusItem)
        }
    }

    private func refreshStatusItemIcons() {
        for statusItem in statusItems {
            guard let button = statusItem.button else {
                continue
            }

            configure(statusItem, payload: visiblePayloadsByTag[button.tag])
        }
    }

    private func makeStatusItem(tag: Int) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: iconStyle.statusItemLength)
        statusItem.button?.tag = tag
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return statusItem
    }

    private func configure(_ statusItem: NSStatusItem, payload: StatusPayload?) {
        guard let button = statusItem.button else {
            return
        }

        let state = payload?.state ?? .offline
        statusItem.length = iconStyle.statusItemLength
        button.image = StatusIcon.image(for: state, style: iconStyle)
        button.title = ""
        button.toolTip = payload.map(tooltip(for:)) ?? "无 Claude Code session\n右键打开设置"
        button.alphaValue = 1.0
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let shouldShowMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true

        if shouldShowMenu {
            showMenu(from: sender)
        } else if let payload = visiblePayloadsByTag[sender.tag] {
            focusClaudeCodeContext(for: payload)
        } else {
            showMenu(from: sender)
        }
    }

    private func showMenu(from sender: NSStatusBarButton) {
        guard let statusItem = statusItems.first(where: { $0.button === sender }) else {
            return
        }

        statusItem.menu = buildMenu(for: visiblePayloadsByTag[sender.tag])
        sender.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu(for payload: StatusPayload?) -> NSMenu {
        let menu = NSMenu()

        if let payload {
            detailLines(for: payload).forEach { line in
                menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
            }
        } else {
            menu.addItem(NSMenuItem(title: "无 Claude Code session", action: nil, keyEquivalent: ""))
        }

        let countItem = NSMenuItem(title: "Sessions：\(currentSessions.count)", action: nil, keyEquivalent: "")
        menu.addItem(countItem)

        menu.addItem(.separator())

        let resetItem = NSMenuItem(title: "重置此 session 为绿灯", action: #selector(resetSelectedToIdle(_:)), keyEquivalent: "r")
        resetItem.target = self
        resetItem.representedObject = payload?.sessionID
        resetItem.isEnabled = payload != nil
        menu.addItem(resetItem)

        let clearErrorsItem = NSMenuItem(title: "清除所有错误", action: #selector(clearAllErrors), keyEquivalent: "")
        clearErrorsItem.target = self
        clearErrorsItem.isEnabled = currentSessions.contains { $0.state == .error }
        menu.addItem(clearErrorsItem)

        let loginItem = NSMenuItem(title: "在登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let notificationsItem = NSMenuItem(title: "启用通知", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsItem.target = self
        notificationsItem.state = notificationController.isEnabled ? .on : .off
        menu.addItem(notificationsItem)

        menu.addItem(styleMenuItem())

        let configTitle = isHooksConfigured ? "✅ Claude Code 集成已配置..." : "⚠️ 未配置 Claude Code 集成..."
        let configItem = NSMenuItem(title: configTitle, action: #selector(checkClaudeConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        if !isHooksConfigured {
            let installItem = NSMenuItem(title: "为我自动配置 Hook", action: #selector(installClaudeHooks), keyEquivalent: "")
            installItem.target = self
            menu.addItem(installItem)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开 Claude Code 上下文", action: #selector(openClaudeCodeContext), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "退出 CC Light...", action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func tooltip(for payload: StatusPayload) -> String {
        detailLines(for: payload).joined(separator: "\n")
    }

    private func detailLines(for payload: StatusPayload) -> [String] {
        var lines = [
            payload.displayTitle,
            "状态：\(displayName(for: payload))",
            "更新：\(relativeTimeString(since: payload.updatedAt))"
        ]

        if let taskName = payload.taskName, !taskName.isEmpty {
            lines.append("任务：\(taskName)")
        }

        if let message = payload.message, !message.isEmpty {
            lines.append("消息：\(message)")
        }

        if let workingDirectory = payload.workingDirectory, !workingDirectory.isEmpty {
            lines.append("目录：\(workingDirectory)")
        }

        if let terminalTTY = payload.terminalTTY, !terminalTTY.isEmpty {
            lines.append("终端：\(terminalTTY)")
        }

        let cmuxIDs = [payload.cmuxWorkspaceID, payload.cmuxSurfaceID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cmuxIDs.isEmpty {
            lines.append("cmux：\(cmuxIDs.joined(separator: " / "))")
        }

        return lines
    }

    private func displayName(for payload: StatusPayload) -> String {
        if payload.state == .waiting,
           Date().timeIntervalSince(payload.updatedAt) >= waitingTimeoutDelay {
            return "等待决策超时"
        }

        return payload.state.displayName
    }

    private func styleMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "灯样式", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for style in StatusLightStyle.allCases {
            let styleItem = NSMenuItem(
                title: style.displayName,
                action: #selector(selectLightStyle(_:)),
                keyEquivalent: ""
            )
            styleItem.target = self
            styleItem.representedObject = style.rawValue
            styleItem.state = iconStyle == style ? .on : .off
            submenu.addItem(styleItem)
        }

        item.submenu = submenu
        return item
    }

    @objc private func resetSelectedToIdle(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String,
              let payload = currentSessions.first(where: { $0.sessionID == sessionID }) else {
            NSAlert.showError(title: "重置失败", message: "无法确定要重置的 session。")
            return
        }

        do {
            try resetToIdle(payload)
            apply(try StatusFileStore.readAllSessions())
        } catch {
            NSAlert.showError(title: "重置失败", message: error.localizedDescription)
        }
    }

    @objc private func clearAllErrors() {
        do {
            for payload in currentSessions where payload.state == .error {
                try resetToIdle(payload)
            }
            apply(try StatusFileStore.readAllSessions())
        } catch {
            NSAlert.showError(title: "清除错误失败", message: error.localizedDescription)
        }
    }

    private func resetToIdle(_ payload: StatusPayload) throws {
        try StatusFileStore.reset(
            sessionID: payload.sessionID,
            sessionTitle: payload.sessionTitle,
            workingDirectory: payload.workingDirectory,
            terminalBundleIdentifier: payload.terminalBundleIdentifier,
            terminalTTY: payload.terminalTTY,
            cmuxWorkspaceID: payload.cmuxWorkspaceID,
            cmuxSurfaceID: payload.cmuxSurfaceID,
            cmuxSocketPath: payload.cmuxSocketPath
        )
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.setEnabled(!LaunchAtLoginManager.isEnabled)
        } catch {
            NSAlert.showError(title: "无法更新登录启动设置", message: error.localizedDescription)
        }
    }

    @objc private func toggleNotifications() {
        notificationController.isEnabled.toggle()
        if notificationController.isEnabled {
            notificationController.requestAuthorizationIfNeeded()
        }
    }

    @objc private func selectLightStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedStyle = StatusLightStyle(rawValue: rawValue),
              selectedStyle != iconStyle else {
            return
        }

        iconStyle = selectedStyle
        StatusLightStyle.current = selectedStyle
        refreshStatusItemIcons()
    }

    @objc private func checkClaudeConfig() {
        ClaudeCodeConfigChecker.check()
    }

    @objc private func installClaudeHooks() {
        ClaudeCodeConfigChecker.installHooksWithUI()
    }

    func updateHooksConfigured(_ configured: Bool) {
        DispatchQueue.main.async {
            self.isHooksConfigured = configured
        }
    }

    @objc private func openClaudeCodeContext() {
        focusClaudeCodeContext(for: currentSessions.sorted(by: sessionSort).first)
    }

    @objc private func confirmQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出 CC Light？"
        alert.informativeText = "状态栏指示灯将停止显示 Claude Code 状态。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func focusClaudeCodeContext(for payload: StatusPayload? = nil) {
        if let payload {
            if focusTerminalSession(for: payload) {
                return
            }

            if let terminalBundleIdentifier = payload.terminalBundleIdentifier,
               activateRunningApplication(bundleIdentifier: terminalBundleIdentifier) {
                return
            }

            showMissingSessionContext(for: payload)
            return
        }

        showMissingSessionContext(for: nil)
    }

    private func activateRunningApplication(bundleIdentifier: String) -> Bool {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first else {
            return false
        }

        if application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
            return true
        }

        return runAppleScript("""
        tell application id "\(appleScriptEscaped(bundleIdentifier))"
            activate
        end tell
        return true
        """)
    }

    private func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private func focusTerminalSession(for payload: StatusPayload) -> Bool {
        if isCmuxSession(payload) {
            return focusCmuxSession(for: payload)
        }

        // Ghostty 没有暴露 tty，按 working directory 匹配并 focus。
        if payload.terminalBundleIdentifier == "com.mitchellh.ghostty" {
            return focusGhosttySession(for: payload)
        }

        guard let terminalTTY = payload.terminalTTY, !terminalTTY.isEmpty else {
            return false
        }

        switch payload.terminalBundleIdentifier {
        case "com.googlecode.iterm2":
            guard isApplicationRunning(bundleIdentifier: "com.googlecode.iterm2") else {
                return false
            }
            return runAppleScript(iTermFocusScript(tty: terminalTTY))
        case "com.apple.Terminal":
            guard isApplicationRunning(bundleIdentifier: "com.apple.Terminal") else {
                return false
            }
            return runAppleScript(terminalFocusScript(tty: terminalTTY))
        default:
            let didFocusITerm = isApplicationRunning(bundleIdentifier: "com.googlecode.iterm2")
                && runAppleScript(iTermFocusScript(tty: terminalTTY))
            let didFocusTerminal = isApplicationRunning(bundleIdentifier: "com.apple.Terminal")
                && runAppleScript(terminalFocusScript(tty: terminalTTY))
            return didFocusITerm || didFocusTerminal
        }
    }

    private func isCmuxSession(_ payload: StatusPayload) -> Bool {
        if hasText(payload.cmuxWorkspaceID) || hasText(payload.cmuxSurfaceID) {
            return true
        }

        return payload.terminalBundleIdentifier == cmuxDefaultBundleIdentifier
    }

    /// 用 cmux 深链接切到 session 所在 workspace/surface 并把 cmux 带到前台。
    /// `cmux://workspace/<ws>/surface/<sfc>` 由 LaunchServices 分发，无需 socket 鉴权或额外权限。
    private func focusCmuxSession(for payload: StatusPayload) -> Bool {
        guard let workspaceID = nonEmpty(payload.cmuxWorkspaceID) else {
            return false
        }

        var path = "workspace/\(workspaceID)"
        if let surfaceID = nonEmpty(payload.cmuxSurfaceID) {
            path += "/surface/\(surfaceID)"
        }

        guard let url = URL(string: "cmux://\(path)") else {
            return false
        }

        NSWorkspace.shared.open(url)
        return true
    }

    /// Ghostty 按 working directory 匹配终端 surface 并 focus；命中后再激活 App 确保置于最前。
    /// 局限：同一目录有多个 session 时只能命中第一个。
    private func focusGhosttySession(for payload: StatusPayload) -> Bool {
        guard isApplicationRunning(bundleIdentifier: "com.mitchellh.ghostty") else {
            return false
        }

        guard let workingDirectory = payload.workingDirectory, !workingDirectory.isEmpty else {
            return false
        }

        guard runAppleScript(ghosttyFocusScript(workingDirectory: workingDirectory)) else {
            return false
        }

        _ = activateRunningApplication(bundleIdentifier: "com.mitchellh.ghostty")
        return true
    }

    private func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        let result = script.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }

    private func iTermFocusScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if tty of aSession is "\(appleScriptEscaped(tty))" then
                            select aSession
                            set current tab of aWindow to aTab
                            set index of aWindow to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private func terminalFocusScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if tty of aTab is "\(appleScriptEscaped(tty))" then
                        set selected tab of aWindow to aTab
                        set index of aWindow to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private func ghosttyFocusScript(workingDirectory: String) -> String {
        """
        tell application "Ghostty"
            repeat with aTerminal in terminals
                if working directory of aTerminal is "\(appleScriptEscaped(workingDirectory))" then
                    focus aTerminal
                    return true
                end if
            end repeat
        end tell
        return false
        """
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func hasText(_ value: String?) -> Bool {
        nonEmpty(value) != nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func showMissingSessionContext(for payload: StatusPayload?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法打开 Claude Code session"
        if let payload {
            alert.informativeText = """
            状态里缺少可定位的终端信息，或对应终端 App 当前没有运行。

            请让 hook 或 CLI 写入当前 session 实际所在的终端信息，例如：
            cc-lights \(payload.state.rawValue) --session "\(payload.sessionID)" --tty "$(tty)" --terminal-bundle "com.googlecode.iterm2"

            如果 session 在 cmux 中，请写入 --cmux-workspace 和 --cmux-surface。
            """
        } else {
            alert.informativeText = "当前没有可打开的 Claude Code session。"
        }
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func sessionSort(_ lhs: StatusPayload, _ rhs: StatusPayload) -> Bool {
        if lhs.state.priority == rhs.state.priority {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.state.priority > rhs.state.priority
    }

    private func relativeTimeString(since date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 10 {
            return "刚刚"
        }
        if elapsed < 60 {
            return "\(elapsed) 秒前"
        }
        if elapsed < 3_600 {
            return "\(elapsed / 60) 分钟前"
        }
        if elapsed < 86_400 {
            return "\(elapsed / 3_600) 小时前"
        }
        return "\(elapsed / 86_400) 天前"
    }
}

enum StatusLightStyle: String, CaseIterable {
    case round
    case pixel

    private static let defaultsKey = "statusLightStyle"

    static var current: StatusLightStyle {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
                  let style = StatusLightStyle(rawValue: rawValue) else {
                return .round
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var displayName: String {
        switch self {
        case .round:
            return "圆形灯"
        case .pixel:
            return "像素风格"
        }
    }

    var statusItemLength: CGFloat {
        switch self {
        case .round:
            return NSStatusItem.squareLength
        case .pixel:
            return NSStatusItem.squareLength
        }
    }
}

enum StatusIcon {
    static func image(for state: StatusState, style: StatusLightStyle) -> NSImage {
        switch style {
        case .round:
            return roundImage(for: state)
        case .pixel:
            return pixelImage(for: state)
        }
    }

    private static func roundImage(for state: StatusState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
        let path = NSBezierPath(ovalIn: rect)
        color(for: state).setFill()
        path.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func pixelImage(for state: StatusState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let context = NSGraphicsContext.current
        context?.shouldAntialias = false
        context?.imageInterpolation = .none

        drawPixelLamp(origin: NSPoint(x: 2, y: 2), color: pixelColor(for: state))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private enum LampColor {
        case red
        case yellow
        case green
        case gray
    }

    private static func pixelColor(for state: StatusState) -> NSColor {
        switch state {
        case .offline:
            return lampColor(.gray)
        case .working, .idle:
            return lampColor(.green)
        case .waiting:
            return lampColor(.yellow)
        case .error:
            return lampColor(.red)
        }
    }

    private static func drawPixelLamp(origin: NSPoint, color: NSColor) {
        let scale: CGFloat = 2
        let mask: [[Bool]] = [
            [false, false, true, true, true, false, false],
            [false, true, true, true, true, true, false],
            [true, true, true, true, true, true, true],
            [true, true, true, true, true, true, true],
            [true, true, true, true, true, true, true],
            [false, true, true, true, true, true, false],
            [false, false, true, true, true, false, false]
        ]

        let borderColor = color.blended(withFraction: 0.25, of: .black) ?? color
        let shadowColor = color.blended(withFraction: 0.12, of: .black) ?? color
        let highlightColor = color.blended(withFraction: 0.7, of: .white) ?? color

        for row in 0..<mask.count {
            for column in 0..<mask[row].count where mask[row][column] {
                let isBorder = row == 0 || row == mask.count - 1
                    || column == 0 || column == mask[row].count - 1
                    || !mask[row - 1][column]
                    || !mask[row + 1][column]
                    || !mask[row][column - 1]
                    || !mask[row][column + 1]
                let isShadow = row >= 5 || column >= 5
                let isHighlight = row <= 2 && column >= 3
                let isSpecular = (row == 1 && column == 4) || (row == 2 && column == 3)
                let pixelColor = isBorder
                    ? borderColor
                    : (isSpecular ? .white : (isHighlight ? highlightColor : (isShadow ? shadowColor : color)))

                pixelColor.setFill()
                NSRect(
                    x: origin.x + CGFloat(column) * scale,
                    y: origin.y + CGFloat(mask.count - 1 - row) * scale,
                    width: scale,
                    height: scale
                ).fill()
            }
        }
    }

    private static func lampColor(_ color: LampColor) -> NSColor {
        switch color {
        case .red:
            return NSColor(calibratedRed: 1.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1.0)
        case .yellow:
            return NSColor(calibratedRed: 1.0, green: 204.0 / 255.0, blue: 0.0, alpha: 1.0)
        case .green:
            return NSColor(calibratedRed: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
        case .gray:
            return NSColor(calibratedWhite: 142.0 / 255.0, alpha: 1.0)
        }
    }

    private static func color(for state: StatusState) -> NSColor {
        switch state {
        case .offline:
            return NSColor(calibratedWhite: 142.0 / 255.0, alpha: 1.0)
        case .working:
            return NSColor(calibratedRed: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
        case .waiting:
            return NSColor(calibratedRed: 1.0, green: 204.0 / 255.0, blue: 0.0, alpha: 1.0)
        case .idle:
            return NSColor(calibratedRed: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
        case .error:
            return NSColor(calibratedRed: 1.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1.0)
        }
    }
}

final class StatusFileMonitor {
    private let queue = DispatchQueue(label: "ClaudeCodeStatusLight.StatusFileMonitor")
    private let onChange: ([StatusPayload]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var cmuxPoller: DispatchSourceTimer?
    private var lastDeliveredPayloads: [StatusPayload]?

    init(onChange: @escaping ([StatusPayload]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async {
            self.readLatestPayloads()
            self.startMonitoringDirectory()
            self.startPollingCmuxSessions()
        }
    }

    func stop() {
        queue.async {
            self.cancelCurrentSource()
            self.cancelCmuxPoller()
        }
    }

    private func startMonitoringDirectory() {
        cancelCurrentSource()

        let fileDescriptor = open(StatusFileStore.sessionsDirectoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            queue.asyncAfter(deadline: .now() + 1.0) {
                self.startMonitoringDirectory()
            }
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        newSource.setCancelHandler {
            close(fileDescriptor)
        }

        source = newSource
        newSource.resume()
    }

    private func handleFileEvent() {
        let events = source?.data ?? []
        let shouldRestart = events.contains(.delete) || events.contains(.rename) || events.contains(.revoke)

        if shouldRestart {
            cancelCurrentSource()
            queue.asyncAfter(deadline: .now() + 0.05) {
                self.readLatestPayloads()
                self.startMonitoringDirectory()
            }
        } else {
            readLatestPayloads()
        }
    }

    private func readLatestPayloads() {
        do {
            let statusPayloads = try StatusFileStore.readAllSessions()
            let payloads = self.mergedWithCmuxClaudeSessions(statusPayloads)
            guard payloads != lastDeliveredPayloads else {
                return
            }
            lastDeliveredPayloads = payloads
            DispatchQueue.main.async {
                self.onChange(payloads)
            }
        } catch {
            DispatchQueue.main.async {
                NSAlert.showError(title: "无法读取 session 状态", message: error.localizedDescription)
            }
        }
    }

    private func mergedWithCmuxClaudeSessions(_ statusPayloads: [StatusPayload]) -> [StatusPayload] {
        let cmuxPayloads: [StatusPayload]
        do {
            cmuxPayloads = try CmuxClaudeSessionStore.readPayloads()
        } catch {
            fputs("无法读取 cmux Claude session：\(error.localizedDescription)\n", stderr)
            cmuxPayloads = []
        }

        guard !cmuxPayloads.isEmpty else {
            return statusPayloads
        }

        var mergedBySessionID = Dictionary(uniqueKeysWithValues: cmuxPayloads.map { ($0.sessionID, $0) })
        for payload in statusPayloads {
            if var cmuxPayload = mergedBySessionID[payload.sessionID] {
                cmuxPayload.state = payload.state
                cmuxPayload.message = payload.message
                cmuxPayload.taskName = payload.taskName
                cmuxPayload.sessionTitle = payload.sessionTitle ?? cmuxPayload.sessionTitle
                cmuxPayload.workingDirectory = payload.workingDirectory ?? cmuxPayload.workingDirectory
                cmuxPayload.terminalBundleIdentifier = payload.terminalBundleIdentifier ?? cmuxPayload.terminalBundleIdentifier
                cmuxPayload.terminalTTY = payload.terminalTTY ?? cmuxPayload.terminalTTY
                cmuxPayload.cmuxWorkspaceID = payload.cmuxWorkspaceID ?? cmuxPayload.cmuxWorkspaceID
                cmuxPayload.cmuxSurfaceID = payload.cmuxSurfaceID ?? cmuxPayload.cmuxSurfaceID
                cmuxPayload.cmuxSocketPath = payload.cmuxSocketPath ?? cmuxPayload.cmuxSocketPath
                cmuxPayload.updatedAt = max(payload.updatedAt, cmuxPayload.updatedAt)
                mergedBySessionID[payload.sessionID] = cmuxPayload
            } else {
                mergedBySessionID[payload.sessionID] = payload
            }
        }

        return mergedBySessionID.values.sorted { lhs, rhs in
            if lhs.state.priority == rhs.state.priority {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.state.priority > rhs.state.priority
        }
    }

    private func startPollingCmuxSessions() {
        cancelCmuxPoller()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.readLatestPayloads()
        }
        cmuxPoller = timer
        timer.resume()
    }

    private func cancelCurrentSource() {
        source?.cancel()
        source = nil
    }

    private func cancelCmuxPoller() {
        cmuxPoller?.cancel()
        cmuxPoller = nil
    }
}

enum CmuxClaudeSessionStore {
    private static let cmuxBundleIdentifier = "com.cmuxterm.app"

    private struct Root: Decodable {
        var sessions: [String: Session]
    }

    private struct Session: Decodable {
        var agentLifecycle: String?
        var cwd: String?
        var pid: Int32?
        var sessionId: String?
        var startedAt: Double?
        var surfaceId: String?
        var updatedAt: Double?
        var workspaceId: String?
    }

    static var sessionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cmuxterm", isDirectory: true)
            .appendingPathComponent("claude-hook-sessions.json", isDirectory: false)
    }

    static func readPayloads() throws -> [StatusPayload] {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: sessionsURL)
        let root = try JSONDecoder().decode(Root.self, from: data)

        return root.sessions.values.compactMap(payload(for:))
    }

    private static func payload(for session: Session) -> StatusPayload? {
        guard let sessionID = nonEmpty(session.sessionId),
              let workspaceID = nonEmpty(session.workspaceId),
              let surfaceID = nonEmpty(session.surfaceId) else {
            return nil
        }

        if let pid = session.pid, !processIsRunning(pid: pid) {
            return nil
        }

        let workingDirectory = nonEmpty(session.cwd)
        return StatusPayload(
            state: state(for: session.agentLifecycle),
            sessionID: sessionID,
            sessionTitle: workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
            workingDirectory: workingDirectory,
            terminalBundleIdentifier: cmuxBundleIdentifier,
            cmuxWorkspaceID: workspaceID,
            cmuxSurfaceID: surfaceID,
            cmuxSocketPath: cmuxSocketPath(),
            updatedAt: date(from: session.updatedAt ?? session.startedAt)
        )
    }

    private static func cmuxSocketPath() -> String? {
        if let socketPath = nonEmpty(ProcessInfo.processInfo.environment["CMUX_SOCKET_PATH"]) {
            return socketPath
        }

        let candidateURLs = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("state", isDirectory: true)
                .appendingPathComponent("cmux", isDirectory: true)
                .appendingPathComponent("cmux.sock", isDirectory: false),
            URL(fileURLWithPath: "/tmp/cmux.sock")
        ]

        return candidateURLs.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    private static func state(for lifecycle: String?) -> StatusState {
        switch lifecycle?.lowercased() {
        case "working", "running", "busy":
            return .working
        case "waiting", "blocked", "permission":
            return .waiting
        case "error", "failed", "failure":
            return .error
        default:
            return .idle
        }
    }

    private static func processIsRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func date(from timestamp: Double?) -> Date {
        guard let timestamp else {
            return Date()
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// 监听 ~/.claude 目录变化，实时反馈 hook 是否已配置（盯目录而非文件，兼容编辑器的原子替换）。
final class ClaudeCodeConfigMonitor {
    private let queue = DispatchQueue(label: "ClaudeCodeStatusLight.ConfigMonitor")
    private let onChange: (Bool) -> Void
    private var source: DispatchSourceFileSystemObject?
    private let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async {
            self.notifyState()
            self.startMonitoring()
        }
    }

    func stop() {
        queue.async {
            self.cancelCurrentSource()
        }
    }

    private func startMonitoring() {
        cancelCurrentSource()

        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            queue.asyncAfter(deadline: .now() + 2.0) {
                self.startMonitoring()
            }
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        newSource.setCancelHandler {
            close(fileDescriptor)
        }

        source = newSource
        newSource.resume()
    }

    private func handleEvent() {
        let events = source?.data ?? []
        let shouldRestart = events.contains(.delete) || events.contains(.rename) || events.contains(.revoke)

        if shouldRestart {
            cancelCurrentSource()
            queue.asyncAfter(deadline: .now() + 0.1) {
                self.notifyState()
                self.startMonitoring()
            }
        } else {
            notifyState()
        }
    }

    private func notifyState() {
        let configured = ClaudeCodeConfigChecker.isHooksConfigured()
        DispatchQueue.main.async {
            self.onChange(configured)
        }
    }

    private func cancelCurrentSource() {
        source?.cancel()
        source = nil
    }
}

final class NotificationController {
    private let enabledKey = "notificationsEnabled"

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    func requestAuthorizationIfNeeded() {
        guard isEnabled, isRunningFromAppBundle else {
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(from previousState: StatusState, to payload: StatusPayload) {
        guard isEnabled, isRunningFromAppBundle else {
            return
        }

        switch (previousState, payload.state) {
        case (_, .waiting) where previousState != .waiting:
            send(title: "Claude Code 需要你的决定", body: payload.message ?? "请回到 Claude Code 上下文完成选择。")
        case (_, .error) where previousState != .error:
            send(title: "Claude Code 执行出错", body: payload.message ?? "请查看 Claude Code 日志。")
        default:
            break
        }
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ClaudeCodeStatusLight.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

enum LaunchAtLoginManager {
    private static let label = "com.github.copilot.ClaudeCodeStatusLight"

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private static var launchAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist", isDirectory: false)
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private static func installLaunchAgent() throws {
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let arguments = programArguments().map { "<string>\($0.xmlEscaped)</string>" }.joined(separator: "\n        ")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                \(arguments)
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """

        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
    }

    private static func programArguments() -> [String] {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return ["/usr/bin/open", "-a", bundlePath]
        }

        return [Bundle.main.executablePath ?? CommandLine.arguments[0]]
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension NSAlert {
    static func showError(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }
    }
}

// MARK: - Claude Code 集成检查

enum ClaudeCodeConfigChecker {
    private static let claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    private static let hasAutoConfiguredKey = "hasAutoConfiguredClaudeHooks"

    /// 启动时自动落地内置 CLI 到稳定路径，并配置/修复 Claude Code hook：
    /// - 已配置：把命令刷新为稳定路径（修复旧裸命令 / 改名后失效的旧路径），幂等无打扰。
    /// - 未配置且首次运行：自动写入 hook（无需用户手动），成功后一次性告知需重启 Claude Code。
    static func setUpHooksOnLaunch() {
        installManagedCLI()
        ensureLegacyManagedAlias()
        exposeCLIOnPath()

        let firstRun = !UserDefaults.standard.bool(forKey: hasAutoConfiguredKey)
        UserDefaults.standard.set(true, forKey: hasAutoConfiguredKey)

        if isHooksConfigured() {
            _ = try? installHooks()
            return
        }

        guard firstRun else { return }

        if (try? installHooks()) == true {
            notifyAutoConfigured()
        }
    }

    private static func notifyAutoConfigured() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "已自动配置 Claude Code 集成"
            alert.informativeText = """
            已把状态灯 hook 写入 ~/.claude/settings.json（原文件已备份）。

            请重启 Claude Code 使配置生效。
            """
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }

    /// 用户从菜单手动检查（每次都弹结果）
    static func check() {
        let configured = isHooksConfigured()
        let alert = NSAlert()
        alert.alertStyle = configured ? .informational : .warning
        alert.messageText = configured ? "✅ Claude Code Hook 已配置" : "⚠️ 未检测到 Claude Code Hook 配置"
        alert.informativeText = configured
            ? "状态灯将自动跟随 Claude Code 的状态变化。\n\n如需调整，请编辑 ~/.claude/settings.json 中的 hooks 配置。"
            : """
            状态灯需要 Claude Code 的 Hook 配置才能自动变化颜色。

            请在 ~/.claude/settings.json 中添加以下配置：

            "hooks": {
              "UserPromptSubmit": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-lights working --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\""}]
              }],
              "PreToolUse": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-lights working --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\""}]
              }],
              "PostToolUse": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-lights working --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\""}]
              }],
              "Stop": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-lights idle --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\""}]
              }],
              "StopFailure": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-lights error --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\" --message \\"执行出错\\""}]
              }],
              "Notification": [
                {
                  "matcher": "permission_prompt",
                  "hooks": [{"type": "command", "command": "cc-lights waiting --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\" --message \\"等待你的操作\\""}]
                },
                {
                  "matcher": "elicitation_dialog",
                  "hooks": [{"type": "command", "command": "cc-lights waiting --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\" --message \\"等待你的操作\\""}]
                }
              ],
              "SessionEnd": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-lights remove --session \\"$CLAUDE_SESSION_ID\\""}]
              }]
            }

            或在右键菜单中点击「为我自动配置 Hook」，App 会自动合并（并备份原文件）。
            """
        if !configured {
            alert.addButton(withTitle: "为我自动配置")
        }
        alert.addButton(withTitle: "知道了")
        if !configured, alert.runModal() == .alertFirstButtonReturn {
            installHooksWithUI()
        }
    }

    static func isHooksConfigured() -> Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        let requiredHooks: Set<String> = ["Stop", "UserPromptSubmit"]
        let configuredHooks = Set(hooks.keys)
        return requiredHooks.isSubset(of: configuredHooks)
    }

    enum ConfigError: LocalizedError {
        case invalidSettings

        var errorDescription: String? {
            switch self {
            case .invalidSettings:
                return "~/.claude/settings.json 不是合法的 JSON，请先手动修复后再试。"
            }
        }
    }

    /// 把状态灯 hook 安全合并进 settings.json：只追加自己的分组、不动用户已有配置、写前备份。
    /// 返回是否真的写入了改动。
    @discardableResult
    static func installHooks() throws -> Bool {
        let url = claudeSettingsURL
        let fileManager = FileManager.default
        let fileExists = fileManager.fileExists(atPath: url.path)

        var root: [String: Any] = [:]
        if fileExists {
            let data = try Data(contentsOf: url)
            if !data.isEmpty {
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ConfigError.invalidSettings
                }
                root = parsed
            }
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        // 写入内置 CLI 的绝对路径，避免 DMG 安装后 hook 在非交互 shell 里找不到 cc-lights。
        let cli = statusctlCommand()

        // Notification 只匹配 permission_prompt / elicitation_dialog（需要你操作时），
        // 避免 idle_prompt 等把空闲会话误点亮。PreToolUse 在工具执行前刷回 working，
        // 让批准授权后黄灯回到绿色呼吸。
        let waitingCommand = "\(cli) waiting --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\" --message \"等待你的操作\""
        let entries: [(event: String, matcher: String, command: String)] = [
            ("UserPromptSubmit", "*", "\(cli) working --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\""),
            ("PreToolUse", "*", "\(cli) working --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\""),
            ("PostToolUse", "*", "\(cli) working --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\""),
            ("Stop", "*", "\(cli) idle --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\""),
            ("StopFailure", "*", "\(cli) error --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\" --message \"执行出错\""),
            ("Notification", "permission_prompt", waitingCommand),
            ("Notification", "elicitation_dialog", waitingCommand),
            ("SessionEnd", "*", "\(cli) remove --session \"$CLAUDE_SESSION_ID\"")
        ]

        var changed = false
        for entry in entries {
            var groups = hooks[entry.event] as? [[String: Any]] ?? []
            let newGroup: [String: Any] = [
                "matcher": entry.matcher,
                "hooks": [["type": "command", "command": entry.command]]
            ]

            // 替换本 App 之前写入的同 matcher cc-statusctl 分组（可能是旧的裸命令），保留用户其它 hook。
            if let index = groups.firstIndex(where: { group in
                (group["matcher"] as? String) == entry.matcher
                    && ((group["hooks"] as? [[String: Any]])?
                        .contains { (($0["command"] as? String) ?? "").contains("cc-statusctl")
                            || (($0["command"] as? String) ?? "").contains("cc-lights") } ?? false)
            }) {
                let existingCommand = (groups[index]["hooks"] as? [[String: Any]])?
                    .first?["command"] as? String
                if existingCommand == entry.command {
                    continue
                }
                groups[index] = newGroup
            } else {
                groups.append(newGroup)
            }

            hooks[entry.event] = groups
            changed = true
        }

        guard changed else {
            return false
        }

        root["hooks"] = hooks

        if fileExists {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("settings.json.bak-\(formatter.string(from: Date()))")
            try fileManager.copyItem(at: url, to: backupURL)
        } else {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let outData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outData.write(to: url, options: .atomic)
        return true
    }

    static func installHooksWithUI() {
        do {
            let didChange = try installHooks()
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = didChange ? "✅ 已写入 Claude Code Hook 配置" : "✅ Claude Code Hook 已配置"
            alert.informativeText = didChange
                ? "已把状态灯 hook 合并进 ~/.claude/settings.json（原文件已备份为 settings.json.bak-*）。\n\n请重启 Claude Code 使配置生效。"
                : "无需改动，hook 已存在。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        } catch {
            NSAlert.showError(title: "写入配置失败", message: error.localizedDescription)
        }
    }

    /// hook 里写入的 cc-lights 命令：优先用稳定托管路径（与 App 名/位置无关），
    /// 其次用 App 内置副本，最后退回裸命令（开发环境）。带引号兼容路径含空格。
    private static func statusctlCommand() -> String {
        if let url = installManagedCLI() ?? existingManagedCLIURL() {
            return "\"\(url.path)\""
        }
        if let url = bundledStatusctlURL() {
            return "\"\(url.path)\""
        }
        return "cc-lights"
    }

    /// 稳定托管路径：放在 Application Support 下，与 App 显示名/安装位置无关，
    /// 因此 App 改名或移动都不会让已写入的 hook 失效。
    static var managedCLIURL: URL {
        StatusFileStore.applicationSupportDirectory
            .appendingPathComponent("cc-lights", isDirectory: false)
    }

    static func existingManagedCLIURL() -> URL? {
        FileManager.default.isExecutableFile(atPath: managedCLIURL.path) ? managedCLIURL : nil
    }

    /// 把 App 内置的 cc-lights 复制到稳定托管路径（内容不同才原子替换）。返回可用路径。
    @discardableResult
    static func installManagedCLI() -> URL? {
        guard let bundled = bundledStatusctlURL() else {
            return existingManagedCLIURL()
        }

        let fileManager = FileManager.default
        let dest = managedCLIURL
        do {
            try fileManager.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let source = try? Data(contentsOf: bundled),
               let current = try? Data(contentsOf: dest),
               source == current {
                return dest
            }

            let tempURL = dest.deletingLastPathComponent()
                .appendingPathComponent("cc-lights.\(UUID().uuidString).tmp", isDirectory: false)
            try fileManager.copyItem(at: bundled, to: tempURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

            if fileManager.fileExists(atPath: dest.path) {
                _ = try fileManager.replaceItemAt(dest, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: dest)
            }
            return dest
        } catch {
            return existingManagedCLIURL()
        }
    }

    /// 在托管目录里维护旧名兼容软链 cc-statusctl -> cc-lights，
    /// 让仍引用旧绝对路径（.../ClaudeCodeStatusLight/cc-statusctl）的 hook 继续可用。
    static func ensureLegacyManagedAlias() {
        let fileManager = FileManager.default
        let alias = StatusFileStore.applicationSupportDirectory
            .appendingPathComponent("cc-statusctl", isDirectory: false)

        guard fileManager.isExecutableFile(atPath: managedCLIURL.path) else {
            return
        }

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: alias.path) {
            if destination == managedCLIURL.path {
                return
            }
            try? fileManager.removeItem(at: alias)
        } else if fileManager.fileExists(atPath: alias.path) {
            // 真实文件（旧版可能直接复制过 cc-statusctl）：替换为指向 cc-lights 的软链。
            try? fileManager.removeItem(at: alias)
        }

        try? fileManager.createSymbolicLink(atPath: alias.path, withDestinationPath: managedCLIURL.path)
    }

    /// 尽力把 cc-lights 暴露到 hook 运行时 PATH 中的标准位置，让即便写成裸命令
    /// `cc-statusctl`（可能来自项目级 .claude/settings.json 或旧配置）的 hook 也能找到它。
    /// 仅在目录已存在且可写时创建/更新指向托管副本的软链，不请求提权，也不覆盖用户已有的真实文件。
    @discardableResult
    static func exposeCLIOnPath() -> Bool {
        guard let cli = existingManagedCLIURL() ?? bundledStatusctlURL() else {
            return false
        }

        let fileManager = FileManager.default
        var linkedAny = false

        for directory in ["/opt/homebrew/bin", "/usr/local/bin"] {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  access(directory, W_OK) == 0 else {
                continue
            }

            for name in ["cc-lights", "cc-statusctl"] {
                let namedLink = (directory as NSString).appendingPathComponent(name)

                if let destination = try? fileManager.destinationOfSymbolicLink(atPath: namedLink) {
                    // 已是软链：指向当前托管路径就跳过，否则更新。
                    if destination == cli.path {
                        linkedAny = true
                        continue
                    }
                    try? fileManager.removeItem(atPath: namedLink)
                } else if fileManager.fileExists(atPath: namedLink) {
                    // 真实文件（用户自己安装的同名命令）：尊重，不覆盖。
                    continue
                }

                if (try? fileManager.createSymbolicLink(atPath: namedLink, withDestinationPath: cli.path)) != nil {
                    linkedAny = true
                }
            }
        }

        return linkedAny
    }

    private static func bundledStatusctlURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("cc-lights", isDirectory: false))
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDirectory.appendingPathComponent("cc-lights", isDirectory: false))
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
