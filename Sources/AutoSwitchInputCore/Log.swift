import os

/// 统一日志入口。分类打点，便于按子系统过滤：
///
///     log stream --predicate 'subsystem == "com.qingwei.inputswitch"' --level debug
///
/// 用 `os.Logger` 而不是 `print`/`NSLog`：不阻塞、不刷屏，
/// 且能按 category 与 level 在 Console.app / `log` 里精确筛选。
public enum Log {
    public static let subsystem = "com.qingwei.inputswitch"

    /// 进程生命周期、设置进程拉起等。
    public static let app = Logger(subsystem: subsystem, category: "app")
    /// 前台应用监听与防抖。
    public static let monitor = Logger(subsystem: subsystem, category: "monitor")
    /// 输入源枚举与切换。
    public static let inputSource = Logger(subsystem: subsystem, category: "input-source")
    /// 规则持久化、跨进程同步、登录项。
    public static let rules = Logger(subsystem: subsystem, category: "rules")
    /// 设置窗口进程。
    public static let settings = Logger(subsystem: subsystem, category: "settings")
}
