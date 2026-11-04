import AppKit
import Foundation
import ServiceManagement

public extension Notification.Name {
    /// 规则变更的跨进程通知（菜单栏进程 ⇄ 设置窗口进程）。
    static let autoSwitchRulesDidChange = Notification.Name("com.qingwei.inputswitch.rulesDidChange")
}

/// 持久化的全部设置。整体作为一个 `Codable` 快照存取，
/// 避免「保存」和「重新读取」维护两份手写字段列表而悄悄漂移。
struct PersistedSettings: Codable, Equatable {
    var autoSwitchEnabled: Bool
    var rules: [AppRule]
    var defaultInputSourceID: String?
    var launchAtLogin: Bool
}

/// Observable store for app rules and settings, persisted to UserDefaults.
///
/// 设置窗口运行在独立进程里，因此写入 UserDefaults 后需要通知另一个进程。
/// 通知里直接携带新快照（`userInfo["settings"]`），接收方不再二次读盘 ——
/// 两条 XPC 通道（cfprefsd 与通知）没有顺序保证，重读可能拿到旧值。
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

    /// 另一个进程写入变更并已被本进程应用后调用。
    /// 菜单栏进程用它把当前前台 App 的规则重放一遍（否则改完规则要切走再切回来才生效）。
    public var onRemoteChange: (() -> Void)?

    private let defaults: UserDefaults
    /// 是否与另一个进程互发变更通知（单元测试里关掉，避免相互干扰）。
    private let syncsAcrossProcesses: Bool
    /// 是否由本进程写系统登录项（单元测试里关掉，避免真的注册登录项）。
    private let managesLaunchAtLogin: Bool

    /// 新格式：全部设置放在一个 key 下。
    private let settingsKey = "settingsSnapshot"
    /// 1.0 的旧 key，仅用于一次性迁移。
    private let legacyRulesKey = "appRules"
    private let legacyEnabledKey = "autoSwitchEnabled"
    private let legacyDefaultKey = "defaultInputSourceID"
    private let legacyLaunchKey = "launchAtLogin"
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

        let loaded = Self.load(from: defaults, settingsKey: settingsKey)
        autoSwitchEnabled = loaded.autoSwitchEnabled
        defaultInputSourceID = loaded.defaultInputSourceID
        launchAtLogin = loaded.launchAtLogin
        rules = loaded.rules

        // 没有快照时统一处理两件事：
        //   1. 首次启动 / 1.0 从未落盘过规则（升级）→ 补默认规则；
        //   2. 从 1.0 的散装 key 迁移到新快照，并清掉旧 key。
        if defaults.data(forKey: settingsKey) == nil {
            if rules.isEmpty {
                rules = RuleStore.defaultRules()
            }
            defaults.set(true, forKey: firstLaunchKey)
            save()
        } else if !defaults.bool(forKey: firstLaunchKey) {
            defaults.set(true, forKey: firstLaunchKey)
        }

        if syncsAcrossProcesses {
            remoteObserver = DistributedNotificationCenter.default().addObserver(
                forName: .autoSwitchRulesDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // 先把通知里的值取成 Sendable 的局部量，再进主 actor。
                let pid = notification.userInfo?["pid"] as? Int
                let snapshot = notification.userInfo?["settings"] as? Data
                // 通知队列固定为 .main，这里可以直接断言主 actor 隔离。
                MainActor.assumeIsolated {
                    guard let self, let pid, self.acceptsRemoteChange(fromPID: pid) else { return }
                    Log.rules.debug("收到跨进程规则变更")
                    if let snapshot {
                        self.applyRemoteSnapshot(snapshot)
                    } else {
                        self.reloadFromDefaults()
                    }
                }
            }
        }
    }

    /// 忽略自己发出的通知（否则会回环）。
    func acceptsRemoteChange(fromPID pid: Int) -> Bool {
        pid != Int(ProcessInfo.processInfo.processIdentifier)
    }

    // MARK: - Persistence

    private func currentSnapshot() -> PersistedSettings {
        PersistedSettings(
            autoSwitchEnabled: autoSwitchEnabled,
            rules: rules,
            defaultInputSourceID: defaultInputSourceID,
            launchAtLogin: launchAtLogin
        )
    }

    private func save() {
        guard !isApplyingRemoteChange else { return }
        guard let data = try? JSONEncoder().encode(currentSnapshot()) else { return }
        defaults.set(data, forKey: settingsKey)
        Self.removeLegacyKeys(from: defaults)

        guard syncsAcrossProcesses else { return }
        DistributedNotificationCenter.default().postNotificationName(
            .autoSwitchRulesDidChange,
            object: nil,
            userInfo: [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                // 直接把新快照带过去：接收方不必再读 UserDefaults，规避两条 XPC 通道的时序问题。
                "settings": data,
            ],
            deliverImmediately: true
        )
    }

    /// 应用另一个进程推来的快照（不触发保存，避免通知回环）。
    func applyRemoteSnapshot(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(PersistedSettings.self, from: data) else {
            Log.rules.error("跨进程快照解码失败，改为重新读取")
            reloadFromDefaults()
            return
        }
        apply(snapshot)
    }

    /// 从 UserDefaults 重新读取（用于通知未携带快照的旧版本，以及测试）。
    func reloadFromDefaults() {
        apply(Self.load(from: defaults, settingsKey: settingsKey))
    }

    private func apply(_ snapshot: PersistedSettings) {
        let changed = snapshot != currentSnapshot()
        isApplyingRemoteChange = true
        autoSwitchEnabled = snapshot.autoSwitchEnabled
        rules = snapshot.rules
        defaultInputSourceID = snapshot.defaultInputSourceID
        launchAtLogin = snapshot.launchAtLogin
        isApplyingRemoteChange = false

        guard changed else { return }
        applyLaunchAtLoginIfNeeded()
        onRemoteChange?()
    }

    // MARK: - Snapshot IO

    static func load(from defaults: UserDefaults, settingsKey: String) -> PersistedSettings {
        if let data = defaults.data(forKey: settingsKey),
           let snapshot = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            return snapshot
        }
        // 1.0 的四个散装 key
        return PersistedSettings(
            autoSwitchEnabled: defaults.object(forKey: "autoSwitchEnabled") as? Bool ?? true,
            rules: defaults.data(forKey: "appRules")
                .flatMap { try? JSONDecoder().decode([AppRule].self, from: $0) } ?? [],
            defaultInputSourceID: defaults.string(forKey: "defaultInputSourceID"),
            launchAtLogin: defaults.bool(forKey: "launchAtLogin")
        )
    }

    private static func removeLegacyKeys(from defaults: UserDefaults) {
        defaults.removeObject(forKey: "appRules")
        defaults.removeObject(forKey: "autoSwitchEnabled")
        defaults.removeObject(forKey: "defaultInputSourceID")
        defaults.removeObject(forKey: "launchAtLogin")
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

    /// 该前台 App 应该切到哪个输入源：规则命中优先，否则默认输入源；
    /// 总开关关闭或两者都没有时返回 nil（不切换）。
    public func targetInputSourceID(for bundleID: String) -> String? {
        guard autoSwitchEnabled else { return nil }
        return rule(for: bundleID)?.inputSourceID ?? defaultInputSourceID
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
