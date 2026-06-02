import AppKit
import Darwin
import Foundation
import StatusLightCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var statusFileMonitor: StatusFileMonitor?
    private let notificationController = NotificationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try StatusFileStore.ensureDirectoryExists()
            if try StatusFileStore.read() == nil {
                try StatusFileStore.write(StatusPayload(state: .idle))
            }
        } catch {
            NSAlert.showError(title: "无法初始化状态文件", message: error.localizedDescription)
        }

        notificationController.requestAuthorizationIfNeeded()

        let controller = StatusBarController(notificationController: notificationController)
        statusBarController = controller

        ClaudeCodeConfigChecker.checkAndWarnIfNeeded()

        let monitor = StatusFileMonitor { [weak controller] payload in
            controller?.apply(payload)
        }
        statusFileMonitor = monitor
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusFileMonitor?.stop()
    }
}

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let notificationController: NotificationController
    private var currentPayload = StatusPayload(state: .idle)
    private var workingAnimator: Timer?

    init(notificationController: NotificationController) {
        self.notificationController = notificationController
        super.init()
        configureStatusItem()
        apply(currentPayload)
    }

    func apply(_ payload: StatusPayload) {
        DispatchQueue.main.async {
            let previousState = self.currentPayload.state
            self.currentPayload = payload

            if let button = self.statusItem.button {
                button.image = StatusIcon.image(for: payload.state)
                button.toolTip = self.tooltip(for: payload)
            }

            if payload.state == .working {
                self.startWorkingAnimation()
            } else {
                self.stopWorkingAnimation()
            }

            if previousState != payload.state {
                self.notificationController.notifyIfNeeded(from: previousState, to: payload)
            }
        }
    }

    // MARK: - Working 脉冲动画

    private var animationStartTime: Date?

    private func startWorkingAnimation() {
        guard workingAnimator == nil else { return }

        animationStartTime = Date()
        let minAlpha: CGFloat = 0.3
        let period: TimeInterval = 1.0

        workingAnimator = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.animationStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let phase = (elapsed / period).truncatingRemainder(dividingBy: 1.0)
            let alpha = minAlpha + (1 - minAlpha) * CGFloat(0.5 + 0.5 * sin(phase * 2 * .pi))
            DispatchQueue.main.async {
                self.statusItem.button?.alphaValue = alpha
            }
        }
    }

    private func stopWorkingAnimation() {
        workingAnimator?.invalidate()
        workingAnimator = nil
        animationStartTime = nil
        statusItem.button?.alphaValue = 1.0
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = StatusIcon.image(for: .idle)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let shouldShowMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true

        if shouldShowMenu {
            showMenu()
        } else {
            handlePrimaryClick()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else {
            return
        }

        statusItem.menu = buildMenu()
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let stateItem = NSMenuItem(title: "当前状态：\(currentPayload.state.displayName)", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)

        if let taskName = currentPayload.taskName, !taskName.isEmpty {
            let taskItem = NSMenuItem(title: "任务：\(taskName)", action: nil, keyEquivalent: "")
            menu.addItem(taskItem)
        }

        if let message = currentPayload.message, !message.isEmpty {
            let messageItem = NSMenuItem(title: "消息：\(message)", action: nil, keyEquivalent: "")
            menu.addItem(messageItem)
        }

        menu.addItem(.separator())

        let resetItem = NSMenuItem(title: "重置为绿灯", action: #selector(resetToIdle), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        let loginItem = NSMenuItem(title: "在登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let notificationsItem = NSMenuItem(title: "启用通知", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsItem.target = self
        notificationsItem.state = notificationController.isEnabled ? .on : .off
        menu.addItem(notificationsItem)

        let configItem = NSMenuItem(title: "检查 Claude Code 集成...", action: #selector(checkClaudeConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开 Claude Code 上下文", action: #selector(openClaudeCodeContext), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "退出 Claude Code Status Light...", action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func handlePrimaryClick() {
        switch currentPayload.state {
        case .waiting:
            showWaitingDecision()
        case .error:
            showErrorDetail()
        case .working, .idle:
            focusClaudeCodeContext()
        }
    }

    private func tooltip(for payload: StatusPayload) -> String {
        if let taskName = payload.taskName, !taskName.isEmpty {
            return "\(payload.state.tooltip)\n\(taskName)"
        }
        return payload.state.tooltip
    }

    @objc private func resetToIdle() {
        do {
            try StatusFileStore.reset()
            apply(StatusPayload(state: .idle))
        } catch {
            NSAlert.showError(title: "重置失败", message: error.localizedDescription)
        }
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

    @objc private func checkClaudeConfig() {
        ClaudeCodeConfigChecker.check()
    }

    @objc private func openClaudeCodeContext() {
        focusClaudeCodeContext()
    }

    @objc private func confirmQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出 Claude Code Status Light？"
        alert.informativeText = "状态栏指示灯将停止显示 Claude Code 状态。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func showWaitingDecision() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Claude Code 等待你的决策"
        alert.informativeText = currentPayload.message ?? "请回到 Claude Code 终端或 IDE 完成当前选择。"
        alert.addButton(withTitle: "打开上下文")
        alert.addButton(withTitle: "重置为绿灯")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            focusClaudeCodeContext()
        } else if response == .alertSecondButtonReturn {
            resetToIdle()
        }
    }

    private func showErrorDetail() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Claude Code 执行出错"
        alert.informativeText = currentPayload.message ?? "未提供错误详情。请回到 Claude Code 上下文查看日志。"
        alert.addButton(withTitle: "重置为绿灯")
        alert.addButton(withTitle: "打开上下文")
        alert.addButton(withTitle: "保留红灯")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            resetToIdle()
        } else if response == .alertSecondButtonReturn {
            focusClaudeCodeContext()
        }
    }

    private func focusClaudeCodeContext() {
        let candidateBundleIdentifiers = [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.microsoft.VSCode"
        ]

        for bundleIdentifier in candidateBundleIdentifiers {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                continue
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
    }
}

enum StatusIcon {
    static func image(for state: StatusState) -> NSImage {
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

    private static func color(for state: StatusState) -> NSColor {
        switch state {
        case .working:
            return NSColor(calibratedRed: 0.0, green: 122.0 / 255.0, blue: 1.0, alpha: 1.0)
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
    private let onChange: (StatusPayload) -> Void
    private var source: DispatchSourceFileSystemObject?

    init(onChange: @escaping (StatusPayload) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async {
            self.readLatestPayload()
            self.startMonitoringFile()
        }
    }

    func stop() {
        queue.async {
            self.cancelCurrentSource()
        }
    }

    private func startMonitoringFile() {
        cancelCurrentSource()

        let fileDescriptor = open(StatusFileStore.statusFileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            queue.asyncAfter(deadline: .now() + 1.0) {
                self.startMonitoringFile()
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
                self.readLatestPayload()
                self.startMonitoringFile()
            }
        } else {
            readLatestPayload()
        }
    }

    private func readLatestPayload() {
        do {
            guard let payload = try StatusFileStore.read() else {
                return
            }
            DispatchQueue.main.async {
                self.onChange(payload)
            }
        } catch {
            DispatchQueue.main.async {
                NSAlert.showError(title: "无法读取状态文件", message: error.localizedDescription)
            }
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
        guard isEnabled else {
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(from previousState: StatusState, to payload: StatusPayload) {
        guard isEnabled else {
            return
        }

        switch (previousState, payload.state) {
        case (.working, .waiting):
            send(title: "Claude Code 需要你的决定", body: payload.message ?? "请回到 Claude Code 上下文完成选择。")
        case (_, .error):
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

    private static let hasCheckedKey = "hasCheckedClaudeHookConfig"

    /// 首次启动时自动检查（只弹一次），没配好就提醒
    static func checkAndWarnIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasCheckedKey) else { return }
        UserDefaults.standard.set(true, forKey: hasCheckedKey)
        performCheck()
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
                "hooks": [{"type": "command", "command": "cc-statusctl working"}]
              }],
              "Stop": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-statusctl idle"}]
              }],
              "StopFailure": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-statusctl error --message \\"执行出错\\""}]
              }]
            }

            添加后保存并重启 Claude Code。
            """
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private static func performCheck() {
        guard !isHooksConfigured() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "检查 Claude Code 集成"
            alert.informativeText = """
            未检测到 Claude Code 的 Hook 配置。

            状态灯已开始运行，但需要配置 Hook 才能自动跟随 Claude Code 的状态变化。
            你可随时在右键菜单中点击「检查 Claude Code 集成」查看配置说明。
            """
            alert.addButton(withTitle: "知道了")
            alert.runModal()
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
