import XCTest
@testable import AutoSwitchInputCore

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

    /// 损坏的 appRules 数据不应该让 App 崩溃，退化成空规则。
    func testCorruptedRulesDataFallsBackToEmpty() {
        defaults.set(Data("not json".utf8), forKey: "appRules")
        defaults.set(true, forKey: "hasLaunchedBefore")

        XCTAssertTrue(makeStore().rules.isEmpty)
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
        defaults.set(false, forKey: "autoSwitchEnabled")
        defaults.set("com.apple.keylayout.US", forKey: "defaultInputSourceID")
        defaults.set(try! JSONEncoder().encode([external]), forKey: "appRules")

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
        defaults.set(try! JSONEncoder().encode([external]), forKey: "appRules")
        store.reloadFromDefaults()
        XCTAssertEqual(store.rules, [external])

        // reload 后再读一次 defaults，内容应仍是外部写入的那份（没有被回写成别的）
        let data = defaults.data(forKey: "appRules")!
        XCTAssertEqual(try JSONDecoder().decode([AppRule].self, from: data), [external])
    }

    // MARK: - 默认规则内容

    func testDefaultRulesCoverCommonEditors() {
        let ids = Set(RuleStore.defaultRules().map(\.bundleIdentifier))
        XCTAssertTrue(ids.contains("com.apple.Terminal"))
        XCTAssertTrue(ids.contains("com.microsoft.VSCode"))
        XCTAssertTrue(ids.contains("com.tencent.xinWeChat"))
    }
}
