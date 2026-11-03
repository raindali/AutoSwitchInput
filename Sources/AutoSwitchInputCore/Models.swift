import Foundation

/// 同一个 App 的两种运行模式。
///
/// 菜单栏进程会以 `--settings` 拉起设置进程；直接运行
/// `AutoSwitchInputSettings` 时按可执行文件名兜底识别。
public enum AppMode {
    public static let isSettingsHelper: Bool = {
        if CommandLine.arguments.contains("--settings") { return true }
        return Bundle.main.executableURL?.lastPathComponent == "AutoSwitchInputSettings"
    }()
}

/// App-to-input-method mapping rule
public struct AppRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var appName: String
    public var inputSourceID: String
    public var inputSourceName: String

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        inputSourceID: String,
        inputSourceName: String
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
    }
}
