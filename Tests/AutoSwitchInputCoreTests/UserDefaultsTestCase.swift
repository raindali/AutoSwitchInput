import XCTest

/// 每个测试用独立的 UserDefaults suite，避免测试之间互相污染。
class UserDefaultsTestCase: XCTestCase {
    private(set) var suiteName = ""
    private(set) var defaults: UserDefaults!

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
}
