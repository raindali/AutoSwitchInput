import AppKit
import Foundation
import ServiceManagement

public extension Notification.Name {
    /// 规则变更的跨进程通知（菜单栏进程 ⇄ 设置窗口进程）。
    static let autoSwitchRulesDidChange = Notification.Name("com.qingwei.inputswitch.rulesDidChange")
}

/// 未命中规则时，切换回应用要如何处理输入源。
public enum RestoreStrategy: String, Codable, Sendable {
    /// 总是切换到默认输入法。
    case alwaysDefault
    /// 恢复该 App 上次使用的输入法；没有记录时用默认输入法。
    case restoreLast
}

/// 持久化的全部设置。整体作为一个 `Codable` 快照存取，
/// 避免「保存」和「重新读取」维护两份手写字段列表而悄悄漂移。
struct PersistedSettings: Codable, Equatable {
    var autoSwitchEnabled: Bool
    var rules: [AppRule]
    var defaultInputSourceID: String?
    var restoreStrategy: RestoreStrategy
    var launchAtLogin: Bool

    init(
        autoSwitchEnabled: Bool,
        rules: [AppRule],
        defaultInputSourceID: String?,
        restoreStrategy: RestoreStrategy,
        launchAtLogin: Bool
    ) {
        self.autoSwitchEnabled = autoSwitchEnabled
        self.rules = rules
        self.defaultInputSourceID = defaultInputSourceID
        self.restoreStrategy = restoreStrategy
        self.launchAtLogin = launchAtLogin
    }

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
    /// 未命中规则时，切换回应用要如何处理输入源。
    @Published public var restoreStrategy: RestoreStrategy {
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

    /// 由菜单栏进程注入：返回某个 App 上次使用的输入源（调用方负责校验仍可用）。
    /// 只有菜单栏进程维护这张表，设置进程不需要。
    public var rememberedInputSource: ((String) -> String?)?

    private enum Keys {
        static let snapshot = "settingsSnapshot"
        static let legacyRules = "appRules"
        static let legacyEnabled = "autoSwitchEnabled"
        static let legacyDefault = "defaultInputSourceID"
        static let legacyLaunch = "launchAtLogin"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    private let defaults: UserDefaults
    /// 是否与另一个进程互发变更通知（单元测试里关掉，避免相互干扰）。
    private let syncsAcrossProcesses: Bool
    /// 是否由本进程写系统登录项（单元测试里关掉，避免真的注册登录项）。
    private let managesLaunchAtLogin: Bool

    /// 正在应用来自另一个进程的变更：此时属性赋值不应再触发保存/回发通知。
    private var isApplyingRemoteChange = false
    /// 1.0 的旧 key 只需清理一次。
    private var legacyKeysCleaned = false
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
        managesLaunchAtLogin: Bool = !AppMode.isSettingsHelper
    ) {
        self.defaults = defaults
        self.syncsAcrossProcesses = syncsAcrossProcesses
        self.managesLaunchAtLogin = managesLaunchAtLogin

        let loaded = Self.load(from: defaults)
        autoSwitchEnabled = loaded.autoSwitchEnabled
        defaultInputSourceID = loaded.defaultInputSourceID
        restoreStrategy = loaded.restoreStrategy
        launchAtLogin = loaded.launchAtLogin
        rules = loaded.rules

        if defaults.data(forKey: Keys.snapshot) == nil {
            if rules.isEmpty {
                let seed = Self.seedSources()
                rules = RuleStore.defaultRules(english: seed.english, chinese: seed.chinese)
            }
            if Self.hasNoLegacySettings(defaults) {
                restoreStrategy = .restoreLast
            }
            save()
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

    func acceptsRemoteChange(fromPID pid: Int) -> Bool {
        pid != Int(ProcessInfo.processInfo.processIdentifier)
    }

    // MARK: - Persistence

    private func currentSnapshot() -> PersistedSettings {
        PersistedSettings(
            autoSwitchEnabled: autoSwitchEnabled,
            rules: rules,
            defaultInputSourceID: defaultInputSourceID,
            restoreStrategy: restoreStrategy,
            launchAtLogin: launchAtLogin
        )
    }

    private func save() {
        guard !isApplyingRemoteChange else { return }
        guard let data = try? JSONEncoder().encode(currentSnapshot()) else { return }
        defaults.set(data, forKey: Keys.snapshot)
        if !legacyKeysCleaned {
            Self.removeLegacyKeys(from: defaults)
            legacyKeysCleaned = true
        }

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
        apply(Self.load(from: defaults))
    }

    private func apply(_ snapshot: PersistedSettings) {
        let changed = snapshot != currentSnapshot()
        isApplyingRemoteChange = true
        if autoSwitchEnabled != snapshot.autoSwitchEnabled { autoSwitchEnabled = snapshot.autoSwitchEnabled }
        if rules != snapshot.rules { rules = snapshot.rules }
        if defaultInputSourceID != snapshot.defaultInputSourceID { defaultInputSourceID = snapshot.defaultInputSourceID }
        if restoreStrategy != snapshot.restoreStrategy { restoreStrategy = snapshot.restoreStrategy }
        if launchAtLogin != snapshot.launchAtLogin { launchAtLogin = snapshot.launchAtLogin }
        isApplyingRemoteChange = false

        guard changed else { return }
        applyLaunchAtLoginIfNeeded()
        onRemoteChange?()
    }

    // MARK: - Snapshot IO

    static func load(from defaults: UserDefaults) -> PersistedSettings {
        if let data = defaults.data(forKey: Keys.snapshot) {
            if let snapshot = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
                return snapshot
            }
            // 无法解码的数据留着只会让每次启动都读到空设置
            defaults.removeObject(forKey: Keys.snapshot)
        }
        // 1.0 的散装 key
        return PersistedSettings(
            autoSwitchEnabled: defaults.object(forKey: Keys.legacyEnabled) as? Bool ?? true,
            rules: defaults.data(forKey: Keys.legacyRules)
                .flatMap { try? JSONDecoder().decode([AppRule].self, from: $0) } ?? [],
            defaultInputSourceID: defaults.string(forKey: Keys.legacyDefault),
            restoreStrategy: .alwaysDefault,
            launchAtLogin: defaults.bool(forKey: Keys.legacyLaunch)
        )
    }

    private static func hasNoLegacySettings(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: Keys.hasLaunchedBefore) == false
            && defaults.object(forKey: Keys.legacyRules) == nil
            && defaults.object(forKey: Keys.legacyEnabled) == nil
    }

    private static func removeLegacyKeys(from defaults: UserDefaults) {
        defaults.removeObject(forKey: Keys.legacyRules)
        defaults.removeObject(forKey: Keys.legacyEnabled)
        defaults.removeObject(forKey: Keys.legacyDefault)
        defaults.removeObject(forKey: Keys.legacyLaunch)
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

    private func applyLaunchAtLoginIfNeeded() {
        guard managesLaunchAtLogin else { return }
        guard lastAppliedLaunchAtLogin != launchAtLogin else { return }
        lastAppliedLaunchAtLogin = launchAtLogin
        applyLaunchAtLogin()
    }

    // MARK: - Queries

    /// Finds the rule matching the given bundle identifier.
    public func rule(for bundleID: String) -> AppRule? {
        rules.first { $0.bundleIdentifier == bundleID }
    }

    /// 该前台 App 应该切到哪个输入源：规则命中优先；否则按「跟随上次」或默认输入源。
    /// 总开关关闭、没有记录或没有默认值时返回 nil（不切换）。
    public func targetInputSourceID(for bundleID: String) -> String? {
        guard autoSwitchEnabled else { return nil }
        if let rule = rule(for: bundleID) { return rule.inputSourceID }
        switch restoreStrategy {
        case .alwaysDefault:
            return defaultInputSourceID
        case .restoreLast:
            return rememberedInputSource?(bundleID) ?? defaultInputSourceID
        }
    }

    /// Returns currently running regular apps (suitable for the picker).
    public func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// 首次播种用的英文 / 中文输入源：从当前已启用的列表里挑，
    /// 避免写死用户没有启用（`TISSelectInputSource` 会返回 -50）的 ID。
    private static func seedSources() -> (
        english: (id: String, name: String),
        chinese: (id: String, name: String)
    ) {
        let sources = InputMethodManager.shared.getAllInputSources()
        let layouts = sources.filter { $0.id.hasPrefix("com.apple.keylayout.") }
        let inputMethods = sources.filter { !$0.id.hasPrefix("com.apple.keylayout.") }

        let english = layouts.first { $0.id == "com.apple.keylayout.ABC" }
            ?? layouts.first { $0.id == "com.apple.keylayout.US" }
            ?? layouts.first
        let chinese = inputMethods.first { $0.id == "com.apple.inputmethod.SCIM.ITABC" }
            ?? inputMethods.first

        return (
            english.map { ($0.id, $0.name) } ?? ("com.apple.keylayout.ABC", "ABC"),
            chinese.map { ($0.id, $0.name) } ?? ("com.apple.inputmethod.SCIM.ITABC", "Pinyin – Simplified")
        )
    }

    /// Default seed rules for common apps.
    nonisolated public static func defaultRules(
        english: (id: String, name: String) = ("com.apple.keylayout.ABC", "ABC"),
        chinese: (id: String, name: String) = ("com.apple.inputmethod.SCIM.ITABC", "Pinyin – Simplified")
    ) -> [AppRule] {
        return [
            // Dev tools → English
            AppRule(bundleIdentifier: "com.apple.Terminal",
                    appName: "Terminal",
                    inputSourceID: english.id,
                    inputSourceName: english.name),
            AppRule(bundleIdentifier: "com.googlecode.iterm2",
                    appName: "iTerm2",
                    inputSourceID: english.id,
                    inputSourceName: english.name),
            AppRule(bundleIdentifier: "com.microsoft.VSCode",
                    appName: "VS Code",
                    inputSourceID: english.id,
                    inputSourceName: english.name),
            AppRule(bundleIdentifier: "com.apple.dt.Xcode",
                    appName: "Xcode",
                    inputSourceID: english.id,
                    inputSourceName: english.name),
            AppRule(bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    appName: "Warp",
                    inputSourceID: english.id,
                    inputSourceName: english.name),
            // Communication apps → Chinese
            AppRule(bundleIdentifier: "com.tencent.xinWeChat",
                    appName: "WeChat",
                    inputSourceID: chinese.id,
                    inputSourceName: chinese.name),
        ]
    }
}
