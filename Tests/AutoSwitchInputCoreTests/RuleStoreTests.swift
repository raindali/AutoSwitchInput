import XCTest
@testable import AutoSwitchInputCore

private final class CountingDefaults: UserDefaults {
    var setCount = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        setCount += 1
        super.set(value, forKey: defaultName)
    }
}

@MainActor
final class RuleStoreTests: UserDefaultsTestCase {
    private func makeStore() -> RuleStore {
        RuleStore(defaults: defaults, syncsAcrossProcesses: false, managesLaunchAtLogin: false)
    }

    private func writeSnapshot(_ snapshot: PersistedSettings) {
        defaults.set(try! JSONEncoder().encode(snapshot), forKey: "settingsSnapshot")
    }

    // MARK: - 首次启动

    func testFirstLaunchSeedsDefaultRules() {
        let store = makeStore()
        XCTAssertEqual(store.rules.count, RuleStore.defaultRules().count)
        XCTAssertEqual(store.rules.map(\.bundleIdentifier), RuleStore.defaultRules().map(\.bundleIdentifier))
    }

    func testSeededRulesSurviveRelaunch() {
        _ = makeStore()
        let relaunched = makeStore()
        XCTAssertEqual(relaunched.rules.count, RuleStore.defaultRules().count)
    }

    func testAutoSwitchDefaultsToOn() {
        XCTAssertTrue(makeStore().autoSwitchEnabled)
    }

    func testNoDefaultInputSourceInitially() {
        XCTAssertNil(makeStore().defaultInputSourceID)
    }

    // MARK: - 持久化

    func testChangesArePersisted() {
        let store = makeStore()
        store.autoSwitchEnabled = false
        store.defaultInputSourceID = "com.apple.keylayout.US"
        store.rules = [
            AppRule(
                bundleIdentifier: "com.example.app",
                appName: "Example",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "美国"
            )
        ]

        let reloaded = makeStore()
        XCTAssertFalse(reloaded.autoSwitchEnabled)
        XCTAssertEqual(reloaded.defaultInputSourceID, "com.apple.keylayout.US")
        XCTAssertEqual(reloaded.rules.count, 1)
        XCTAssertEqual(reloaded.rules.first?.bundleIdentifier, "com.example.app")
    }

    func testRuleLookupByBundleIdentifier() {
        let store = makeStore()
        store.rules = [
            AppRule(bundleIdentifier: "com.a", appName: "A", inputSourceID: "id.a", inputSourceName: "A"),
            AppRule(bundleIdentifier: "com.b", appName: "B", inputSourceID: "id.b", inputSourceName: "B"),
        ]

        XCTAssertEqual(store.rule(for: "com.b")?.inputSourceID, "id.b")
        XCTAssertNil(store.rule(for: "com.missing"))
    }

    func testCorruptedSnapshotFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "settingsSnapshot")

        let store = makeStore()
        XCTAssertEqual(store.rules.map(\.bundleIdentifier), RuleStore.defaultRules().map(\.bundleIdentifier))
        XCTAssertNotNil(
            try? JSONDecoder().decode(
                PersistedSettings.self,
                from: try XCTUnwrap(defaults.data(forKey: "settingsSnapshot"))
            )
        )
    }

    // MARK: - 跨进程同步

    func testReloadFromDefaultsPicksUpExternalChanges() {
        let store = makeStore()
        XCTAssertTrue(store.autoSwitchEnabled)

        let external = AppRule(
            bundleIdentifier: "com.external.app",
            appName: "External",
            inputSourceID: "com.apple.keylayout.ABC",
            inputSourceName: "ABC"
        )
        writeSnapshot(
            PersistedSettings(
                autoSwitchEnabled: false,
                rules: [external],
                defaultInputSourceID: "com.apple.keylayout.US",
                restoreStrategy: .alwaysDefault,
                launchAtLogin: false
            )
        )

        store.reloadFromDefaults()

        XCTAssertFalse(store.autoSwitchEnabled)
        XCTAssertEqual(store.defaultInputSourceID, "com.apple.keylayout.US")
        XCTAssertEqual(store.rules, [external])
    }

    func testReloadDoesNotWriteBack() {
        let counting = CountingDefaults(suiteName: suiteName)!
        let store = RuleStore(defaults: counting, syncsAcrossProcesses: false, managesLaunchAtLogin: false)
        counting.setCount = 0

        let external = AppRule(
            bundleIdentifier: "com.external",
            appName: "External",
            inputSourceID: "id2",
            inputSourceName: "n2"
        )
        writeSnapshot(
            PersistedSettings(
                autoSwitchEnabled: true,
                rules: [external],
                defaultInputSourceID: nil,
                restoreStrategy: .alwaysDefault,
                launchAtLogin: false
            )
        )
        store.reloadFromDefaults()

        XCTAssertEqual(store.rules, [external])
        XCTAssertEqual(counting.setCount, 0, "reload 不应触发保存，否则两个进程会互相通知形成回环")
    }

    // MARK: - 跨进程同步（快照直传）

    func testRemoteSnapshotAppliedWithoutReReadingDefaults() {
        let store = makeStore()
        let external = AppRule(
            bundleIdentifier: "com.external",
            appName: "External",
            inputSourceID: "com.apple.keylayout.US",
            inputSourceName: "美国"
        )
        let snapshot = PersistedSettings(
            autoSwitchEnabled: false,
            rules: [external],
            defaultInputSourceID: "com.apple.keylayout.US",
            restoreStrategy: .alwaysDefault,
            launchAtLogin: false
        )
        store.applyRemoteSnapshot(try! JSONEncoder().encode(snapshot))

        XCTAssertFalse(store.autoSwitchEnabled)
        XCTAssertEqual(store.rules, [external])
        XCTAssertEqual(store.defaultInputSourceID, "com.apple.keylayout.US")
    }

    func testIgnoresNotificationsFromSelf() {
        let store = makeStore()
        let own = Int(ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(store.acceptsRemoteChange(fromPID: own))
        XCTAssertTrue(store.acceptsRemoteChange(fromPID: own &+ 1))
    }

    func testRemoteChangeInvokesCallback() {
        let store = makeStore()
        var called = 0
        store.onRemoteChange = { called += 1 }
        store.applyRemoteSnapshot(
            try! JSONEncoder().encode(
                PersistedSettings(
                    autoSwitchEnabled: false,
                    rules: [],
                    defaultInputSourceID: nil,
                    restoreStrategy: .alwaysDefault,
                    launchAtLogin: false
                )
            )
        )
        XCTAssertEqual(called, 1)
    }

    // MARK: - 输入源决策

    func testTargetInputSourceDecision() {
        struct Case {
            let name: String
            let autoSwitch: Bool
            let strategy: RestoreStrategy
            let hasRule: Bool
            let remembered: String?
            let defaultID: String?
            let expected: String?
        }

        let cases: [Case] = [
            Case(name: "规则命中优先", autoSwitch: true, strategy: .restoreLast, hasRule: true,
                 remembered: "remembered.id", defaultID: "default.id", expected: "rule.id"),
            Case(name: "恢复上次命中", autoSwitch: true, strategy: .restoreLast, hasRule: false,
                 remembered: "remembered.id", defaultID: "default.id", expected: "remembered.id"),
            Case(name: "恢复上次无记录时回落默认值", autoSwitch: true, strategy: .restoreLast, hasRule: false,
                 remembered: nil, defaultID: "default.id", expected: "default.id"),
            Case(name: "恢复上次且没有默认值时不切换", autoSwitch: true, strategy: .restoreLast, hasRule: false,
                 remembered: nil, defaultID: nil, expected: nil),
            Case(name: "总是切到默认输入源", autoSwitch: true, strategy: .alwaysDefault, hasRule: false,
                 remembered: "remembered.id", defaultID: "default.id", expected: "default.id"),
            Case(name: "总是默认但没有默认值时不切换", autoSwitch: true, strategy: .alwaysDefault, hasRule: false,
                 remembered: "remembered.id", defaultID: nil, expected: nil),
            Case(name: "总开关关闭时不切换", autoSwitch: false, strategy: .restoreLast, hasRule: true,
                 remembered: "remembered.id", defaultID: "default.id", expected: nil),
        ]

        for c in cases {
            let store = makeStore()
            store.autoSwitchEnabled = c.autoSwitch
            store.restoreStrategy = c.strategy
            store.defaultInputSourceID = c.defaultID
            store.rules = c.hasRule
                ? [AppRule(bundleIdentifier: "com.a", appName: "A", inputSourceID: "rule.id", inputSourceName: "R")]
                : []
            store.rememberedInputSource = { _ in c.remembered }

            XCTAssertEqual(store.targetInputSourceID(for: "com.a"), c.expected, c.name)
        }
    }

    // MARK: - 输入法恢复策略

    func testFirstInstallDefaultsToRestoreLast() {
        XCTAssertEqual(makeStore().restoreStrategy, .restoreLast)
    }

    func testRestoreStrategyPersistsInSnapshot() {
        let store = makeStore()
        store.restoreStrategy = .alwaysDefault

        XCTAssertEqual(makeStore().restoreStrategy, .alwaysDefault)
    }

    func testLegacyUpgradeKeepsAlwaysDefault() {
        defaults.set(false, forKey: "autoSwitchEnabled")
        defaults.set(true, forKey: "hasLaunchedBefore")

        XCTAssertEqual(makeStore().restoreStrategy, .alwaysDefault)
    }

    func testSnapshotWithoutRestoreStrategyDefaultsToAlwaysDefault() throws {
        let json = #"{"autoSwitchEnabled":true,"rules":[],"defaultInputSourceID":null,"launchAtLogin":false}"#

        let snapshot = try JSONDecoder().decode(PersistedSettings.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.restoreStrategy, .alwaysDefault)
    }

    // MARK: - 迁移与播种

    func testLegacyKeysMigrateIntoSnapshot() {
        defaults.set(false, forKey: "autoSwitchEnabled")
        defaults.set("com.apple.keylayout.US", forKey: "defaultInputSourceID")
        defaults.set(true, forKey: "hasLaunchedBefore")
        let legacyRule = AppRule(
            bundleIdentifier: "com.legacy", appName: "Legacy", inputSourceID: "id", inputSourceName: "n"
        )
        defaults.set(try! JSONEncoder().encode([legacyRule]), forKey: "appRules")

        let store = makeStore()
        XCTAssertFalse(store.autoSwitchEnabled)
        XCTAssertEqual(store.rules, [legacyRule])
        XCTAssertEqual(store.defaultInputSourceID, "com.apple.keylayout.US")
        XCTAssertEqual(store.restoreStrategy, .alwaysDefault)
        XCTAssertNil(defaults.data(forKey: "appRules"))
        XCTAssertNotNil(defaults.data(forKey: "settingsSnapshot"))
    }

    func testSeedsRulesForUpgradedUserWhoNeverPersistedThem() {
        defaults.set(false, forKey: "autoSwitchEnabled")

        let store = makeStore()
        XCTAssertEqual(store.rules.count, RuleStore.defaultRules().count)
        XCTAssertFalse(store.autoSwitchEnabled)
    }

    func testDoesNotReseedAfterUserClearedRules() {
        let first = makeStore()
        first.rules = []
        XCTAssertNotNil(defaults.data(forKey: "settingsSnapshot"))

        let reopened = makeStore()
        XCTAssertTrue(reopened.rules.isEmpty)
    }

    // MARK: - 默认规则内容

    func testDefaultRulesUseProvidedInputSources() {
        let rules = RuleStore.defaultRules(
            english: (id: "en.layout", name: "EN"),
            chinese: (id: "zh.ime", name: "ZH")
        )

        let devTools = rules.filter { $0.bundleIdentifier != "com.tencent.xinWeChat" }
        XCTAssertFalse(devTools.isEmpty)
        XCTAssertTrue(devTools.allSatisfy { $0.inputSourceID == "en.layout" && $0.inputSourceName == "EN" })

        let weChat = rules.first { $0.bundleIdentifier == "com.tencent.xinWeChat" }
        XCTAssertEqual(weChat?.inputSourceID, "zh.ime")
        XCTAssertEqual(weChat?.inputSourceName, "ZH")
    }

    /// 首次播种不能写死用户没启用的输入源（否则 TISSelectInputSource 返回 -50）。
    func testSeededRulesUseEnabledInputSources() throws {
        let enabled = Set(InputMethodManager.shared.getAllInputSources().map(\.id))
        let hasLayout = enabled.contains { $0.hasPrefix("com.apple.keylayout.") }
        let hasInputMethod = enabled.contains { !$0.hasPrefix("com.apple.keylayout.") }
        try XCTSkipUnless(hasLayout && hasInputMethod, "环境里没有同时启用英文布局与中文输入法")

        let store = makeStore()
        for rule in store.rules {
            XCTAssertTrue(
                enabled.contains(rule.inputSourceID),
                "\(rule.bundleIdentifier) 指向未启用的 \(rule.inputSourceID)"
            )
        }
    }

    func testDefaultRulesCoverCommonEditors() {
        let ids = Set(RuleStore.defaultRules().map(\.bundleIdentifier))
        XCTAssertTrue(ids.contains("com.apple.Terminal"))
        XCTAssertTrue(ids.contains("com.microsoft.VSCode"))
        XCTAssertTrue(ids.contains("com.tencent.xinWeChat"))
    }
}
