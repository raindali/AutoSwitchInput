import Foundation

/// 同一个二进制的两种运行模式。
enum AppMode {
    /// `--settings`：设置窗口进程（短命，关窗即退出）。
    static let isSettingsHelper = CommandLine.arguments.contains("--settings")
}

/// App-to-input-method mapping rule
struct AppRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bundleIdentifier: String
    var appName: String
    var inputSourceID: String
    var inputSourceName: String
}
