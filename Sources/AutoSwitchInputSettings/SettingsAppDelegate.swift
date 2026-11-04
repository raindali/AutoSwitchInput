import AppKit
import SwiftUI
import AutoSwitchInputCore
import AutoSwitchInputUI

/// 设置窗口进程的 delegate（由菜单栏进程以 `--settings` 参数拉起）。
///
/// 独立进程的意义：SwiftUI 的 AttributeGraph / DisplayList、图标与文字渲染缓存、
/// 窗口后备存储全部只存在于这个短命进程里。窗口一关进程即退出，常驻的菜单栏进程
/// 始终保持在 ~12 MB，不会再因为「开过一次设置」而长期多占 ~20 MB。
@MainActor
final class SettingsAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private var keyMonitor: Any?
    /// 监听菜单栏进程（父进程）退出，父进程没了就跟着退出，避免留下孤儿窗口。
    private var parentSource: DispatchSourceProcess?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.settings.debug("设置进程启动 pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSApp.setActivationPolicy(.accessory)
        setupWindow()
        setupKeyMonitor()
        watchParentProcess()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 只有一个窗口，关掉就退出整个进程。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Window

    private func setupWindow() {
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.preferredContentSize = NSSize(width: 720, height: 540)
        hostingController = hosting

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 液态玻璃窗口（macOS 26 Tahoe）：
        // 内容视图换成 NSVisualEffectView（.hudWindow 材质），SwiftUI 视图悬浮其上
        if #available(macOS 26.0, *) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            window.contentView = effect

            hosting.view.frame = effect.bounds
            hosting.view.autoresizingMask = [.width, .height]
            effect.addSubview(hosting.view)
        } else {
            window.contentViewController = hosting
        }
        window.setContentSize(NSSize(width: 720, height: 540))
        window.contentMinSize = NSSize(width: 560, height: 420)
        window.title = L10n.t("settings.window.title")
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
    }

    // MARK: - 键盘快捷键

    /// ⌘W：关闭主窗口（进程随之退出，与红圈按钮同效）。
    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "w" {
                // 仅当主窗口为 key 且未弹出 sheet（如"添加规则"）时关闭主窗口，
                // 避免连带关掉 sheet 或误触。
                if let win = self?.window, win.isKeyWindow, win.attachedSheet == nil {
                    win.performClose(nil)
                    return nil
                }
            }
            return event
        }
    }

    // MARK: - 父进程

    private func watchParentProcess() {
        guard let raw = ProcessInfo.processInfo.environment["ASI_PARENT_PID"],
              let pid = pid_t(raw) else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        parentSource = source
    }
}
