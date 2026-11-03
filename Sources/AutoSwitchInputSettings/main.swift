import AppKit

// 设置窗口进程入口（由菜单栏进程以 --settings 拉起）。
// 关窗即退出，SwiftUI 的视图图与渲染缓存随进程一起还给系统。
let app = NSApplication.shared
let delegate = SettingsAppDelegate()
app.delegate = delegate
app.run()
