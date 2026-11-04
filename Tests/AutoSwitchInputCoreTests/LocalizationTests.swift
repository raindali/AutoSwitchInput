import XCTest
@testable import AutoSwitchInputCore

final class LocalizationTests: XCTestCase {

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AutoSwitchInputCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 包根目录

    private static let tables: [String: [String: String]?] = {
        var result: [String: [String: String]?] = [:]
        for language in ["en", "zh-Hans"] {
            let url = packageRoot
                .appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
            let data = try? Data(contentsOf: url)
            let plist = data.flatMap {
                try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)
            }
            result[language] = plist as? [String: String]
        }
        return result
    }()

    private static let usedKeys: Set<String>? = {
        let sources = packageRoot.appendingPathComponent("Sources")
        guard let pattern = try? NSRegularExpression(
            pattern: #""((?:menu|settings|statusItem|alert)\.[A-Za-z0-9.]+)""#
        ) else { return nil }

        var keys = Set<String>()
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift",
                  let text = try? String(contentsOf: file, encoding: .utf8)
            else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    keys.insert(String(text[r]))
                }
            }
        }
        return keys
    }()

    private func table(_ language: String) throws -> [String: String] {
        try XCTUnwrap(Self.tables[language] ?? nil, "\(language) 不是有效的字符串表")
    }

    private func keysUsedInCode() throws -> Set<String> {
        try XCTUnwrap(Self.usedKeys, "扫描源码 key 失败")
    }

    func testLanguageTablesHaveIdenticalKeys() throws {
        let en = Set(try table("en").keys)
        let zh = Set(try table("zh-Hans").keys)

        XCTAssertEqual(en.subtracting(zh), [], "英文表里有、中文表里缺失的 key")
        XCTAssertEqual(zh.subtracting(en), [], "中文表里有、英文表里缺失的 key")
    }

    func testNoEmptyTranslations() throws {
        for language in ["en", "zh-Hans"] {
            for (key, value) in try table(language) where value.trimmingCharacters(in: .whitespaces).isEmpty {
                XCTFail("\(language) 的 \(key) 是空翻译")
            }
        }
    }

    func testEveryKeyUsedInCodeExists() throws {
        let used = try keysUsedInCode()
        XCTAssertFalse(used.isEmpty, "没有扫描到任何 key，正则可能失效了")

        for language in ["en", "zh-Hans"] {
            let table = Set(try table(language).keys)
            let missing = used.subtracting(table).sorted()
            XCTAssertEqual(missing, [], "\(language) 缺少这些 key")
        }
    }

    func testNoUnusedKeys() throws {
        let used = try keysUsedInCode()
        let table = Set(try table("en").keys)
        XCTAssertEqual(table.subtracting(used).sorted(), [], "这些 key 已无人使用，可以从字符串表里删掉")
    }

    /// 带参数的文案必须保留占位符，否则 String(format:) 会静默丢参数。
    func testPlaceholdersMatchBetweenLanguages() throws {
        let en = try table("en")
        let zh = try table("zh-Hans")

        for (key, enValue) in en {
            let zhValue = try XCTUnwrap(zh[key])
            let enCount = enValue.components(separatedBy: "%@").count - 1
            let zhCount = zhValue.components(separatedBy: "%@").count - 1
            XCTAssertEqual(enCount, zhCount, "\(key) 的 %@ 占位符数量不一致")
        }
    }
}
