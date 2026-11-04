import AppKit

/// Monitors frontmost app changes via NSWorkspace notifications.
@MainActor
public final class AppMonitor {
    public static let shared = AppMonitor()

    /// Called with (bundleIdentifier, appName) when the frontmost app changes.
    public var onAppChange: ((String, String) -> Void)?

    public private(set) var currentBundleID: String?
    public private(set) var currentAppName: String?

    private let debounce: TimeInterval
    private let ownBundleID: String?
    private var observer: NSObjectProtocol?
    private var pendingChange: DispatchWorkItem?

    /// - Parameters:
    ///   - debounce: 防抖时长，默认 80ms（测试可缩短）。
    ///   - ownBundleID: 自身 bundle id；本 App 的激活事件（含设置进程）会被忽略。
    public init(debounce: TimeInterval = 0.08, ownBundleID: String? = Bundle.main.bundleIdentifier) {
        self.debounce = debounce
        self.ownBundleID = ownBundleID
    }

    public func start() {
        // Capture the app that was active at launch
        if let app = NSWorkspace.shared.frontmostApplication {
            currentBundleID = app.bundleIdentifier
            currentAppName = app.localizedName
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            // 通知队列固定为 .main，这里可以直接断言主 actor 隔离。
            MainActor.assumeIsolated {
                self.handleActivation(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "")
            }
        }
    }

    public func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        pendingChange?.cancel()
        pendingChange = nil
    }

    func handleActivation(bundleID: String, name: String) {
        guard bundleID != currentBundleID, bundleID != ownBundleID else { return }
        currentBundleID = bundleID
        currentAppName = name
        Log.monitor.debug("前台应用切换: \(bundleID, privacy: .public)")

        // Debounce: wait a beat to skip rapid app switching.
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingChange = nil
            self?.onAppChange?(bundleID, name)
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
