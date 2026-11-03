import AppKit

// Classic AppKit entry point.
// 同一个二进制有两种运行模式（见 AppMode）：
//   • 默认：菜单栏常驻进程，只负责 NSStatusItem / 右键菜单 / 前台应用监听；
//   • --settings：设置窗口进程，由菜单栏进程按需拉起，窗口关闭即退出。
// 拆开的原因：SwiftUI 的视图图与渲染缓存一旦用上就基本不会还给系统，
// 放进短命进程后，常驻的菜单栏进程可以一直保持在 ~12 MB。
let app = NSApplication.shared
let delegate: NSApplicationDelegate = AppMode.isSettingsHelper
    ? SettingsAppDelegate()
    : AppDelegate()
app.delegate = delegate
app.run()
