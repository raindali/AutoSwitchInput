import AppKit

/// Monitors frontmost app changes via NSWorkspace notifications.
class AppMonitor {
    static let shared = AppMonitor()

    /// Called with (bundleIdentifier, appName) when the frontmost app changes.
    var onAppChange: ((String, String) -> Void)?

    private(set) var currentBundleID: String?
    private(set) var currentAppName: String?
    private var observer: NSObjectProtocol?
    private var pendingChange: DispatchWorkItem?

    func start() {
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
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }

            let bundleID = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""

            // Only fire when the frontmost app actually changes.
            // 忽略自身（设置窗口是独立进程，同样使用本 App 的 bundle id）：
            // 打开设置时不应把「当前应用」变成 AutoSwitchInput 自己。
            guard bundleID != self.currentBundleID,
                  bundleID != Bundle.main.bundleIdentifier else { return }
            self.currentBundleID = bundleID
            self.currentAppName = name

            // Debounce: wait 80ms to skip rapid app switching.
            // 用一次性 DispatchWorkItem 代替 Timer：不注册 RunLoop 源，切换时也不额外分配对象。
            self.pendingChange?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingChange = nil
                self?.onAppChange?(bundleID, name)
            }
            self.pendingChange = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        pendingChange?.cancel()
        pendingChange = nil
    }
}
