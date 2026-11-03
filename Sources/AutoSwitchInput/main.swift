import AppKit

// 菜单栏常驻进程入口。
// 只依赖 AutoSwitchInputCore（AppKit / Carbon / ServiceManagement），链接期不引入 SwiftUI；
// 设置窗口由 AutoSwitchInputSettings 独立进程承载，关窗即退出。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
