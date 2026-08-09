import AppKit
import Darwin
import Foundation
import StatusLightCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var statusFileMonitor: StatusFileMonitor?
    private var integrationsConfigMonitor: IntegrationsConfigMonitor?
    private let notificationController = NotificationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try StatusFileStore.ensureDirectoryExists()
            // 兜底清理：被强杀/崩溃而未触发 SessionEnd 的残留 session（超过 24 小时未更新）。
            try StatusFileStore.pruneStale(olderThan: 24 * 60 * 60)
        } catch {
            NSAlert.showError(title: Loc.initFileErrorTitle, message: error.localizedDescription)
        }

        notificationController.requestAuthorizationIfNeeded()

        let controller = StatusBarController(notificationController: notificationController)
        statusBarController = controller
        NSApp.mainMenu = Self.buildMainMenu(preferencesTarget: controller)

        // 语言切换时重建主菜单，让「关于/隐藏/编辑/窗口」等标准菜单跟随新语言。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMainMenu),
            name: .appLanguageDidChange,
            object: nil
        )

        // 启动即自动落地内置 CLI 到稳定路径，并自动配置/修复 Claude Code hook（无需手动）。
        ClaudeCodeConfigChecker.setUpHooksOnLaunch()
        // codex 与 Claude Code 同样文件化接入，自动写入 ~/.codex/hooks.json。
        CodexConfigChecker.setUpHooksOnLaunch()
        // opencode 无 CLI hooks，改用插件订阅会话事件，自动写入 ~/.config/opencode/plugins/。
        OpenCodeConfigChecker.setUpOnLaunch()

        let monitor = StatusFileMonitor { [weak controller] payloads in
            controller?.apply(payloads)
        }
        statusFileMonitor = monitor
        monitor.start()

        let configMonitor = IntegrationsConfigMonitor { [weak controller] in
            controller?.updateHooksConfigured(true)
        }
        self.integrationsConfigMonitor = configMonitor
        configMonitor.start()

        // 启动后静默检查一次更新，有新版本时在右键菜单中提示。
        UpdateChecker.check { [weak controller] result in
            DispatchQueue.main.async {
                if case .updateAvailable(let latest) = result {
                    controller?.latestAvailableVersion = latest
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusFileMonitor?.stop()
        integrationsConfigMonitor?.stop()
    }

    @objc private func rebuildMainMenu() {
        guard let controller = statusBarController else { return }
        NSApp.mainMenu = Self.buildMainMenu(preferencesTarget: controller)
    }

    /// 构建标准主菜单：App 处于 regular（打开偏好设置显示 Dock 图标）时提供完整菜单栏，
    /// 让 ⌘, 打开偏好设置、⌘Q 退出、文本框可用 复制/粘贴 等标准编辑命令。
    private static func buildMainMenu(preferencesTarget: AnyObject) -> NSMenu {
        let appName = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String) ?? "CC Lights"
        let mainMenu = NSMenu()

        // App 菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: Loc.menuAbout(appName), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: Loc.preferences, action: #selector(StatusBarController.openPreferences), keyEquivalent: ",")
        preferencesItem.target = preferencesTarget
        appMenu.addItem(preferencesItem)
        appMenu.addItem(.separator())

        let hideItem = appMenu.addItem(withTitle: Loc.menuHide(appName), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp

        let hideOthersItem = appMenu.addItem(withTitle: Loc.menuHideOthers, action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp

        let showAllItem = appMenu.addItem(withTitle: Loc.menuShowAll, action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp

        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: Loc.menuQuit(appName), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        // 编辑菜单（供偏好设置中的文本控件使用标准命令）
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: Loc.menuEdit)
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: Loc.menuUndo, action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: Loc.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: Loc.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: Loc.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: Loc.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: Loc.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: Loc.menuWindow)
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: Loc.menuMinimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: Loc.menuZoom, action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: Loc.menuClose, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        return mainMenu
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
    private let snakeStep: TimeInterval = 0.15
    private let placeholderTag = -1
    private let cmuxDefaultBundleIdentifier = "com.cmuxterm.app"
    private var iconStyle = StatusLightStyle.current
    private var preferencesWindowController: PreferencesWindowController?
    /// 后台检查得到的最新版本号；为 nil 表示还没有结果或当前已是最新。
    var latestAvailableVersion: String?

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
            || currentSessions.contains { usesSnakeAnimation(for: $0) }
            || errorFlashStartBySessionID.values.contains { now.timeIntervalSince($0) < errorFlashDuration }
    }

    /// 大像素方块的 working 灯用「贪吃蛇」围边行走动画（逐帧换图），而非 alpha 脉动。
    private func usesSnakeAnimation(for payload: StatusPayload) -> Bool {
        guard payload.state == .working else { return false }
        return resolvedStyle(for: payload).isPixelBlockStyle
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

                    if self.usesSnakeAnimation(for: payload) {
                        let style = self.resolvedStyle(for: payload)
                        let headCell = Int(elapsed / self.snakeStep) % style.pixelBlockSnakeLoopLength
                        button.image = StatusIcon.pixelBlockSnakeImage(for: payload.state, style: style, headCell: headCell)
                        button.alphaValue = 1.0
                        hasAnimation = true
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
        let sortedSessions = currentSessions.sorted(by: sessionSort)
        // 始终至少保留一个灯：无 session 时显示灰色占位灯。
        let desiredCount = max(sortedSessions.count, 1)

        // 只按数量差增删 NSStatusItem，其余复用并原地更新。
        // 之前每次都全部 remove + 重建，频繁增删会偶发「幽灵灯残留」或新灯不刷新颜色，
        // 表现为「session 没了灯还在」「状态变了颜色不变」。复用可避免这些竞态。
        while statusItems.count < desiredCount {
            statusItems.append(makeStatusItem(tag: statusItems.count))
        }
        while statusItems.count > desiredCount {
            NSStatusBar.system.removeStatusItem(statusItems.removeLast())
        }

        visiblePayloadsByTag.removeAll()

        if sortedSessions.isEmpty {
            let statusItem = statusItems[0]
            statusItem.button?.tag = placeholderTag
            configure(statusItem, payload: nil)
            return
        }

        for (index, payload) in sortedSessions.enumerated() {
            let statusItem = statusItems[index]
            statusItem.button?.tag = index
            visiblePayloadsByTag[index] = payload
            configure(statusItem, payload: payload)
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
        let style = resolvedStyle(for: payload)
        statusItem.length = style.statusItemLength
        button.image = StatusIcon.image(for: state, style: style)
        button.title = ""
        button.toolTip = payload.map(tooltip(for:)) ?? Loc.tooltipNoSession
        button.alphaValue = 1.0
    }

    /// 解析某盏灯应使用的样式：有 session 时取其覆盖值（回落到全局默认），无 session 的占位灯用全局默认。
    private func resolvedStyle(for payload: StatusPayload?) -> StatusLightStyle {
        guard let payload else {
            return iconStyle
        }
        return SessionLightStyle.style(for: payload.sessionID)
    }

    /// 当前会话按菜单栏同样的顺序排序，供偏好设置的每-session 列表使用。
    func currentSortedSessions() -> [StatusPayload] {
        currentSessions.sorted(by: sessionSort)
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
            menu.addItem(NSMenuItem(title: Loc.noSession, action: nil, keyEquivalent: ""))
        }

        let countItem = NSMenuItem(title: Loc.sessionsCount(currentSessions.count), action: nil, keyEquivalent: "")
        menu.addItem(countItem)

        menu.addItem(.separator())

        if let payload {
            let styleItem = NSMenuItem(title: Loc.lightStyleMenu, action: nil, keyEquivalent: "")
            styleItem.submenu = makeLightStyleSubmenu(for: payload.sessionID)
            menu.addItem(styleItem)
            menu.addItem(.separator())
        }

        let resetItem = NSMenuItem(title: Loc.resetSessionToGreen, action: #selector(resetSelectedToIdle(_:)), keyEquivalent: "r")
        resetItem.target = self
        resetItem.representedObject = payload?.sessionID
        resetItem.isEnabled = payload != nil
        menu.addItem(resetItem)

        let clearErrorsItem = NSMenuItem(title: Loc.clearAllErrors, action: #selector(clearAllErrors), keyEquivalent: "")
        clearErrorsItem.target = self
        clearErrorsItem.isEnabled = currentSessions.contains { $0.state == .error }
        menu.addItem(clearErrorsItem)

        menu.addItem(.separator())

        if let latest = latestAvailableVersion,
           UpdateChecker.isNewer(latest, than: UpdateChecker.currentVersion) {
            let updateItem = NSMenuItem(title: Loc.updateAvailable(latest), action: #selector(openUpdatePage), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        let checkUpdateItem = NSMenuItem(title: Loc.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdateItem.target = self
        menu.addItem(checkUpdateItem)

        let preferencesItem = NSMenuItem(title: Loc.preferences, action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: Loc.openClaudeCodeContext, action: #selector(openClaudeCodeContext), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: Loc.quitCCLights, action: #selector(confirmQuit), keyEquivalent: "q")
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
            Loc.lineStatus(displayName(for: payload)),
            Loc.lineUpdated(relativeTimeString(since: payload.updatedAt))
        ]

        if let taskName = payload.taskName, !taskName.isEmpty {
            lines.append(Loc.lineTask(taskName))
        }

        if let message = payload.message, !message.isEmpty {
            lines.append(Loc.lineMessage(message))
        }

        if let workingDirectory = payload.workingDirectory, !workingDirectory.isEmpty {
            lines.append(Loc.lineDirectory(workingDirectory))
        }

        if let terminalTTY = payload.terminalTTY, !terminalTTY.isEmpty {
            lines.append(Loc.lineTerminal(terminalTTY))
        }

        let cmuxIDs = [payload.cmuxWorkspaceID, payload.cmuxSurfaceID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cmuxIDs.isEmpty {
            lines.append(Loc.lineCmux(cmuxIDs.joined(separator: " / ")))
        }

        return lines
    }

    private func displayName(for payload: StatusPayload) -> String {
        if payload.state == .waiting,
           Date().timeIntervalSince(payload.updatedAt) >= waitingTimeoutDelay {
            return Loc.stateWaitingTimedOut
        }

        return Loc.stateName(payload.state)
    }

    private struct SessionStyleChoice {
        let sessionID: String
        let style: StatusLightStyle
    }

    /// 为某个 session 构建「灯样式」子菜单：每个样式一行，带小样图预览，当前样式打勾。
    private func makeLightStyleSubmenu(for sessionID: String) -> NSMenu {
        let submenu = NSMenu()
        let currentStyle = SessionLightStyle.style(for: sessionID)
        for style in StatusLightStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(changeSessionLightStyle(_:)), keyEquivalent: "")
            item.target = self
            item.image = StatusIcon.image(for: .idle, style: style)
            item.representedObject = SessionStyleChoice(sessionID: sessionID, style: style)
            item.state = (style == currentStyle) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func changeSessionLightStyle(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? SessionStyleChoice else {
            return
        }
        SessionLightStyle.setStyle(choice.style, for: choice.sessionID)
        refreshStatusItemIcons()
    }

    @objc private func resetSelectedToIdle(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String,
              let payload = currentSessions.first(where: { $0.sessionID == sessionID }) else {
            NSAlert.showError(title: Loc.resetFailedTitle, message: Loc.resetFailedUnknownSession)
            return
        }

        do {
            try resetToIdle(payload)
            apply(try StatusFileStore.readAllSessions())
        } catch {
            NSAlert.showError(title: Loc.resetFailedTitle, message: error.localizedDescription)
        }
    }

    @objc private func clearAllErrors() {
        do {
            for payload in currentSessions where payload.state == .error {
                try resetToIdle(payload)
            }
            apply(try StatusFileStore.readAllSessions())
        } catch {
            NSAlert.showError(title: Loc.clearErrorsFailedTitle, message: error.localizedDescription)
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

    @objc private func checkForUpdates() {
        UpdateChecker.check { [weak self] result in
            DispatchQueue.main.async {
                self?.presentUpdateResult(result)
            }
        }
    }

    @objc private func openUpdatePage() {
        guard let url = UpdateChecker.releasePageURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func presentUpdateResult(_ result: UpdateChecker.UpdateCheckResult) {
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.alertStyle = .informational
            alert.messageText = Loc.updateUpToDateTitle
            alert.informativeText = Loc.updateUpToDateBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        case .updateAvailable(let latest):
            latestAvailableVersion = latest
            alert.alertStyle = .informational
            alert.messageText = Loc.updateAvailableTitle
            alert.informativeText = Loc.updateAvailableBody(
                current: UpdateChecker.currentVersion,
                latest: latest
            )
            alert.addButton(withTitle: Loc.buttonUpdate)
            alert.addButton(withTitle: Loc.buttonCancel)
            if alert.runModal() == .alertFirstButtonReturn {
                openUpdatePage()
            }
        case .failed:
            alert.alertStyle = .warning
            alert.messageText = Loc.updateCheckFailedTitle
            alert.informativeText = Loc.updateCheckFailedBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        }
    }

    @objc func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                notificationController: notificationController,
                initialStyle: iconStyle,
                onStyleChange: { [weak self] style in
                    self?.applyLightStyle(style)
                },
                onLanguageChange: { [weak self] in
                    self?.applyLanguageChange()
                },
                sessionsProvider: { [weak self] in
                    self?.currentSortedSessions() ?? []
                },
                onSessionStyleChange: { [weak self] in
                    self?.refreshStatusItemIcons()
                },
                onCheckForUpdates: { [weak self] in
                    self?.checkForUpdates()
                }
            )
        }
        preferencesWindowController?.present()
    }

    private func applyLightStyle(_ style: StatusLightStyle) {
        guard style != iconStyle else { return }
        iconStyle = style
        StatusLightStyle.current = style
        refreshStatusItemIcons()
    }

    /// 语言切换：刷新菜单栏灯的悬停详情，广播通知让主菜单重建，并用新语言重开偏好设置窗口。
    private func applyLanguageChange() {
        refreshStatusItemIcons()
        NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)

        guard let controller = preferencesWindowController,
              controller.window?.isVisible == true else {
            return
        }
        controller.close()
        preferencesWindowController = nil
        DispatchQueue.main.async { [weak self] in
            self?.openPreferences()
        }
    }

    func updateHooksConfigured(_ configured: Bool) {
        DispatchQueue.main.async {
            self.preferencesWindowController?.refreshIntegrationStatuses()
        }
    }

    @objc private func openClaudeCodeContext() {
        focusClaudeCodeContext(for: currentSessions.sorted(by: sessionSort).first)
    }

    @objc private func confirmQuit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Loc.quitConfirmTitle
        alert.informativeText = Loc.quitConfirmBody
        alert.addButton(withTitle: Loc.buttonQuit)
        alert.addButton(withTitle: Loc.buttonCancel)

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

    /// Ghostty 聚焦分三级降级。多个 Ghostty 副本共用同一 bundle id，故用宿主进程 PID 定位到具体副本：
    /// 1) 在该副本内按工作目录 `focus` 到对应 surface（tab 级，需自动化权限）；
    /// 2) 退化为仅精确激活该副本（无需自动化权限，权限被拒或匹配不到 surface 时兜底）；
    /// 3) 老数据无 PID / PID 失效时，脚本化 LaunchServices 认定的 canonical 副本按工作目录聚焦。
    /// 局限：同一副本内多个 surface 工作目录相同时只能命中第一个。
    private func focusGhosttySession(for payload: StatusPayload) -> Bool {
        guard isApplicationRunning(bundleIdentifier: "com.mitchellh.ghostty") else {
            return false
        }

        if let terminalPID = payload.terminalPID,
           let app = NSRunningApplication(processIdentifier: pid_t(terminalPID)) {
            if let appPath = app.bundleURL?.path,
               let workingDirectory = payload.workingDirectory, !workingDirectory.isEmpty,
               runAppleScript(ghosttyFocusScript(appPath: appPath, workingDirectory: workingDirectory)) {
                return true
            }

            if app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
                return true
            }
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

    /// 按 .app 路径精确定位某个 Ghostty 副本（区分共用 bundle id 的多个副本），
    /// 在其中按工作目录聚焦对应 surface 并把该副本带到最前。
    private func ghosttyFocusScript(appPath: String, workingDirectory: String) -> String {
        """
        tell application "\(appleScriptEscaped(appPath))"
            repeat with aTerminal in terminals
                if working directory of aTerminal is "\(appleScriptEscaped(workingDirectory))" then
                    activate
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
        alert.messageText = Loc.cannotOpenSessionTitle
        if let payload {
            let command = "cc-lights \(payload.state.rawValue) --session \"\(payload.sessionID)\" --tty \"$(tty)\" --terminal-bundle \"com.googlecode.iterm2\""
            alert.informativeText = Loc.cannotOpenSessionBody(command: command)
        } else {
            alert.informativeText = Loc.noSessionToOpenBody
        }
        alert.addButton(withTitle: Loc.buttonOK)
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
            return Loc.timeJustNow
        }
        if elapsed < 60 {
            return Loc.timeSecondsAgo(elapsed)
        }
        if elapsed < 3_600 {
            return Loc.timeMinutesAgo(elapsed / 60)
        }
        if elapsed < 86_400 {
            return Loc.timeHoursAgo(elapsed / 3_600)
        }
        return Loc.timeDaysAgo(elapsed / 86_400)
    }
}

enum StatusLightStyle: String, CaseIterable {
    case round
    case pixel
    case pixelRing
    case pixelSquare
    case pixelDiamond
    case pixelGlow
    case pixelCrab
    case pixelRobot
    case pixelCat
    case pixelBlock
    case pixelBlock3x3

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
            return Loc.lightStyleRound
        case .pixel:
            return Loc.lightStylePixel
        case .pixelRing:
            return Loc.lightStylePixelRing
        case .pixelSquare:
            return Loc.lightStylePixelSquare
        case .pixelDiamond:
            return Loc.lightStylePixelDiamond
        case .pixelGlow:
            return Loc.lightStylePixelGlow
        case .pixelCrab:
            return Loc.lightStylePixelCrab
        case .pixelRobot:
            return Loc.lightStylePixelRobot
        case .pixelCat:
            return Loc.lightStylePixelCat
        case .pixelBlock:
            return Loc.lightStylePixelBlock
        case .pixelBlock3x3:
            return Loc.lightStylePixelBlock3x3
        }
    }

    // 所有样式都占用方形宽度。
    var statusItemLength: CGFloat { NSStatusItem.squareLength }

    /// 是否为带「贪吃蛇」动画的大像素块样式。
    var isPixelBlockStyle: Bool {
        self == .pixelBlock || self == .pixelBlock3x3
    }

    /// 该大像素块样式围边行走路径的格数。
    var pixelBlockSnakeLoopLength: Int {
        StatusIcon.blockSnakeLoopLength(for: self)
    }
}

/// 每个 session 可单独覆盖灯样式；未设置时回落到全局默认 `StatusLightStyle.current`。
/// 覆盖值以 [sessionID: rawValue] 存进 UserDefaults。
enum SessionLightStyle {
    private static let defaultsKey = "sessionLightStyles"

    static func style(for sessionID: String) -> StatusLightStyle {
        guard let rawValue = overrides()[sessionID],
              let style = StatusLightStyle(rawValue: rawValue) else {
            return StatusLightStyle.current
        }
        return style
    }

    static func setStyle(_ style: StatusLightStyle, for sessionID: String) {
        var map = overrides()
        map[sessionID] = style.rawValue
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    private static func overrides() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}

enum StatusIcon {
    static func image(for state: StatusState, style: StatusLightStyle) -> NSImage {
        switch style {
        case .round:
            return roundImage(for: state)
        case .pixel:
            return pixelImage(for: state)
        case .pixelRing:
            return pixelShapeImage(mask: ringMask, for: state)
        case .pixelSquare:
            return pixelShapeImage(mask: squareMask, for: state)
        case .pixelDiamond:
            return pixelShapeImage(mask: diamondMask, for: state)
        case .pixelGlow:
            return pixelGlowImage(for: state)
        case .pixelCrab:
            return pixelSpriteImage(rows: crabSprite, for: state)
        case .pixelRobot:
            return pixelSpriteImage(rows: robotSprite, for: state)
        case .pixelCat:
            return pixelSpriteImage(rows: catSprite, for: state)
        case .pixelBlock:
            return pixelBlockImage(for: state)
        case .pixelBlock3x3:
            return pixelBlock3x3Image(for: state)
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

    // MARK: 像素风形状（圆环 / 方块 / 菱形 / 光晕）

    /// 用字符点阵定义像素形状：非空格且非 "." 的字符视为实心格。
    private static func pixelMask(_ rows: String...) -> [[Bool]] {
        rows.map { $0.map { $0 != " " && $0 != "." } }
    }

    private static let circleMask = pixelMask(
        "..XXX..",
        ".XXXXX.",
        "XXXXXXX",
        "XXXXXXX",
        "XXXXXXX",
        ".XXXXX.",
        "..XXX.."
    )

    private static let ringMask = pixelMask(
        "..XXX..",
        ".XXXXX.",
        "XX...XX",
        "XX...XX",
        "XX...XX",
        ".XXXXX.",
        "..XXX.."
    )

    private static let squareMask = pixelMask(
        ".XXXXX.",
        "XXXXXXX",
        "XXXXXXX",
        "XXXXXXX",
        "XXXXXXX",
        "XXXXXXX",
        ".XXXXX."
    )

    private static let diamondMask = pixelMask(
        "...X...",
        "..XXX..",
        ".XXXXX.",
        "XXXXXXX",
        ".XXXXX.",
        "..XXX..",
        "...X..."
    )

    private static func pixelShapeImage(mask: [[Bool]], for state: StatusState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let context = NSGraphicsContext.current
        context?.shouldAntialias = false
        context?.imageInterpolation = .none

        drawPixelShape(mask: mask, origin: NSPoint(x: 2, y: 2), scale: 2, color: pixelColor(for: state))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// 像素光晕：先画一圈半透明外扩像素，再叠上实心圆点。
    private static func pixelGlowImage(for state: StatusState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let context = NSGraphicsContext.current
        context?.shouldAntialias = false
        context?.imageInterpolation = .none

        let color = pixelColor(for: state)
        drawPixelHalo(mask: circleMask, origin: NSPoint(x: 2, y: 2), scale: 2, color: color)
        drawPixelShape(mask: circleMask, origin: NSPoint(x: 2, y: 2), scale: 2, color: color)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// 按点阵绘制像素形状：描边格用暗色，左上高光、右下阴影营造立体感。
    private static func drawPixelShape(mask: [[Bool]], origin: NSPoint, scale: CGFloat, color: NSColor) {
        let rows = mask.count
        let cols = mask.map(\.count).max() ?? 0
        guard rows > 0, cols > 0 else { return }

        let borderColor = color.blended(withFraction: 0.25, of: .black) ?? color
        let shadowColor = color.blended(withFraction: 0.12, of: .black) ?? color
        let highlightColor = color.blended(withFraction: 0.7, of: .white) ?? color

        for row in 0..<rows {
            for column in 0..<mask[row].count where mask[row][column] {
                let onBorder = !maskCell(mask, row - 1, column)
                    || !maskCell(mask, row + 1, column)
                    || !maskCell(mask, row, column - 1)
                    || !maskCell(mask, row, column + 1)
                let ny = Double(row) / Double(max(rows - 1, 1))
                let nx = Double(column) / Double(max(cols - 1, 1))
                let isHighlight = ny <= 0.35 && nx >= 0.45
                let isShadow = ny >= 0.65 || nx >= 0.65
                let fill: NSColor = onBorder
                    ? borderColor
                    : (isHighlight ? highlightColor : (isShadow ? shadowColor : color))

                fill.setFill()
                NSRect(
                    x: origin.x + CGFloat(column) * scale,
                    y: origin.y + CGFloat(rows - 1 - row) * scale,
                    width: scale,
                    height: scale
                ).fill()
            }
        }
    }

    /// 在形状外围紧邻的空格里画半透明像素，形成光晕。
    private static func drawPixelHalo(mask: [[Bool]], origin: NSPoint, scale: CGFloat, color: NSColor) {
        let rows = mask.count
        let cols = mask.map(\.count).max() ?? 0
        guard rows > 0, cols > 0 else { return }

        color.withAlphaComponent(0.28).setFill()
        for row in -1...rows {
            for column in -1...cols where !maskCell(mask, row, column) {
                let adjacent = maskCell(mask, row - 1, column) || maskCell(mask, row + 1, column)
                    || maskCell(mask, row, column - 1) || maskCell(mask, row, column + 1)
                    || maskCell(mask, row - 1, column - 1) || maskCell(mask, row - 1, column + 1)
                    || maskCell(mask, row + 1, column - 1) || maskCell(mask, row + 1, column + 1)
                guard adjacent else { continue }
                NSRect(
                    x: origin.x + CGFloat(column) * scale,
                    y: origin.y + CGFloat(rows - 1 - row) * scale,
                    width: scale,
                    height: scale
                ).fill()
            }
        }
    }

    private static func maskCell(_ mask: [[Bool]], _ row: Int, _ column: Int) -> Bool {
        guard row >= 0, row < mask.count, column >= 0, column < mask[row].count else {
            return false
        }
        return mask[row][column]
    }

    // MARK: 像素风生物 / 机器人 sprite

    /// sprite 点阵调色板：'X' 身体（状态色）、'#' 暗部（混黑）、'o' 眼睛（近黑）、'*' 白色高光，其余为空。
    private static let crabSprite = [
        "...o.o...",
        "...X.X...",
        "XX.XXX.XX",
        "XXXXXXXXX",
        ".XXXXXXX.",
        "..XXXXX..",
        ".#.#.#.#."
    ]

    private static let robotSprite = [
        "...oo...",
        "...##...",
        ".XXXXXX.",
        ".XoXXoX.",
        ".XXXXXX.",
        ".X#XX#X.",
        "..XXXX..",
        ".XXXXXX.",
        ".X....X."
    ]

    private static let catSprite = [
        "X.....X",
        "XX...XX",
        "XXXXXXX",
        "XoXXXoX",
        "XXXoXXX",
        ".XXXXX.",
        "..X.X.."
    ]

    /// 把 sprite 点阵居中绘制到 18×18 画布（scale 2）。形状表达样式，颜色仍表达状态。
    private static func pixelSpriteImage(rows: [String], for state: StatusState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let context = NSGraphicsContext.current
        context?.shouldAntialias = false
        context?.imageInterpolation = .none

        let scale: CGFloat = 2
        let width = rows.map(\.count).max() ?? 0
        let height = rows.count
        let origin = NSPoint(
            x: (18 - CGFloat(width) * scale) / 2,
            y: (18 - CGFloat(height) * scale) / 2
        )
        drawPixelSprite(rows: rows, origin: origin, scale: scale, color: pixelColor(for: state))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawPixelSprite(rows: [String], origin: NSPoint, scale: CGFloat, color: NSColor) {
        let dark = color.blended(withFraction: 0.42, of: .black) ?? color
        let eye = color.blended(withFraction: 0.80, of: .black) ?? .black
        let height = rows.count

        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() {
                let fill: NSColor?
                switch character {
                case "X": fill = color
                case "#": fill = dark
                case "o": fill = eye
                case "*": fill = .white
                default: fill = nil
                }
                guard let fill else { continue }

                fill.setFill()
                NSRect(
                    x: origin.x + CGFloat(column) * scale,
                    y: origin.y + CGFloat(height - 1 - row) * scale,
                    width: scale,
                    height: scale
                ).fill()
            }
        }
    }

    /// 方形大像素块：完整的 4×4，像素间以暗色分隔线区分。
    private static let blockMask = [
        [true, true, true, true],
        [true, true, true, true],
        [true, true, true, true],
        [true, true, true, true]
    ]

    /// 3×3 大像素块。
    private static let block3x3Mask = [
        [true, true, true],
        [true, true, true],
        [true, true, true]
    ]

    private static func pixelBlockImage(for state: StatusState) -> NSImage {
        blockImage(for: state, mask: blockMask, pitch: 4, cell: 3)
    }

    private static func pixelBlock3x3Image(for state: StatusState) -> NSImage {
        blockImage(for: state, mask: block3x3Mask, pitch: 5, cell: 4)
    }

    /// 静态大像素块的通用绘制。3×3 用稍大的 pitch/cell 以填满同样的 18pt 图标。
    private static func blockImage(
        for state: StatusState,
        mask: [[Bool]],
        pitch: CGFloat,
        cell: CGFloat
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let context = NSGraphicsContext.current
        context?.shouldAntialias = false
        context?.imageInterpolation = .none

        let rows = mask.count
        let cols = mask[0].count
        let total = CGFloat(cols) * pitch
        let origin = NSPoint(x: (18 - total) / 2, y: (18 - total) / 2)

        // 大像素块本体（每格之间留 1px 空隙，pixel 分得更清）
        pixelColor(for: state).setFill()
        fillBlock(mask, rows: rows, cols: cols, origin: origin, pitch: pitch, cell: cell)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// 大像素格的位置：以 pitch 为步长、每格实际占用 `cell`，从而在格与格之间留出空隙。
    private static func blockCellRect(
        row: Int,
        column: Int,
        rows: Int,
        origin: NSPoint,
        pitch: CGFloat,
        cell: CGFloat
    ) -> NSRect {
        NSRect(
            x: origin.x + CGFloat(column) * pitch,
            y: origin.y + CGFloat(rows - 1 - row) * pitch,
            width: cell,
            height: cell
        )
    }

    private static func fillBlock(
        _ mask: [[Bool]],
        rows: Int,
        cols: Int,
        origin: NSPoint,
        pitch: CGFloat,
        cell: CGFloat
    ) {
        for row in 0..<rows {
            for column in 0..<cols where maskCell(mask, row, column) {
                blockCellRect(
                    row: row,
                    column: column,
                    rows: rows,
                    origin: origin,
                    pitch: pitch,
                    cell: cell
                ).fill()
            }
        }
    }

    /// 大像素方块四周的「贪吃蛇」行走路径：沿 4×4 方块外圈顺时针走一圈，每步都是正交相邻格子。
    private static let blockSnakeLoop: [(row: Int, column: Int)] = [
        (0, 0), (0, 1), (0, 2), (0, 3),
        (1, 3), (2, 3), (3, 3),
        (3, 2), (3, 1), (3, 0),
        (2, 0), (1, 0)
    ]

    /// 3×3 方块四周的「贪吃蛇」行走路径：沿外圈顺时针走一圈（共 8 格）。
    private static let block3x3SnakeLoop: [(row: Int, column: Int)] = [
        (0, 0), (0, 1), (0, 2),
        (1, 2), (2, 2),
        (2, 1), (2, 0),
        (1, 0)
    ]

    static func blockSnakeLoopLength(for style: StatusLightStyle) -> Int {
        switch style {
        case .pixelBlock:
            return blockSnakeLoop.count
        case .pixelBlock3x3:
            return block3x3SnakeLoop.count
        default:
            return 0
        }
    }

    /// 大像素块「贪吃蛇」围边行走的一帧。`headCell` 为蛇头所在的路径格序号（0..<snakeLoop.count）。
    /// 蛇头最亮，身体逐格变暗，尾巴淡入暗色底块，看起来像一条蛇绕方块转圈。
    static func pixelBlockSnakeImage(for state: StatusState, style: StatusLightStyle, headCell: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let context = NSGraphicsContext.current
        context?.shouldAntialias = false
        context?.imageInterpolation = .none

        let color = pixelColor(for: state)

        let mask: [[Bool]]
        let loop: [(row: Int, column: Int)]
        let length: Int
        let pitch: CGFloat
        let cell: CGFloat
        let rows: Int
        let cols: Int

        switch style {
        case .pixelBlock:
            mask = blockMask
            loop = blockSnakeLoop
            length = 4
            pitch = 4
            cell = 3
            rows = blockMask.count
            cols = 4
        case .pixelBlock3x3:
            mask = block3x3Mask
            loop = block3x3SnakeLoop
            length = 3
            pitch = 5
            cell = 4
            rows = block3x3Mask.count
            cols = 3
        default:
            mask = blockMask
            loop = blockSnakeLoop
            length = 4
            pitch = 4
            cell = 3
            rows = blockMask.count
            cols = 4
        }

        let total = CGFloat(cols) * pitch
        let origin = NSPoint(x: (18 - total) / 2, y: (18 - total) / 2)

        // 底块（压暗，让行走的蛇突显出来），每格之间留 1px 空隙
        let base = color.blended(withFraction: 0.30, of: .black) ?? color
        base.setFill()
        fillBlock(mask, rows: rows, cols: cols, origin: origin, pitch: pitch, cell: cell)

        // 蛇身：从蛇头到尾巴逐渐压暗
        let loopCount = loop.count
        for offset in 0..<length {
            let index = ((headCell - offset) % loopCount + loopCount) % loopCount
            let snakeCell = loop[index]
            let t = CGFloat(offset) / CGFloat(length - 1)
            let segment = color.blended(withFraction: 0.28 * t, of: .black) ?? color
            segment.setFill()
            blockCellRect(
                row: snakeCell.row,
                column: snakeCell.column,
                rows: rows,
                origin: origin,
                pitch: pitch,
                cell: cell
            ).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
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
                NSAlert.showError(title: Loc.readSessionErrorTitle, message: error.localizedDescription)
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
/// 监视各工具配置目录（~/.claude、~/.codex、~/.config/opencode/plugins），
/// 任一变化都触发一次回调（刷新「集成」分页三块状态）。
final class IntegrationsConfigMonitor {
    private let queue = DispatchQueue(label: "ClaudeCodeStatusLight.IntegrationsMonitor")
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private let directoryURLs: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins")
    ]

    init(onChange: @escaping () -> Void) {
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
            self.cancelAllSources()
        }
    }

    private func startMonitoring() {
        cancelAllSources()

        for directoryURL in directoryURLs {
            let fileDescriptor = open(directoryURL.path, O_EVTONLY)
            guard fileDescriptor >= 0 else {
                continue // 目录尚不存在（如未安装相应工具时），跳过；配置写入后再重启会补上。
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

            sources.append(newSource)
            newSource.resume()
        }
    }

    private func handleEvent() {
        notifyState()

        // 若任一被监视目录被删除（工具改路径/卸载），需要重启监视：简单起见每次事件后
        // 都重建监视源，保证目录重建后能继续工作。
        cancelAllSources()
        queue.asyncAfter(deadline: .now() + 0.1) {
            self.startMonitoring()
        }
    }

    private func notifyState() {
        DispatchQueue.main.async {
            self.onChange()
        }
    }

    private func cancelAllSources() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
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
            send(title: Loc.notifyWaitingTitle, body: payload.message ?? Loc.notifyWaitingBody)
        case (_, .error) where previousState != .error:
            send(title: Loc.notifyErrorTitle, body: payload.message ?? Loc.notifyErrorBody)
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

    /// 供偏好设置「集成」分页打开/定位配置文件使用。
    static var settingsFileURL: URL { claudeSettingsURL }

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
            alert.messageText = Loc.autoConfiguredTitle
            alert.informativeText = Loc.autoConfiguredBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        }
    }

    /// 用户从菜单手动检查（每次都弹结果）
    static func check() {
        let configured = isHooksConfigured()
        let alert = NSAlert()
        alert.alertStyle = configured ? .informational : .warning
        alert.messageText = configured ? Loc.hookConfiguredTitle : Loc.hookNotConfiguredTitle
        let exampleJSON = """
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
        """
        alert.informativeText = configured
            ? Loc.hookConfiguredBody
            : Loc.hookNotConfiguredBody(json: exampleJSON)
        if !configured {
            alert.addButton(withTitle: Loc.autoConfigureButton)
        }
        alert.addButton(withTitle: Loc.buttonOK)
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
                return Loc.invalidSettingsError
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
            alert.messageText = didChange ? Loc.hooksWrittenTitle : Loc.hookConfiguredTitle
            alert.informativeText = didChange ? Loc.hooksMergedBody : Loc.hooksNoChangeBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        } catch {
            NSAlert.showError(title: Loc.writeConfigFailedTitle, message: error.localizedDescription)
        }
    }

    /// hook 里写入的 cc-lights 命令：优先用稳定托管路径（与 App 名/位置无关），
    /// 其次用 App 内置副本，最后退回裸命令（开发环境）。带引号兼容路径含空格。
    static func statusctlCommand() -> String {
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

// MARK: - Codex 集成

/// 管理 codex (OpenAI) 的 hooks.json 配置。codex 与 Claude Code 不同：
/// hook 上下文全部走 stdin JSON（`session_id`/`cwd`/`hook_event_name`），无 CLAUDE_* 环境变量。
enum CodexConfigChecker {
    private static let codexHooksURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/hooks.json")

    /// 供偏好设置「集成」分页打开/定位配置文件使用。
    static var hooksFileURL: URL { codexHooksURL }

    private static let hasAutoConfiguredKey = "hasAutoConfiguredCodexHooks"

    /// 启动时幂等配置 codex hooks：
    /// - 已配置：把命令刷新为稳定路径。
    /// - 未配置且首次运行：自动写入（无需用户手动）。
    static func setUpHooksOnLaunch() {
        guard codexSeemsInstalled() else {
            return
        }
        _ = ClaudeCodeConfigChecker.installManagedCLI()

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

    /// codex 是否可能已安装：~/.codex 存在即可（安装路径不固定，可能不在 PATH 上）。
    static func codexSeemsInstalled() -> Bool {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        return FileManager.default.fileExists(atPath: codexDirectory.path)
    }

    private static func notifyAutoConfigured() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = Loc.codexAutoConfiguredTitle
            alert.informativeText = Loc.codexAutoConfiguredBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        }
    }

    /// 用户从菜单手动检查（每次都弹结果）。
    static func check() {
        let configured = isHooksConfigured()
        let alert = NSAlert()
        alert.alertStyle = configured ? .informational : .warning
        alert.messageText = configured ? Loc.codexHookConfiguredTitle : Loc.codexHookNotConfiguredTitle
        alert.informativeText = configured
            ? Loc.codexHookConfiguredBody
            : Loc.codexHookNotConfiguredBody
        if !configured {
            alert.addButton(withTitle: Loc.autoConfigureButton)
        }
        alert.addButton(withTitle: Loc.buttonOK)
        if !configured, alert.runModal() == .alertFirstButtonReturn {
            installHooksWithUI()
        }
    }

    static func isHooksConfigured() -> Bool {
        guard let data = try? Data(contentsOf: codexHooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        let requiredHooks: Set<String> = ["SessionStart", "Stop"]
        let configuredHooks = Set(hooks.keys)
        return requiredHooks.isSubset(of: configuredHooks)
    }

    enum ConfigError: LocalizedError {
        case invalidHooks

        var errorDescription: String? {
            switch self {
            case .invalidHooks:
                return Loc.codexInvalidHooksError
            }
        }
    }

    /// 把状态灯 hook 安全合并进 hooks.json：只追加自己的分组、不动用户已有配置、写前备份。
    @discardableResult
    static func installHooks() throws -> Bool {
        let url = codexHooksURL
        let fileManager = FileManager.default
        let fileExists = fileManager.fileExists(atPath: url.path)

        var root: [String: Any] = [:]
        if fileExists {
            let data = try Data(contentsOf: url)
            if !data.isEmpty {
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ConfigError.invalidHooks
                }
                root = parsed
            }
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let cli = ClaudeCodeConfigChecker.statusctlCommand()

        // codex 事件 → cc-lights hook 子命令。
        // 命令里不传 session/cwd：codex 会把 JSON 放在 stdin，CLI 自己解析。
        let entries: [(event: String, command: String)] = [
            ("SessionStart", "\(cli) hook working"),
            ("UserPromptSubmit", "\(cli) hook working"),
            ("PreToolUse", "\(cli) hook working"),
            ("PostToolUse", "\(cli) hook working"),
            ("PermissionRequest", "\(cli) hook waiting"),
            ("Stop", "\(cli) hook idle"),
            ("SessionEnd", "\(cli) hook remove")
        ]

        var changed = false
        for entry in entries {
            var groups = hooks[entry.event] as? [[String: Any]] ?? []
            let newGroup: [String: Any] = [
                "hooks": [["type": "command", "command": entry.command]]
            ]

            // 替换本 App 之前写入的同 event 的 cc-lights 分组（可能来自旧配置），保留用户其它 hook。
            if let index = groups.firstIndex(where: { group in
                ((group["hooks"] as? [[String: Any]])?
                    .contains { (($0["command"] as? String) ?? "").contains("cc-lights")
                        || (($0["command"] as? String) ?? "").contains("cc-statusctl") } ?? false)
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
                .appendingPathComponent("hooks.json.bak-\(formatter.string(from: Date()))")
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
            alert.messageText = didChange ? Loc.codexHooksWrittenTitle : Loc.codexHookConfiguredTitle
            alert.informativeText = didChange ? Loc.codexHooksMergedBody : Loc.hooksNoChangeBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        } catch {
            NSAlert.showError(title: Loc.writeConfigFailedTitle, message: error.localizedDescription)
        }
    }
}

// MARK: - OpenCode 集成

/// 管理 opencode 的状态灯插件。opencode 没有 CLI hooks，只能通过 JS/TS 插件
/// 订阅会话事件；插件文件放在全局插件目录 `~/.config/opencode/plugins/`，
/// opencode 启动时自动加载。插件调用托管 CLI 同步状态。
enum OpenCodeConfigChecker {
    private static let opencodeConfigDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/opencode", isDirectory: true)
    private static let pluginsDirectory = opencodeConfigDirectory
        .appendingPathComponent("plugins", isDirectory: true)
    private static let pluginFileName = "cc-lights.js"

    static var pluginFileURL: URL {
        pluginsDirectory.appendingPathComponent(pluginFileName, isDirectory: false)
    }

    private static let hasAutoConfiguredKey = "hasAutoConfiguredOpenCodePlugin"

    static func setUpOnLaunch() {
        guard opencodeSeemsInstalled() else {
            return
        }
        _ = ClaudeCodeConfigChecker.installManagedCLI()

        let firstRun = !UserDefaults.standard.bool(forKey: hasAutoConfiguredKey)
        UserDefaults.standard.set(true, forKey: hasAutoConfiguredKey)

        if isConfigured() {
            _ = try? installPlugin()
            return
        }

        guard firstRun else { return }

        if (try? installPlugin()) == true {
            notifyAutoConfigured()
        }
    }

    /// opencode 是否可能已安装：二进制常位于 ~/.opencode/bin/opencode（PATH 上）。
    static func opencodeSeemsInstalled() -> Bool {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".opencode/bin/opencode", isDirectory: false),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/opencode", isDirectory: false)
        ]
        let fileManager = FileManager.default
        if candidates.contains(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return true
        }
        return fileManager.fileExists(atPath: opencodeConfigDirectory.path)
    }

    private static func notifyAutoConfigured() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = Loc.opencodeAutoConfiguredTitle
            alert.informativeText = Loc.opencodeAutoConfiguredBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        }
    }

    static func check() {
        let configured = isConfigured()
        let alert = NSAlert()
        alert.alertStyle = configured ? .informational : .warning
        alert.messageText = configured ? Loc.opencodeConfiguredTitle : Loc.opencodeNotConfiguredTitle
        alert.informativeText = configured ? Loc.opencodeConfiguredBody : Loc.opencodeNotConfiguredBody
        if !configured {
            alert.addButton(withTitle: Loc.autoConfigureButton)
        }
        alert.addButton(withTitle: Loc.buttonOK)
        if !configured, alert.runModal() == .alertFirstButtonReturn {
            installPluginWithUI()
        }
    }

    static func isConfigured() -> Bool {
        guard let current = try? String(contentsOf: pluginFileURL, encoding: .utf8) else {
            return false
        }
        let cliPath = managedCLIPath()
        // 已安装且指向当前托管 CLI 路径才算已配置（路径变了需刷新）。
        return current.contains(cliPath)
    }

    enum InstallError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let reason):
                return reason
            }
        }
    }

    /// 生成并幂等写入 opencode 插件文件。返回是否真正写入了改动。
    @discardableResult
    static func installPlugin() throws -> Bool {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: pluginsDirectory,
            withIntermediateDirectories: true
        )

        let content = pluginSource(cliPath: managedCLIPath())

        let url = pluginFileURL
        if let existing = try? String(contentsOf: url, encoding: .utf8),
           existing == content {
            return false
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    /// 插件内 Bun.spawn 需要的裸路径（不带 shell 引号，argv 数组不经过 shell）。
    private static func managedCLIPath() -> String {
        if let url = ClaudeCodeConfigChecker.existingManagedCLIURL() ?? bundledStatusctlURL() {
            return url.path
        }
        return "cc-lights"
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

    static func installPluginWithUI() {
        do {
            let didChange = try installPlugin()
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = didChange ? Loc.opencodePluginWrittenTitle : Loc.opencodeConfiguredTitle
            alert.informativeText = didChange ? Loc.opencodePluginWrittenBody : Loc.hooksNoChangeBody
            alert.addButton(withTitle: Loc.buttonOK)
            alert.runModal()
        } catch {
            NSAlert.showError(title: Loc.writeConfigFailedTitle, message: error.localizedDescription)
        }
    }

    /// 生成插件源码。插件导出异步初始化函数返回 hook 集合；通过 `event` hook
    /// 订阅所有事件，按事件类型映射到 cc-lights 状态。CLI 路径在安装时内嵌。
    static func pluginSource(cliPath: String) -> String {
        """
        // CC Lights status plugin for opencode.
        // Generated by CC Lights — do not edit manually; the app rewrites this file on each launch.
        // It maps opencode session events to the CC Lights status via the bundled CLI.
        const CLI = \(String(reflecting: cliPath));

        function run(args) {
          try {
            const proc = Bun.spawn([CLI, ...args], { stdio: ["ignore", "pipe", "pipe"] });
            proc.exited.catch(() => {});
          } catch (_e) {
            // Never let a status sync failure break opencode.
          }
        }

        export const CCLightsPlugin = async ({ directory }) => {
          return {
            event: async ({ event }) => {
              const props = event.properties || {};
              switch (event.type) {
                case "session.created":
                  if (props.info?.id) {
                    run(["working", "--session", props.info.id, "--cwd", props.info.directory || directory]);
                  }
                  break;
                case "session.status":
                  if (props.sessionID && (props.status?.type === "busy" || props.status?.type === "retry")) {
                    run(["working", "--session", props.sessionID, "--cwd", directory]);
                  }
                  break;
                case "session.idle":
                  if (props.sessionID) {
                    run(["idle", "--session", props.sessionID, "--cwd", directory]);
                  }
                  break;
                case "session.error":
                  if (props.sessionID) {
                    run(["error", "--session", props.sessionID, "--cwd", directory]);
                  }
                  break;
                case "session.deleted":
                  if (props.info?.id) {
                    run(["remove", "--session", props.info.id]);
                  }
                  break;
                case "permission.updated":
                  if (props.sessionID) {
                    run(["waiting", "--session", props.sessionID, "--cwd", directory]);
                  }
                  break;
                case "tool.execute.before":
                  if (props.sessionID) {
                    run(["working", "--session", props.sessionID, "--cwd", directory]);
                  }
                  break;
              }
            },
          };
        };
        """
    }
}

// MARK: - 版本更新检查

/// 查询 GitHub Releases 最新版本，与本地版本比较，供「检查更新」菜单项/关于页使用。
enum UpdateChecker {
    private static let repoOwner = "andyiac"
    private static let repoName = "cc-lights"

    enum UpdateCheckResult {
        case upToDate
        case updateAvailable(String)
        case failed
    }

    /// 当前本地安装的版本（来自 Info.plist，如 `0.1.7`）。
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "0.0.0"
    }

    /// 触发一次网络检查；结果在主线程回调。
    static func check(completion: @escaping (UpdateCheckResult) -> Void) {
        guard let url = apiURL else {
            completion(.failed)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                completion(.failed)
                return
            }

            // tag 形如 "v0.1.7"，去掉 "v" 前缀后参与比较。
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard isNewer(latest, than: currentVersion) else {
                completion(.upToDate)
                return
            }
            completion(.updateAvailable(latest))
        }.resume()
    }

    private static var apiURL: URL? {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")
    }

    static var releasePageURL: URL? {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")
    }

    /// 版本号比较：`lhs > rhs`？按点分段取整比较，支持 `0.1.7` 与 `0.10.0`。
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
