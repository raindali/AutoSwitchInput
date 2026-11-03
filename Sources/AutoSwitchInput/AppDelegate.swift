import AppKit
import AutoSwitchInputCore

/// AppKit delegate for the menu-bar process.
///
/// 这个进程只负责菜单栏图标、右键菜单和前台应用监听，**完全不碰 SwiftUI**。
/// 设置窗口由 `AutoSwitchInputSettings`（同一二进制的副本，`--settings` 模式）承载，
/// 关窗即退出，所以 SwiftUI 的视图图、图标/文字缓存不会滞留在常驻进程里。
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    /// 弹出菜单期间持有强引用，避免 tracking 循环结束后菜单提前释放。
    private var statusMenu: NSMenu?
    /// 正在运行的设置窗口进程（同一时间只保留一个）。
    private var settingsProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupMonitor()
        RuleStore.shared.applyLaunchAtLogin() // 同步开机启动（登录项）状态
        // 纯菜单栏后台应用：启动后安静留在后台，不自动弹窗；
        // 用户点击菜单栏图标或右键菜单「设置…」时再打开设置窗口。
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 菜单栏进程退出时一并结束设置窗口进程，避免留下孤儿窗口。
        settingsProcess?.terminate()
        settingsProcess = nil
    }

    // 点击 Dock 图标时打开设置窗口（应用改为 regular 模式后生效）
    func applicationShouldHandleReopen(_ sender: NSApplication) -> Bool {
        showSettings()
        return true
    }

    // 无窗口的菜单栏应用：AppKit 在启动/被 LaunchServices 打开时会询问是否打开「未命名文稿」，
    // 直接返回 false，避免启动即弹窗（也让首次内存占用停在 ~12 MB）。
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // 标准模板图标：符合 macOS HIG（菜单栏扩展应使用模板图标），自动适配浅/深色菜单栏
            if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: L10n.t("statusItem.accessibility")) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "IME"
            }
            // 左键点击直接打开主窗口；右键弹出菜单
            button.target = self
            button.action = #selector(statusBarClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// 菜单内容按需构建：只在右键真正弹出菜单时生成。
    /// 旧实现把整份 NSMenu 在每次前台应用切换时重建一遍，纯属浪费（菜单此时并不可见）。
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Auto-switch toggle
        let toggle = NSMenuItem(
            title: L10n.t(RuleStore.shared.autoSwitchEnabled ? "menu.autoSwitch.on" : "menu.autoSwitch.off"),
            action: #selector(toggleAutoSwitch),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Current app + input method info
        if let name = AppMonitor.shared.currentAppName {
            let appItem = NSMenuItem(title: L10n.t("menu.currentApp", name), action: nil, keyEquivalent: "")
            appItem.isEnabled = false
            menu.addItem(appItem)

            if let rule = AppMonitor.shared.currentBundleID.flatMap({ RuleStore.shared.rule(for: $0) }) {
                let ruleItem = NSMenuItem(title: L10n.t("menu.ruleInputSource", rule.inputSourceName), action: nil, keyEquivalent: "")
                ruleItem.isEnabled = false
                menu.addItem(ruleItem)
            } else {
                let noRule = NSMenuItem(title: L10n.t("menu.noRule"), action: nil, keyEquivalent: "")
                noRule.isEnabled = false
                menu.addItem(noRule)
            }

            if let id = InputMethodManager.shared.getCurrentInputSourceID() {
                let cur = NSMenuItem(title: L10n.t("menu.currentInputSource", InputMethodManager.shared.name(for: id)),
                                     action: nil, keyEquivalent: "")
                cur.isEnabled = false
                menu.addItem(cur)
            }
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Monitor

    private func setupMonitor() {
        AppMonitor.shared.onAppChange = { [weak self] bundleID, appName in
            self?.handleAppChange(bundleID: bundleID, appName: appName)
        }
        AppMonitor.shared.start()

        // Apply rule for the app that was frontmost at launch
        if let bundleID = AppMonitor.shared.currentBundleID {
            handleAppChange(bundleID: bundleID, appName: AppMonitor.shared.currentAppName ?? "")
        }
    }

    private func handleAppChange(bundleID: String, appName: String) {
        guard RuleStore.shared.autoSwitchEnabled else { return }

        let targetID = RuleStore.shared.rule(for: bundleID)?.inputSourceID
            ?? RuleStore.shared.defaultInputSourceID
        guard let targetID else { return }

        if InputMethodManager.shared.selectInputSource(id: targetID) {
            Log.inputSource.debug("已切换输入法: \(targetID, privacy: .public)")
        } else {
            Log.inputSource.error("切换输入法失败: \(targetID, privacy: .public)")
        }
    }

    // 状态栏按钮点击：左键打开主窗口，右键弹出菜单
    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            showSettings()
            return
        }
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick {
            let menu = buildMenu()
            statusMenu = menu
            let point = NSPoint(x: 0, y: NSHeight(sender.bounds) + 4)
            menu.popUp(positioning: nil, at: point, in: sender)
            statusMenu = nil
        } else {
            showSettings()
        }
    }

    // MARK: - Menu Actions

    @objc private func toggleAutoSwitch() {
        RuleStore.shared.autoSwitchEnabled.toggle()
    }

    /// 打开设置窗口：拉起独立的设置进程（已在运行则把它的窗口提到前台）。
    @objc private func showSettings() {
        if let process = settingsProcess, process.isRunning {
            NSRunningApplication(processIdentifier: process.processIdentifier)?.activate()
            return
        }

        guard let executable = Bundle.main.executableURL else { return }
        // 设置界面是独立的可执行文件（AutoSwitchInputSettings），和菜单栏进程并排放在
        // Contents/MacOS 下。缺失说明 .app 打包不完整，直接报错而不是误拉起自己。
        let helper = executable.deletingLastPathComponent()
            .appendingPathComponent("AutoSwitchInputSettings")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            Log.app.error("找不到设置进程: \(helper.path, privacy: .public)")
            return
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = ["--settings"]
        var environment = ProcessInfo.processInfo.environment
        environment["ASI_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = environment
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.settingsProcess = nil }
        }

        do {
            try process.run()
            settingsProcess = process
            Log.app.debug("已拉起设置进程 pid=\(process.processIdentifier)")
        } catch {
            Log.app.error("无法启动设置窗口进程: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
