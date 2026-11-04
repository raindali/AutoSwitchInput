import XCTest
@testable import AutoSwitchInputCore

@MainActor
final class InputMethodManagerTests: XCTestCase {

    private func raw(
        _ id: String,
        _ name: String,
        category: String = InputMethodManager.keyboardCategory,
        type: String = "TISTypeKeyboardLayout",
        enabled: Bool = true
    ) -> InputMethodManager.RawInputSource {
        InputMethodManager.RawInputSource(
            id: id,
            name: name,
            category: category,
            type: type,
            isEnabled: enabled
        )
    }

    func testFilteredRules() {
        struct Case {
            let name: String
            let input: [InputMethodManager.RawInputSource]
            let expectedIDs: [String]
        }

        let cases: [Case] = [
            Case(
                name: "保留键盘输入法",
                input: [
                    raw("com.apple.keylayout.ABC", "ABC"),
                    raw("com.apple.inputmethod.SCIM.ITABC", "简体拼音", type: "TISTypeKeyboardInputMode"),
                ],
                expectedIDs: ["com.apple.keylayout.ABC", "com.apple.inputmethod.SCIM.ITABC"]
            ),
            Case(
                name: "过滤非键盘类别",
                input: [
                    raw("com.apple.keylayout.ABC", "ABC"),
                    raw("com.apple.inputmethod.voice", "语音", category: "TISCategoryPaletteInputSource"),
                ],
                expectedIDs: ["com.apple.keylayout.ABC"]
            ),
            Case(
                name: "过滤未启用",
                input: [
                    raw("com.apple.keylayout.ABC", "ABC", enabled: false),
                    raw("com.apple.keylayout.US", "美国"),
                ],
                expectedIDs: ["com.apple.keylayout.US"]
            ),
            Case(
                name: "过滤父容器类型",
                input: [
                    raw("com.apple.inputmethod.SCIM", "简体中文", type: InputMethodManager.parentContainerType),
                    raw("com.apple.inputmethod.SCIM.ITABC", "简体拼音", type: "TISTypeKeyboardInputMode"),
                ],
                expectedIDs: ["com.apple.inputmethod.SCIM.ITABC"]
            ),
            Case(
                name: "同名去重",
                input: [
                    raw("com.vendor.a", "ABC"),
                    raw("com.vendor.b", "ABC"),
                ],
                expectedIDs: ["com.vendor.a"]
            ),
            Case(
                name: "按名称排序",
                input: [
                    raw("id.c", "Charlie"),
                    raw("id.a", "Alpha"),
                    raw("id.b", "Bravo"),
                ],
                expectedIDs: ["id.a", "id.b", "id.c"]
            ),
        ]

        for c in cases {
            XCTAssertEqual(InputMethodManager.filtered(c.input).map(\.id), c.expectedIDs, c.name)
        }
    }

    func testLiveInputSourcesAreUniqueAndCurrentSourceIsKnown() throws {
        let sources = InputMethodManager.shared.getAllInputSources()
        XCTAssertFalse(sources.isEmpty, "枚举不到任何输入源，Carbon 路径可能坏了")
        XCTAssertEqual(Set(sources.map(\.name)).count, sources.count, "输入源显示名不应重复")

        if let current = InputMethodManager.shared.getCurrentInputSourceID() {
            XCTAssertFalse(current.isEmpty)
        }
    }
}
