import Foundation

/// 界面文案统一走 `Localizable.strings`（en / zh-Hans）。
///
/// 用语义化 key 而不是把中文写死在代码里：代码保持语言中立，翻译与 review 都更容易。
/// 找不到对应条目时回退成 key 本身，漏翻一眼就能看出来。
public enum L10n {
    public static func t(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    public static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: ""),
            arguments: arguments
        )
    }
}
