import AppKit
import StatusLightCore
import UserNotifications

// MARK: - 偏好设置窗口

/// 参考 macOS「系统设置 / Shottr」风格的偏好设置窗口：顶部工具栏分页，
/// 打开时把 App 从 accessory 切成 regular，让 Dock 出现 logo 图标；关闭后再切回，
/// 让它重新变成纯菜单栏应用。
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let tabController: PreferencesTabViewController
    private var hasCentered = false

    init(
        notificationController: NotificationController,
        initialStyle: StatusLightStyle,
        onStyleChange: @escaping (StatusLightStyle) -> Void
    ) {
        tabController = PreferencesTabViewController(
            notificationController: notificationController,
            initialStyle: initialStyle,
            onStyleChange: onStyleChange
        )

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "CC Lights 偏好设置"
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("PreferencesWindow")
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .preference
        }

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 展示窗口，并让 Dock 出现应用图标。
    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if !hasCentered {
            window?.center()
            hasCentered = true
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 集成状态变化时（配置监视器触发）同步刷新「集成」分页。
    func updateHookStatus(_ configured: Bool) {
        tabController.integrationViewController.updateStatus(configured)
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭偏好设置后回到菜单栏应用形态，隐藏 Dock 图标。
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - 分页容器

final class PreferencesTabViewController: NSTabViewController {
    let generalViewController: GeneralPreferencesViewController
    let notificationsViewController: NotificationsPreferencesViewController
    let integrationViewController: IntegrationPreferencesViewController
    let aboutViewController: AboutPreferencesViewController

    init(
        notificationController: NotificationController,
        initialStyle: StatusLightStyle,
        onStyleChange: @escaping (StatusLightStyle) -> Void
    ) {
        generalViewController = GeneralPreferencesViewController(
            initialStyle: initialStyle,
            onStyleChange: onStyleChange
        )
        notificationsViewController = NotificationsPreferencesViewController(
            notificationController: notificationController
        )
        integrationViewController = IntegrationPreferencesViewController()
        aboutViewController = AboutPreferencesViewController()

        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addPane(generalViewController, label: "通用", symbol: "gearshape", fallback: NSImage.preferencesGeneralName)
        addPane(notificationsViewController, label: "通知", symbol: "bell", fallback: NSImage.userAccountsName)
        addPane(integrationViewController, label: "集成", symbol: "puzzlepiece", fallback: NSImage.networkName)
        addPane(aboutViewController, label: "关于", symbol: "info.circle", fallback: NSImage.infoName)
    }

    private func addPane(_ controller: NSViewController, label: String, symbol: String, fallback: NSImage.Name) {
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = PrefsUI.symbolImage(symbol, fallback: fallback)
        addTabViewItem(item)
    }
}

// MARK: - 分页基类

/// 提供固定宽度、垂直堆叠布局与常用控件工厂的分页基类。
class PreferencePane: NSViewController {
    let contentWidth: CGFloat = 460
    private let inset: CGFloat = 22
    let stack = NSStackView()

    override func loadView() {
        let container = NSView()

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
            stack.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildContent()
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    /// 子类重写，向 `stack` 中追加内容。
    func buildContent() {}

    // MARK: 布局辅助

    func addSpacing(_ height: CGFloat) {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        stack.addArrangedSubview(spacer)
    }

    func addSectionHeader(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        stack.addArrangedSubview(label)
    }

    func addSeparator() {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        stack.addArrangedSubview(box)
    }

    @discardableResult
    func addHelpText(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = contentWidth
        label.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        stack.addArrangedSubview(label)
        return label
    }
}

// MARK: - 通用

final class GeneralPreferencesViewController: PreferencePane {
    private let onStyleChange: (StatusLightStyle) -> Void
    private var selectedStyle: StatusLightStyle
    private var launchCheckbox: NSButton?
    private var previewViews: [(state: StatusState, imageView: NSImageView)] = []

    init(initialStyle: StatusLightStyle, onStyleChange: @escaping (StatusLightStyle) -> Void) {
        self.selectedStyle = initialStyle
        self.onStyleChange = onStyleChange
        super.init(nibName: nil, bundle: nil)
        title = "通用"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addSectionHeader("启动")

        let launch = PrefsUI.checkbox(
            "登录时自动启动 CC Lights",
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launch.state = LaunchAtLoginManager.isEnabled ? .on : .off
        launchCheckbox = launch
        stack.addArrangedSubview(launch)
        addHelpText("开启后会在 ~/Library/LaunchAgents 中安装启动项，登录时自动拉起菜单栏指示灯。")

        addSpacing(6)
        addSeparator()
        addSpacing(6)

        addSectionHeader("状态灯样式")

        let segmented = NSSegmentedControl(
            labels: StatusLightStyle.allCases.map(\.displayName),
            trackingMode: .selectOne,
            target: self,
            action: #selector(styleChanged(_:))
        )
        segmented.selectedSegment = StatusLightStyle.allCases.firstIndex(of: selectedStyle) ?? 0
        stack.addArrangedSubview(segmented)

        addSpacing(4)
        stack.addArrangedSubview(makePreviewRow())
        addHelpText("预览从左到右依次为：无会话 / 空闲 / 等待决策 / 错误。")
    }

    private func makePreviewRow() -> NSView {
        let states: [StatusState] = [.offline, .idle, .waiting, .error]
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .centerY

        for state in states {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleNone
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 22).isActive = true
            imageView.image = StatusIcon.image(for: state, style: selectedStyle)
            previewViews.append((state, imageView))
            row.addArrangedSubview(imageView)
        }

        return row
    }

    private func refreshPreview() {
        for entry in previewViews {
            entry.imageView.image = StatusIcon.image(for: entry.state, style: selectedStyle)
        }
    }

    @objc private func styleChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard StatusLightStyle.allCases.indices.contains(index) else { return }
        let style = StatusLightStyle.allCases[index]
        guard style != selectedStyle else { return }

        selectedStyle = style
        refreshPreview()
        onStyleChange(style)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        let shouldEnable = sender.state == .on
        do {
            try LaunchAtLoginManager.setEnabled(shouldEnable)
        } catch {
            sender.state = shouldEnable ? .off : .on
            PrefsUI.showError(title: "无法更新登录启动设置", message: error.localizedDescription)
        }
    }
}

// MARK: - 通知

final class NotificationsPreferencesViewController: PreferencePane {
    private let notificationController: NotificationController

    init(notificationController: NotificationController) {
        self.notificationController = notificationController
        super.init(nibName: nil, bundle: nil)
        title = "通知"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addSectionHeader("系统通知")

        let checkbox = PrefsUI.checkbox(
            "启用系统通知",
            target: self,
            action: #selector(toggleNotifications(_:))
        )
        checkbox.state = notificationController.isEnabled ? .on : .off
        stack.addArrangedSubview(checkbox)

        addHelpText(
            "当某个 Claude Code session 进入「等待决策」（需要你授权/确认）或「执行出错」时，"
                + "发送一条系统通知提醒你。仅在以 .app 形式运行时可用。"
        )
    }

    @objc private func toggleNotifications(_ sender: NSButton) {
        notificationController.isEnabled = sender.state == .on
        if notificationController.isEnabled {
            notificationController.requestAuthorizationIfNeeded()
        }
    }
}

// MARK: - Claude Code 集成

final class IntegrationPreferencesViewController: PreferencePane {
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var installButton: NSButton?

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "集成"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addSectionHeader("Claude Code Hook 配置")

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        statusRow.addArrangedSubview(statusIcon)
        statusRow.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(statusRow)

        addHelpText(
            "指示灯依赖 ~/.claude/settings.json 中的 hooks 配置，才能随 Claude Code 的状态自动变色。"
        )

        addSpacing(8)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let install = NSButton(title: "自动配置 Hook", target: self, action: #selector(installHooks))
        install.bezelStyle = .rounded
        installButton = install
        buttonRow.addArrangedSubview(install)

        let recheck = NSButton(title: "重新检查", target: self, action: #selector(recheck))
        recheck.bezelStyle = .rounded
        buttonRow.addArrangedSubview(recheck)

        let openSettings = NSButton(title: "打开 settings.json", target: self, action: #selector(openSettingsFile))
        openSettings.bezelStyle = .rounded
        buttonRow.addArrangedSubview(openSettings)

        stack.addArrangedSubview(buttonRow)

        updateStatus(ClaudeCodeConfigChecker.isHooksConfigured())
    }

    /// 同步集成状态到 UI（可从主线程外部调用）。
    func updateStatus(_ configured: Bool) {
        DispatchQueue.main.async {
            if configured {
                self.statusIcon.image = PrefsUI.symbolImage("checkmark.circle.fill", fallback: NSImage.statusAvailableName)
                self.statusIcon.contentTintColor = .systemGreen
                self.statusLabel.stringValue = "已配置，指示灯会自动跟随 Claude Code 状态。"
            } else {
                self.statusIcon.image = PrefsUI.symbolImage("exclamationmark.triangle.fill", fallback: NSImage.statusUnavailableName)
                self.statusIcon.contentTintColor = .systemOrange
                self.statusLabel.stringValue = "未配置，指示灯不会自动变色。"
            }
            self.installButton?.isEnabled = !configured
        }
    }

    @objc private func installHooks() {
        ClaudeCodeConfigChecker.installHooksWithUI()
        updateStatus(ClaudeCodeConfigChecker.isHooksConfigured())
    }

    @objc private func recheck() {
        ClaudeCodeConfigChecker.check()
        updateStatus(ClaudeCodeConfigChecker.isHooksConfigured())
    }

    @objc private func openSettingsFile() {
        let url = ClaudeCodeConfigChecker.settingsFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

// MARK: - 关于

final class AboutPreferencesViewController: PreferencePane {
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "关于"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        stack.alignment = .centerX

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(iconView)

        let name = NSTextField(labelWithString: appName)
        name.font = .systemFont(ofSize: 18, weight: .semibold)
        name.alignment = .center
        stack.addArrangedSubview(name)

        let version = NSTextField(labelWithString: versionString)
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        stack.addArrangedSubview(version)

        addSpacing(6)

        let description = NSTextField(wrappingLabelWithString:
            "在菜单栏用交通灯的方式展示每个 Claude Code session 的状态："
                + "绿色空闲/工作、黄色等待决策、红色出错。点击指示灯可直接切回对应终端。")
        description.font = .systemFont(ofSize: NSFont.systemFontSize)
        description.textColor = .secondaryLabelColor
        description.alignment = .center
        description.translatesAutoresizingMaskIntoConstraints = false
        description.preferredMaxLayoutWidth = contentWidth
        description.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        stack.addArrangedSubview(description)
    }

    private var appName: String {
        (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? "CC Lights"
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return "版本 \(short) (\(build))"
        }
        return "版本 \(short)"
    }
}

// MARK: - 控件工厂

private enum PrefsUI {
    static func checkbox(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        return button
    }

    static func symbolImage(_ symbolName: String, fallback: NSImage.Name) -> NSImage? {
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            return image
        }
        return NSImage(named: fallback)
    }

    static func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
