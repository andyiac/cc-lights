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
        onStyleChange: @escaping (StatusLightStyle) -> Void,
        onLanguageChange: @escaping () -> Void,
        sessionsProvider: @escaping () -> [StatusPayload],
        onSessionStyleChange: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        tabController = PreferencesTabViewController(
            notificationController: notificationController,
            initialStyle: initialStyle,
            onStyleChange: onStyleChange,
            onLanguageChange: onLanguageChange,
            sessionsProvider: sessionsProvider,
            onSessionStyleChange: onSessionStyleChange,
            onCheckForUpdates: onCheckForUpdates
        )

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = Loc.prefsWindowTitle
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

        // 会话是动态的，每次打开都刷新每-session 灯样式列表。
        tabController.reloadSessionStyles()
    }

    /// 任一集成配置变化时（配置监视器触发）刷新「集成」分页三块状态。
    func refreshIntegrationStatuses() {
        tabController.integrationViewController.refreshAll()
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
        onStyleChange: @escaping (StatusLightStyle) -> Void,
        onLanguageChange: @escaping () -> Void,
        sessionsProvider: @escaping () -> [StatusPayload],
        onSessionStyleChange: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        generalViewController = GeneralPreferencesViewController(
            initialStyle: initialStyle,
            onStyleChange: onStyleChange,
            onLanguageChange: onLanguageChange,
            sessionsProvider: sessionsProvider,
            onSessionStyleChange: onSessionStyleChange
        )
        notificationsViewController = NotificationsPreferencesViewController(
            notificationController: notificationController
        )
        integrationViewController = IntegrationPreferencesViewController()
        aboutViewController = AboutPreferencesViewController(onCheckForUpdates: onCheckForUpdates)

        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addPane(generalViewController, label: Loc.tabGeneral, symbol: "gearshape", fallback: NSImage.preferencesGeneralName)
        addPane(notificationsViewController, label: Loc.tabNotifications, symbol: "bell", fallback: NSImage.userAccountsName)
        addPane(integrationViewController, label: Loc.tabIntegration, symbol: "puzzlepiece", fallback: NSImage.networkName)
        addPane(aboutViewController, label: Loc.tabAbout, symbol: "info.circle", fallback: NSImage.infoName)
    }

    /// 会话列表是动态的，外部（窗口每次展示时）调用它刷新每-session 灯样式列表。
    func reloadSessionStyles() {
        generalViewController.reloadSessionStyles()
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
    private let onLanguageChange: () -> Void
    private let sessionsProvider: () -> [StatusPayload]
    private let onSessionStyleChange: () -> Void
    private var selectedStyle: StatusLightStyle
    private var launchCheckbox: NSButton?
    private var previewViews: [(state: StatusState, imageView: NSImageView)] = []
    private var sessionStyleContainer: NSStackView?
    private var sessionSnapshot: [StatusPayload] = []
    private var sessionRowPreviews: [Int: NSImageView] = [:]

    /// 语言分段的顺序：跟随系统 / English / 中文。
    private let languageOptions: [AppLanguage?] = [nil, .english, .chinese]

    init(
        initialStyle: StatusLightStyle,
        onStyleChange: @escaping (StatusLightStyle) -> Void,
        onLanguageChange: @escaping () -> Void,
        sessionsProvider: @escaping () -> [StatusPayload],
        onSessionStyleChange: @escaping () -> Void
    ) {
        self.selectedStyle = initialStyle
        self.onStyleChange = onStyleChange
        self.onLanguageChange = onLanguageChange
        self.sessionsProvider = sessionsProvider
        self.onSessionStyleChange = onSessionStyleChange
        super.init(nibName: nil, bundle: nil)
        title = Loc.tabGeneral
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addSectionHeader(Loc.generalStartupHeader)

        let launch = PrefsUI.checkbox(
            Loc.launchAtLoginCheckbox,
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launch.state = LaunchAtLoginManager.isEnabled ? .on : .off
        launchCheckbox = launch
        stack.addArrangedSubview(launch)
        addHelpText(Loc.launchAtLoginHelp)

        addSpacing(6)
        addSeparator()
        addSpacing(6)

        addSectionHeader(Loc.languageHeader)

        let languageLabels = languageOptions.map { $0?.displayName ?? Loc.languageSystemOption }
        let languageControl = NSSegmentedControl(
            labels: languageLabels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        languageControl.selectedSegment = languageOptions.firstIndex(where: { $0 == AppLanguage.override }) ?? 0
        stack.addArrangedSubview(languageControl)
        addHelpText(Loc.languageHelp)

        addSpacing(6)
        addSeparator()
        addSpacing(6)

        addSectionHeader(Loc.lightStyleHeader)

        // 样式数量较多，用带样图的下拉菜单（分段控件放不下）。
        let stylePopup = NSPopUpButton()
        for style in StatusLightStyle.allCases {
            stylePopup.addItem(withTitle: style.displayName)
            stylePopup.lastItem?.image = StatusIcon.image(for: .idle, style: style)
        }
        stylePopup.selectItem(at: StatusLightStyle.allCases.firstIndex(of: selectedStyle) ?? 0)
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged(_:))
        stack.addArrangedSubview(stylePopup)

        addSpacing(4)
        stack.addArrangedSubview(makePreviewRow())
        addHelpText(Loc.lightStylePreviewHelp)

        addSpacing(6)
        addSeparator()
        addSpacing(6)

        addSectionHeader(Loc.perSessionStyleHeader)

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        stack.addArrangedSubview(container)
        sessionStyleContainer = container
        populateSessionStyles(into: container)

        addHelpText(Loc.perSessionStyleHelp)
    }

    /// 窗口每次展示时刷新会话列表（会话是动态增删的）。
    func reloadSessionStyles() {
        guard isViewLoaded, let container = sessionStyleContainer else { return }
        populateSessionStyles(into: container)
    }

    private func populateSessionStyles(into container: NSStackView) {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sessionRowPreviews.removeAll()
        sessionSnapshot = sessionsProvider()

        guard !sessionSnapshot.isEmpty else {
            let empty = NSTextField(labelWithString: Loc.perSessionStyleEmpty)
            empty.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            empty.textColor = .secondaryLabelColor
            container.addArrangedSubview(empty)
            return
        }

        for (index, payload) in sessionSnapshot.enumerated() {
            container.addArrangedSubview(makeSessionRow(payload: payload, index: index))
        }
    }

    private func makeSessionRow(payload: StatusPayload, index: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        let currentStyle = SessionLightStyle.style(for: payload.sessionID)

        let preview = NSImageView()
        preview.imageScaling = .scaleNone
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 20).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 20).isActive = true
        preview.image = StatusIcon.image(for: payload.state, style: currentStyle)
        sessionRowPreviews[index] = preview
        row.addArrangedSubview(preview)

        let title = NSTextField(labelWithString: payload.displayTitle)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(title)

        let popup = NSPopUpButton()
        popup.addItems(withTitles: StatusLightStyle.allCases.map(\.displayName))
        popup.selectItem(at: StatusLightStyle.allCases.firstIndex(of: currentStyle) ?? 0)
        popup.tag = index
        popup.target = self
        popup.action = #selector(sessionStylePopupChanged(_:))
        popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(popup)

        return row
    }

    @objc private func sessionStylePopupChanged(_ sender: NSPopUpButton) {
        let index = sender.tag
        guard sessionSnapshot.indices.contains(index) else { return }
        let styleIndex = sender.indexOfSelectedItem
        guard StatusLightStyle.allCases.indices.contains(styleIndex) else { return }

        let style = StatusLightStyle.allCases[styleIndex]
        let payload = sessionSnapshot[index]
        SessionLightStyle.setStyle(style, for: payload.sessionID)
        sessionRowPreviews[index]?.image = StatusIcon.image(for: payload.state, style: style)
        onSessionStyleChange()
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

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard StatusLightStyle.allCases.indices.contains(index) else { return }
        let style = StatusLightStyle.allCases[index]
        guard style != selectedStyle else { return }

        selectedStyle = style
        refreshPreview()
        onStyleChange(style)
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard languageOptions.indices.contains(index) else { return }
        let choice = languageOptions[index]
        guard choice != AppLanguage.override else { return }

        AppLanguage.override = choice
        onLanguageChange()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        let shouldEnable = sender.state == .on
        do {
            try LaunchAtLoginManager.setEnabled(shouldEnable)
        } catch {
            sender.state = shouldEnable ? .off : .on
            PrefsUI.showError(title: Loc.launchToggleErrorTitle, message: error.localizedDescription)
        }
    }
}

// MARK: - 通知

final class NotificationsPreferencesViewController: PreferencePane {
    private let notificationController: NotificationController

    init(notificationController: NotificationController) {
        self.notificationController = notificationController
        super.init(nibName: nil, bundle: nil)
        title = Loc.tabNotifications
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addSectionHeader(Loc.notificationsHeader)

        let checkbox = PrefsUI.checkbox(
            Loc.enableNotificationsCheckbox,
            target: self,
            action: #selector(toggleNotifications(_:))
        )
        checkbox.state = notificationController.isEnabled ? .on : .off
        stack.addArrangedSubview(checkbox)

        addHelpText(Loc.notificationsHelp)
    }

    @objc private func toggleNotifications(_ sender: NSButton) {
        notificationController.isEnabled = sender.state == .on
        if notificationController.isEnabled {
            notificationController.requestAuthorizationIfNeeded()
        }
    }
}

// MARK: - 集成

/// 「集成」分页：展示五个 AI 编码工具（Claude Code / Codex / OpenCode / pi / Hermes）各自的状态灯
/// 接入配置状态，并提供「自动配置 / 重新检查 / 打开配置文件」操作。
final class IntegrationPreferencesViewController: PreferencePane {
    /// 一个工具的配置状态与操作，抽象自三个 ConfigChecker 的公共形状。
    private struct ToolConfig {
        let name: String
        let help: String
        let isConfigured: () -> Bool
        let recheck: () -> Void
        let install: () -> Void
        let openFile: () -> Void
    }

    private var toolConfigs: [ToolConfig] = []
    private var statusRows: [(icon: NSImageView, label: NSTextField, button: NSButton)] = []

    init() {
        super.init(nibName: nil, bundle: nil)
        title = Loc.tabIntegration
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addSectionHeader(Loc.integrationHeader)
        addHelpText(Loc.integrationHelp)
        addSpacing(4)

        let claude = ToolConfig(
            name: "Claude Code",
            help: Loc.integrationClaudeHelp,
            isConfigured: { ClaudeCodeConfigChecker.isHooksConfigured() },
            recheck: { ClaudeCodeConfigChecker.check() },
            install: { ClaudeCodeConfigChecker.installHooksWithUI() },
            openFile: { [weak self] in
                let url = ClaudeCodeConfigChecker.settingsFileURL
                self?.openFile(url)
            }
        )
        let codex = ToolConfig(
            name: "Codex",
            help: Loc.integrationCodexHelp,
            isConfigured: { CodexConfigChecker.isHooksConfigured() },
            recheck: { CodexConfigChecker.check() },
            install: { CodexConfigChecker.installHooksWithUI() },
            openFile: { [weak self] in
                let url = CodexConfigChecker.hooksFileURL
                self?.openFile(url)
            }
        )
        let opencode = ToolConfig(
            name: "OpenCode",
            help: Loc.integrationOpenCodeHelp,
            isConfigured: { OpenCodeConfigChecker.isConfigured() },
            recheck: { OpenCodeConfigChecker.check() },
            install: { OpenCodeConfigChecker.installPluginWithUI() },
            openFile: { [weak self] in
                let url = OpenCodeConfigChecker.pluginFileURL
                self?.openFile(url)
            }
        )
        let pi = ToolConfig(
            name: "pi",
            help: Loc.integrationPiHelp,
            isConfigured: { PiConfigChecker.isConfigured() },
            recheck: { PiConfigChecker.check() },
            install: { PiConfigChecker.installExtensionWithUI() },
            openFile: { [weak self] in
                let url = PiConfigChecker.extensionFileURL
                self?.openFile(url)
            }
        )
        let hermes = ToolConfig(
            name: "Hermes",
            help: Loc.integrationHermesHelp,
            isConfigured: { HermesConfigChecker.isConfigured() && HermesConfigChecker.isPluginEnabled() },
            recheck: { HermesConfigChecker.check() },
            install: { HermesConfigChecker.installPluginWithUI() },
            openFile: { [weak self] in
                let url = HermesConfigChecker.pluginDirectoryURL
                self?.openFile(url)
            }
        )

        toolConfigs = [claude, codex, opencode, pi, hermes]
        for (index, config) in toolConfigs.enumerated() {
            addSectionHeader(config.name)
            stack.addArrangedSubview(makeSection(for: index))
            addHelpText(config.help)
            addSpacing(4)
        }

        refreshAll()
    }

    /// 构建某工具的状态行 + 按钮行，并把对应控件记入 `statusRows` 供刷新使用。
    private func makeSection(for index: Int) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        statusRow.addArrangedSubview(icon)

        let label = NSTextField(labelWithString: "")
        statusRow.addArrangedSubview(label)
        container.addArrangedSubview(statusRow)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let install = NSButton(title: Loc.integrationAutoConfigureButton, target: self, action: #selector(installTapped(_:)))
        install.bezelStyle = .rounded
        install.tag = index
        buttonRow.addArrangedSubview(install)

        let recheck = NSButton(title: Loc.integrationRecheckButton, target: self, action: #selector(recheckTapped(_:)))
        recheck.bezelStyle = .rounded
        recheck.tag = index
        buttonRow.addArrangedSubview(recheck)

        let openSettings = NSButton(title: Loc.integrationOpenSettingsButton, target: self, action: #selector(openTapped(_:)))
        openSettings.bezelStyle = .rounded
        openSettings.tag = index
        buttonRow.addArrangedSubview(openSettings)

        container.addArrangedSubview(buttonRow)

        statusRows.append((icon, label, install))
        return container
    }

    /// 刷新三块工具状态到 UI（可从主线程外部调用）。
    func refreshAll() {
        DispatchQueue.main.async {
            for (index, row) in self.statusRows.enumerated() where index < self.toolConfigs.count {
                let configured = self.toolConfigs[index].isConfigured()
                row.icon.image = PrefsUI.symbolImage(
                    configured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    fallback: configured ? NSImage.statusAvailableName : NSImage.statusUnavailableName
                )
                row.icon.contentTintColor = configured ? .systemGreen : .systemOrange
                row.label.stringValue = configured
                    ? String(format: Loc.integrationConfiguredStatusFormat, self.toolConfigs[index].name)
                    : String(format: Loc.integrationNotConfiguredStatusFormat, self.toolConfigs[index].name)
                row.button.isEnabled = !configured
            }
        }
    }

    @objc private func installTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index < toolConfigs.count else { return }
        toolConfigs[index].install()
        refreshAll()
    }

    @objc private func recheckTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index < toolConfigs.count else { return }
        toolConfigs[index].recheck()
        refreshAll()
    }

    @objc private func openTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index < toolConfigs.count else { return }
        toolConfigs[index].openFile()
    }

    private func openFile(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

// MARK: - 关于

final class AboutPreferencesViewController: PreferencePane {
    private let onCheckForUpdates: () -> Void

    init(onCheckForUpdates: @escaping () -> Void) {
        self.onCheckForUpdates = onCheckForUpdates
        super.init(nibName: nil, bundle: nil)
        title = Loc.tabAbout
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

        let description = NSTextField(wrappingLabelWithString: Loc.aboutDescription)
        description.font = .systemFont(ofSize: NSFont.systemFontSize)
        description.textColor = .secondaryLabelColor
        description.alignment = .center
        description.translatesAutoresizingMaskIntoConstraints = false
        description.preferredMaxLayoutWidth = contentWidth
        description.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        stack.addArrangedSubview(description)

        addSpacing(6)

        let checkButton = NSButton(title: Loc.checkForUpdates, target: self, action: #selector(checkForUpdates))
        checkButton.bezelStyle = .rounded
        stack.addArrangedSubview(checkButton)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    private var appName: String {
        (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? "CC Lights"
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return Loc.aboutVersionBuild(short, build)
        }
        return Loc.aboutVersion(short)
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
