import XCTest
@testable import AutoSwitchInputCore

final class RecentInputSourceStoreTests: UserDefaultsTestCase {
    func testRemembersPerApp() {
        let store = RecentInputSourceStore(defaults: defaults)
        store.remember("com.apple.keylayout.US", for: "com.apple.Terminal")
        store.remember("com.apple.inputmethod.SCIM.ITABC", for: "com.tencent.xinWeChat")

        XCTAssertEqual(store.source(for: "com.apple.Terminal"), "com.apple.keylayout.US")
        XCTAssertEqual(store.source(for: "com.tencent.xinWeChat"), "com.apple.inputmethod.SCIM.ITABC")
        XCTAssertNil(store.source(for: "com.example.none"))
    }

    func testRememberUpdatesExistingEntry() {
        let store = RecentInputSourceStore(defaults: defaults, limit: 3)
        store.remember("B", for: "app.2")
        store.remember("C", for: "app.3")
        store.remember("A", for: "app.1")
        store.remember("D", for: "app.1")

        XCTAssertEqual(store.source(for: "app.2"), "B", "重复条目不应挤掉其他 App")
        XCTAssertEqual(store.source(for: "app.1"), "D")
    }

    func testEvictsLeastRecentBeyondLimit() {
        let store = RecentInputSourceStore(defaults: defaults, limit: 3)
        store.remember("A", for: "app.1")
        store.remember("B", for: "app.2")
        store.remember("C", for: "app.3")
        store.remember("D", for: "app.4")

        XCTAssertNil(store.source(for: "app.1"))
        XCTAssertEqual(store.source(for: "app.4"), "D")
    }

    func testSurvivesRelaunch() {
        RecentInputSourceStore(defaults: defaults).remember("US", for: "com.app")

        XCTAssertEqual(RecentInputSourceStore(defaults: defaults).source(for: "com.app"), "US")
    }

    func testCorruptedDataFallsBackToEmpty() {
        defaults.set(Data("not json".utf8), forKey: RecentInputSourceStore.defaultsKey)

        XCTAssertNil(RecentInputSourceStore(defaults: defaults).source(for: "com.app"))
    }
}
