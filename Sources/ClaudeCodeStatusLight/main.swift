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
        } catch {
            NSAlert.showError(title: "无法初始化状态文件", message: error.localizedDescription)
        }

        notificationController.requestAuthorizationIfNeeded()

        let controller = StatusBarController(notificationController: notificationController)
        statusBarController = controller

        ClaudeCodeConfigChecker.checkAndWarnIfNeeded()

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
    private var workingAnimator: Timer?
    private let placeholderTag = -1
    private var isHooksConfigured = false

    init(notificationController: NotificationController) {
        self.notificationController = notificationController
        super.init()
        apply([])
    }

    func apply(_ payloads: [StatusPayload]) {
        DispatchQueue.main.async {
            let previousState = self.currentPayload.state
            let payload = StatusFileStore.aggregate(payloads)
            self.currentSessions = payloads
            self.currentPayload = payload

            self.rebuildStatusItems()

            if payloads.contains(where: { $0.state == .working }) {
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
                for statusItem in self.statusItems {
                    guard let button = statusItem.button else {
                        continue
                    }

                    if self.visiblePayloadsByTag[button.tag]?.state == .working {
                        button.alphaValue = alpha
                    } else {
                        button.alphaValue = 1.0
                    }
                }
            }
        }
    }

    private func stopWorkingAnimation() {
        workingAnimator?.invalidate()
        workingAnimator = nil
        animationStartTime = nil
        statusItems.forEach { $0.button?.alphaValue = 1.0 }
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

    private func makeStatusItem(tag: Int) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        button.image = StatusIcon.image(for: state)
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

        statusItem.menu = buildMenu()
        sender.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let stateItem = NSMenuItem(title: "当前状态：\(currentPayload.state.displayName)", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)

        let countItem = NSMenuItem(title: "Sessions：\(currentSessions.count)", action: nil, keyEquivalent: "")
        menu.addItem(countItem)

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
        resetItem.isEnabled = !currentSessions.isEmpty
        menu.addItem(resetItem)

        let loginItem = NSMenuItem(title: "在登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let notificationsItem = NSMenuItem(title: "启用通知", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsItem.target = self
        notificationsItem.state = notificationController.isEnabled ? .on : .off
        menu.addItem(notificationsItem)

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

        let quitItem = NSMenuItem(title: "退出 Claude Code Status Light...", action: #selector(confirmQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func tooltip(for payload: StatusPayload) -> String {
        var lines = [
            payload.displayTitle,
            "状态：\(payload.state.displayName)",
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

        return lines.joined(separator: "\n")
    }

    @objc private func resetToIdle() {
        do {
            try StatusFileStore.reset(
                sessionID: currentPayload.sessionID,
                sessionTitle: currentPayload.sessionTitle,
                workingDirectory: currentPayload.workingDirectory,
                terminalBundleIdentifier: currentPayload.terminalBundleIdentifier,
                terminalTTY: currentPayload.terminalTTY
            )
            apply(try StatusFileStore.readAllSessions())
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
        alert.messageText = "退出 Claude Code Status Light？"
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
               activateApplication(bundleIdentifier: terminalBundleIdentifier) {
                return
            }

            if activateDefaultTerminal() {
                return
            }

            showMissingSessionContext(for: payload)
            return
        }

        _ = activateDefaultTerminal()
    }

    private func activateDefaultTerminal() -> Bool {
        let candidateBundleIdentifiers = [
            "com.googlecode.iterm2",
            "com.apple.Terminal"
        ]

        for bundleIdentifier in candidateBundleIdentifiers {
            if activateApplication(bundleIdentifier: bundleIdentifier) {
                return true
            }
        }

        return false
    }

    private func activateApplication(bundleIdentifier: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }

    private func focusTerminalSession(for payload: StatusPayload) -> Bool {
        guard let terminalTTY = payload.terminalTTY, !terminalTTY.isEmpty else {
            return false
        }

        switch payload.terminalBundleIdentifier {
        case "com.googlecode.iterm2":
            return runAppleScript(iTermFocusScript(tty: terminalTTY))
        case "com.apple.Terminal":
            return runAppleScript(terminalFocusScript(tty: terminalTTY))
        default:
            return runAppleScript(iTermFocusScript(tty: terminalTTY))
                || runAppleScript(terminalFocusScript(tty: terminalTTY))
        }
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

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func showMissingSessionContext(for payload: StatusPayload) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法打开 Claude Code session"
        alert.informativeText = """
        状态里缺少可定位的终端信息。

        请让 hook 或 CLI 写入 --tty 和 --terminal-bundle，例如：
        cc-statusctl \(payload.state.rawValue) --session "\(payload.sessionID)" --tty "$(tty)" --terminal-bundle "com.googlecode.iterm2"
        """
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
        case .offline:
            return NSColor(calibratedWhite: 142.0 / 255.0, alpha: 1.0)
        case .working:
            return NSColor(calibratedRed: 0.0, green: 122.0 / 255.0, blue: 1.0, alpha: 1.0)
        case .waiting:
            return NSColor(calibratedRed: 1.0, green: 149.0 / 255.0, blue: 0.0, alpha: 1.0)
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

    init(onChange: @escaping ([StatusPayload]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async {
            self.readLatestPayloads()
            self.startMonitoringDirectory()
        }
    }

    func stop() {
        queue.async {
            self.cancelCurrentSource()
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
            let payloads = try StatusFileStore.readAllSessions()
            DispatchQueue.main.async {
                self.onChange(payloads)
            }
        } catch {
            DispatchQueue.main.async {
                NSAlert.showError(title: "无法读取 session 状态", message: error.localizedDescription)
            }
        }
    }

    private func cancelCurrentSource() {
        source?.cancel()
        source = nil
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
                "hooks": [{"type": "command", "command": "cc-statusctl working --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\""}]
              }],
              "Stop": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-statusctl idle --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\""}]
              }],
              "StopFailure": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-statusctl error --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\" --message \\"执行出错\\""}]
              }],
              "Notification": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-statusctl waiting --session \\"$CLAUDE_SESSION_ID\\" --cwd \\"$PWD\\" --message \\"等待你的操作\\""}]
              }],
              "SessionEnd": [{
                "matcher": "*",
                "hooks": [{"type": "command", "command": "cc-statusctl remove --session \\"$CLAUDE_SESSION_ID\\""}]
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

    private static func performCheck() {
        guard !isHooksConfigured() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "检查 Claude Code 集成"
            alert.informativeText = """
            未检测到 Claude Code 的 Hook 配置。

            状态灯已开始运行，但需要配置 Hook 才能自动跟随 Claude Code 的状态变化。
            点击「为我自动配置」可把 hook 合并进 ~/.claude/settings.json（会先备份原文件），也可稍后在右键菜单中操作。
            """
            alert.addButton(withTitle: "为我自动配置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                installHooksWithUI()
            }
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

        let entries: [(event: String, command: String)] = [
            ("UserPromptSubmit", "cc-statusctl working --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\""),
            ("Stop", "cc-statusctl idle --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\""),
            ("StopFailure", "cc-statusctl error --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\" --message \"执行出错\""),
            ("Notification", "cc-statusctl waiting --session \"$CLAUDE_SESSION_ID\" --cwd \"$PWD\" --message \"等待你的操作\""),
            ("SessionEnd", "cc-statusctl remove --session \"$CLAUDE_SESSION_ID\"")
        ]

        var added = 0
        for entry in entries {
            var groups = hooks[entry.event] as? [[String: Any]] ?? []
            if hasCCStatusctlCommand(in: groups) {
                continue
            }
            groups.append([
                "matcher": "*",
                "hooks": [["type": "command", "command": entry.command]]
            ])
            hooks[entry.event] = groups
            added += 1
        }

        guard added > 0 else {
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

    private static func hasCCStatusctlCommand(in groups: [[String: Any]]) -> Bool {
        for group in groups {
            guard let hookList = group["hooks"] as? [[String: Any]] else {
                continue
            }
            for hook in hookList {
                if let command = hook["command"] as? String, command.contains("cc-statusctl") {
                    return true
                }
            }
        }
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
