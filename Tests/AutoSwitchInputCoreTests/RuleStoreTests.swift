import XCTest
@testable import AutoSwitchInputCore

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

    /// 模拟另一个进程写入完整快照。
    private func writeSnapshot(_ snapshot: PersistedSettings) {
        defaults.set(try! JSONEncoder().encode(snapshot), forKey: "settingsSnapshot")
    }

    // MARK: - 首次启动

    func testFirstLaunchSeedsDefaultRules() {
        let store = makeStore()
        XCTAssertEqual(store.rules.count, RuleStore.defaultRules().count)
        XCTAssertEqual(store.rules.map(\.bundleIdentifier), RuleStore.defaultRules().map(\.bundleIdentifier))
    }

    /// 回归：默认规则必须落盘。否则用户一次都不改设置，下次启动读不到 appRules 就全丢了。
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

    /// 损坏的数据不应该让 App 崩溃：解不出来就退回默认规则，并重新落盘。
    func testCorruptedRulesDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "appRules")
        defaults.set(true, forKey: "hasLaunchedBefore")

        let store = makeStore()
        // AppRule.id 是随机 UUID，比较业务字段而不是整条记录
        XCTAssertEqual(store.rules.map(\.bundleIdentifier), RuleStore.defaultRules().map(\.bundleIdentifier))
        XCTAssertNotNil(defaults.data(forKey: "settingsSnapshot"))
    }

    // MARK: - 跨进程同步

    /// 模拟另一个进程写入 UserDefaults 后，本进程重新读取。
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

    /// reload 不应该反过来触发保存（否则两个进程会互相通知形成回环）。
    func testReloadDoesNotWriteBack() {
        let store = makeStore()
        store.rules = [
            AppRule(bundleIdentifier: "com.local", appName: "Local", inputSourceID: "id", inputSourceName: "n")
        ]

        // 另一个进程写入后本进程 reload
        let external = AppRule(
            bundleIdentifier: "com.external",
            appName: "External",
            inputSourceID: "id2",
            inputSourceName: "n2"
        )
        let snapshot = PersistedSettings(
            autoSwitchEnabled: true,
            rules: [external],
            defaultInputSourceID: nil,
            launchAtLogin: false
        )
        writeSnapshot(snapshot)
        store.reloadFromDefaults()
        XCTAssertEqual(store.rules, [external])

        // reload 后再读一次 defaults，内容应仍是外部写入的那份（没有被回写成别的）
        let data = defaults.data(forKey: "settingsSnapshot")!
        XCTAssertEqual(try JSONDecoder().decode(PersistedSettings.self, from: data), snapshot)
    }

    // MARK: - 跨进程同步（快照直传）

    /// 通知里携带的快照应被直接应用，不依赖再次读盘（规避 cfprefsd 与通知的时序问题）。
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
        // 故意不写 defaults：应用快照不应依赖磁盘内容
        store.applyRemoteSnapshot(try! JSONEncoder().encode(snapshot))

        XCTAssertFalse(store.autoSwitchEnabled)
        XCTAssertEqual(store.rules, [external])
        XCTAssertEqual(store.defaultInputSourceID, "com.apple.keylayout.US")
    }

    /// 自己发出的通知必须被忽略，否则两个属性赋值会来回触发。
    func testIgnoresNotificationsFromSelf() {
        let store = makeStore()
        let own = Int(ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(store.acceptsRemoteChange(fromPID: own))
        XCTAssertTrue(store.acceptsRemoteChange(fromPID: own &+ 1))
    }

    /// 远端变更应用后要通知调用方重放当前 App（否则改完规则要切走再切回）。
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

    /// 1.0 的四个散装 key 应被读进来，并在下次保存时收成快照。
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
        // 保存后旧 key 被清理
        XCTAssertNil(defaults.data(forKey: "appRules"))
        XCTAssertNotNil(defaults.data(forKey: "settingsSnapshot"))
    }

    /// 回归：1.0 升级上来的用户（hasLaunchedBefore=true、从未落盘规则）也要拿到默认规则。
    func testSeedsRulesForUpgradedUserWhoNeverPersistedThem() {
        defaults.set(true, forKey: "hasLaunchedBefore")
        let store = makeStore()
        XCTAssertEqual(store.rules.count, RuleStore.defaultRules().count)
    }

    /// 用户主动删空规则（留下非 nil 的空数组）不应被重新播种。
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
