import XCTest
@testable import AutoSwitchInputCore

final class AppMonitorTests: XCTestCase {

    private let ownBundleID = "com.example.self"

    /// 让主队列跑一段时间，用于确认「没有额外回调」。
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 1)
    }

    func testFiresOnceWithLatestBundleAfterDebounce() {
        let monitor = AppMonitor(debounce: 0.05, ownBundleID: ownBundleID)
        var received: [(String, String)] = []
        monitor.onAppChange = { bundleID, name in
            received.append((bundleID, name))
        }

        // 快速连切三个 App：防抖只应保留最后一个
        monitor.handleActivation(bundleID: "com.a", name: "A")
        monitor.handleActivation(bundleID: "com.b", name: "B")
        monitor.handleActivation(bundleID: "com.c", name: "C")

        settle(0.3)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, "com.c")
        XCTAssertEqual(received.first?.1, "C")
    }

    func testRepeatedActivationOfSameBundleFiresOnce() {
        let monitor = AppMonitor(debounce: 0.05, ownBundleID: ownBundleID)
        var count = 0
        monitor.onAppChange = { _, _ in count += 1 }

        monitor.handleActivation(bundleID: "com.a", name: "A")
        monitor.handleActivation(bundleID: "com.a", name: "A")

        settle(0.25)

        XCTAssertEqual(count, 1)
    }

    /// 设置窗口是独立进程但同 bundle id，打开设置不应把「当前应用」变成自己。
    func testIgnoresOwnBundleIdentifier() {
        let monitor = AppMonitor(debounce: 0.05, ownBundleID: ownBundleID)
        let notFired = expectation(description: "no callback")
        notFired.isInverted = true
        monitor.onAppChange = { _, _ in notFired.fulfill() }

        monitor.handleActivation(bundleID: ownBundleID, name: "AutoSwitchInput")

        wait(for: [notFired], timeout: 0.2)
        XCTAssertNil(monitor.currentBundleID)
    }

    func testTracksCurrentAppImmediately() {
        let monitor = AppMonitor(debounce: 0.05, ownBundleID: ownBundleID)
        monitor.onAppChange = { _, _ in }

        monitor.handleActivation(bundleID: "com.a", name: "A")
        XCTAssertEqual(monitor.currentBundleID, "com.a")
        XCTAssertEqual(monitor.currentAppName, "A")
    }

    func testStopCancelsPendingChange() {
        let monitor = AppMonitor(debounce: 0.2, ownBundleID: ownBundleID)
        let notFired = expectation(description: "no callback after stop")
        notFired.isInverted = true
        monitor.onAppChange = { _, _ in notFired.fulfill() }

        monitor.handleActivation(bundleID: "com.a", name: "A")
        monitor.stop()

        wait(for: [notFired], timeout: 0.4)
    }
}
