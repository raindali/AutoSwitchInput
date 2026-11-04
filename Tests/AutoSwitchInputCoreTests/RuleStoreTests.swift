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
final class RuleStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AutoSwitchInputTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

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

    func testCorruptedRulesDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "appRules")

        let store = makeStore()
        XCTAssertEqual(store.rules.map(\.bundleIdentifier), RuleStore.defaultRules().map(\.bundleIdentifier))
        XCTAssertNotNil(defaults.data(forKey: "settingsSnapshot"))
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
                PersistedSettings(autoSwitchEnabled: false, rules: [], defaultInputSourceID: nil, launchAtLogin: false)
            )
        )
        XCTAssertEqual(called, 1)
    }

    // MARK: - 输入源决策

    func testTargetInputSourcePrefersRuleThenDefault() {
        let store = makeStore()
        store.autoSwitchEnabled = true
        store.defaultInputSourceID = "default.id"
        store.rules = [
            AppRule(bundleIdentifier: "com.a", appName: "A", inputSourceID: "rule.id", inputSourceName: "R")
        ]

        XCTAssertEqual(store.targetInputSourceID(for: "com.a"), "rule.id")
        XCTAssertEqual(store.targetInputSourceID(for: "com.unknown"), "default.id")

        store.autoSwitchEnabled = false
        XCTAssertNil(store.targetInputSourceID(for: "com.a"), "总开关关闭时不应切换")
    }

    func testTargetInputSourceIsNilWithoutRuleOrDefault() {
        let store = makeStore()
        store.rules = []
        store.defaultInputSourceID = nil
        XCTAssertNil(store.targetInputSourceID(for: "com.a"))
    }

    // MARK: - 迁移与播种

    func testLegacyKeysMigrateIntoSnapshot() {
        defaults.set(false, forKey: "autoSwitchEnabled")
        defaults.set("com.apple.keylayout.US", forKey: "defaultInputSourceID")
        let legacyRule = AppRule(
            bundleIdentifier: "com.legacy", appName: "Legacy", inputSourceID: "id", inputSourceName: "n"
        )
        defaults.set(try! JSONEncoder().encode([legacyRule]), forKey: "appRules")

        let store = makeStore()
        XCTAssertFalse(store.autoSwitchEnabled)
        XCTAssertEqual(store.rules, [legacyRule])
        XCTAssertEqual(store.defaultInputSourceID, "com.apple.keylayout.US")
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

    func testDefaultRulesCoverCommonEditors() {
        let ids = Set(RuleStore.defaultRules().map(\.bundleIdentifier))
        XCTAssertTrue(ids.contains("com.apple.Terminal"))
        XCTAssertTrue(ids.contains("com.microsoft.VSCode"))
        XCTAssertTrue(ids.contains("com.tencent.xinWeChat"))
    }
}
