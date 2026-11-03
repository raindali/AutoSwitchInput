import AppKit
import Foundation
import ServiceManagement

public extension Notification.Name {
    /// 规则变更的跨进程通知（菜单栏进程 ⇄ 设置窗口进程）。
    static let autoSwitchRulesDidChange = Notification.Name("com.qingwei.inputswitch.rulesDidChange")
}

/// Observable store for app rules and settings, persisted to UserDefaults.
///
/// 设置窗口运行在独立进程里，因此写入 UserDefaults 后需要通知另一个进程重新读取，
/// 否则菜单栏进程仍会用旧规则去切换输入法。
@MainActor
public final class RuleStore: ObservableObject {
    public static let shared = RuleStore()

    @Published public var autoSwitchEnabled: Bool {
        didSet { save() }
    }
    @Published public var rules: [AppRule] {
        didSet { save() }
    }
    @Published public var defaultInputSourceID: String? {
        didSet { save() }
    }
    /// 是否开机启动（登录项）。写入 UserDefaults 并同步系统登录项状态。
    @Published public var launchAtLogin: Bool {
        didSet {
            save()
            applyLaunchAtLoginIfNeeded()
        }
    }

    private let defaults: UserDefaults
    /// 是否与另一个进程互发变更通知（单元测试里关掉，避免相互干扰）。
    private let syncsAcrossProcesses: Bool
    /// 是否由本进程写系统登录项（单元测试里关掉，避免真的注册登录项）。
    private let managesLaunchAtLogin: Bool

    private let rulesKey = "appRules"
    private let enabledKey = "autoSwitchEnabled"
    private let defaultKey = "defaultInputSourceID"
    private let launchKey = "launchAtLogin"
    private let firstLaunchKey = "hasLaunchedBefore"

    /// 正在应用来自另一个进程的变更：此时属性赋值不应再触发保存/回发通知。
    private var isApplyingRemoteChange = false
    /// 上次同步给系统的登录项状态，避免每次保存都去问 SMAppService。
    private var lastAppliedLaunchAtLogin: Bool?
    private var remoteObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - defaults: 存储后端，默认 `UserDefaults.standard`（测试可注入独立 suite）。
    ///   - syncsAcrossProcesses: 是否启用跨进程通知同步。
    ///   - managesLaunchAtLogin: 是否负责同步系统登录项（仅菜单栏进程负责）。
    public init(
        defaults: UserDefaults = .standard,
        syncsAcrossProcesses: Bool = true,
        managesLaunchAtLogin: Bool = true
    ) {
        self.defaults = defaults
        self.syncsAcrossProcesses = syncsAcrossProcesses
        self.managesLaunchAtLogin = managesLaunchAtLogin

        autoSwitchEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        defaultInputSourceID = defaults.string(forKey: defaultKey)
        launchAtLogin = defaults.bool(forKey: launchKey)

        if let data = defaults.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([AppRule].self, from: data) {
            rules = decoded
        } else {
            rules = []
        }

        // Seed default rules on first launch
        if !defaults.bool(forKey: firstLaunchKey) {
            if rules.isEmpty {
                rules = RuleStore.defaultRules()
            }
            defaults.set(true, forKey: firstLaunchKey)
            // 首次启动就把默认规则落盘：否则只要用户没改动过任何设置，
            // 下次启动读不到 appRules，默认规则会凭空消失。
            save()
        }

        if syncsAcrossProcesses {
            remoteObserver = DistributedNotificationCenter.default().addObserver(
                forName: .autoSwitchRulesDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let pid = notification.userInfo?["pid"] as? Int,
                      pid != Int(ProcessInfo.processInfo.processIdentifier)
                else { return }
                // 通知队列固定为 .main，这里可以直接断言主 actor 隔离。
                MainActor.assumeIsolated {
                    Log.rules.debug("收到跨进程规则变更，重新读取")
                    self.reloadFromDefaults()
                }
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        guard !isApplyingRemoteChange else { return }
        defaults.set(autoSwitchEnabled, forKey: enabledKey)
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: rulesKey)
        }
        defaults.set(defaultInputSourceID, forKey: defaultKey)
        defaults.set(launchAtLogin, forKey: launchKey)

        guard syncsAcrossProcesses else { return }
        DistributedNotificationCenter.default().postNotificationName(
            .autoSwitchRulesDidChange,
            object: nil,
            userInfo: ["pid": Int(ProcessInfo.processInfo.processIdentifier)],
            deliverImmediately: true
        )
    }

    /// 从 UserDefaults 重新读取另一个进程写入的变更（不触发保存，避免通知回环）。
    func reloadFromDefaults() {
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        let newEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        if newEnabled != autoSwitchEnabled {
            autoSwitchEnabled = newEnabled
        }

        let newDefaultID = defaults.string(forKey: defaultKey)
        if newDefaultID != defaultInputSourceID {
            defaultInputSourceID = newDefaultID
        }

        let newLaunch = defaults.bool(forKey: launchKey)
        if newLaunch != launchAtLogin {
            launchAtLogin = newLaunch
        }

        if let data = defaults.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([AppRule].self, from: data),
           decoded != rules {
            rules = decoded
        }
    }

    // MARK: - Launch at login

    /// 根据 launchAtLogin 同步系统的登录项（开机启动）状态。
    /// 使用 SMAppService.mainApp（macOS 13+），需要在 /Applications 中运行才生效。
    public func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            Log.rules.error("开机启动设置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 只有菜单栏进程负责写系统登录项（设置进程只改 UserDefaults 并通知）。
    private func applyLaunchAtLoginIfNeeded() {
        guard managesLaunchAtLogin, !AppMode.isSettingsHelper else { return }
        guard lastAppliedLaunchAtLogin != launchAtLogin else { return }
        lastAppliedLaunchAtLogin = launchAtLogin
        applyLaunchAtLogin()
    }

    // MARK: - Queries

    /// Finds the rule matching the given bundle identifier.
    public func rule(for bundleID: String) -> AppRule? {
        rules.first { $0.bundleIdentifier == bundleID }
    }

    /// Returns currently running regular apps (suitable for the picker).
    public func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// Default seed rules for common apps.
    nonisolated public static func defaultRules() -> [AppRule] {
        let abc = "com.apple.keylayout.ABC"
        let pinyin = "com.apple.inputmethod.SCIM.ITABC"
        return [
            // Dev tools → English
            AppRule(bundleIdentifier: "com.apple.Terminal",
                    appName: "Terminal",
                    inputSourceID: abc,
                    inputSourceName: "ABC"),
            AppRule(bundleIdentifier: "com.googlecode.iterm2",
                    appName: "iTerm2",
                    inputSourceID: abc,
                    inputSourceName: "ABC"),
            AppRule(bundleIdentifier: "com.microsoft.VSCode",
                    appName: "VS Code",
                    inputSourceID: abc,
                    inputSourceName: "ABC"),
            AppRule(bundleIdentifier: "com.apple.dt.Xcode",
                    appName: "Xcode",
                    inputSourceID: abc,
                    inputSourceName: "ABC"),
            AppRule(bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    appName: "Warp",
                    inputSourceID: abc,
                    inputSourceName: "ABC"),
            // Communication apps → Chinese
            AppRule(bundleIdentifier: "com.tencent.xinWeChat",
                    appName: "WeChat",
                    inputSourceID: pinyin,
                    inputSourceName: "Pinyin – Simplified"),
        ]
    }
}
