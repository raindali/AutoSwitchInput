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

    func testKeepsKeyboardInputSources() {
        let result = InputMethodManager.filtered([
            raw("com.apple.keylayout.ABC", "ABC"),
            raw("com.apple.inputmethod.SCIM.ITABC", "简体拼音", type: "TISTypeKeyboardInputMode"),
        ])

        XCTAssertEqual(result.map(\.id), [
            "com.apple.keylayout.ABC",
            "com.apple.inputmethod.SCIM.ITABC",
        ])
    }

    func testFiltersOutNonKeyboardCategories() {
        let result = InputMethodManager.filtered([
            raw("com.apple.keylayout.ABC", "ABC"),
            raw("com.apple.inputmethod.voice", "语音", category: "TISCategoryPaletteInputSource"),
        ])

        XCTAssertEqual(result.map(\.id), ["com.apple.keylayout.ABC"])
    }

    func testFiltersOutDisabledSources() {
        let result = InputMethodManager.filtered([
            raw("com.apple.keylayout.ABC", "ABC", enabled: false),
            raw("com.apple.keylayout.US", "美国"),
        ])

        XCTAssertEqual(result.map(\.id), ["com.apple.keylayout.US"])
    }

    /// 父容器类型（如「简体中文」包裹「简体拼音」）会造成选择器里重复，必须过滤。
    func testFiltersOutParentContainerType() {
        let result = InputMethodManager.filtered([
            raw(
                "com.apple.inputmethod.SCIM",
                "简体中文",
                type: InputMethodManager.parentContainerType
            ),
            raw("com.apple.inputmethod.SCIM.ITABC", "简体拼音", type: "TISTypeKeyboardInputMode"),
        ])

        XCTAssertEqual(result.map(\.id), ["com.apple.inputmethod.SCIM.ITABC"])
    }

    func testDeduplicatesByDisplayName() {
        let result = InputMethodManager.filtered([
            raw("com.vendor.a", "ABC"),
            raw("com.vendor.b", "ABC"),
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "com.vendor.a")
    }

    func testSortsByDisplayName() {
        let result = InputMethodManager.filtered([
            raw("id.c", "Charlie"),
            raw("id.a", "Alpha"),
            raw("id.b", "Bravo"),
        ])

        XCTAssertEqual(result.map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    func testEmptyInputProducesEmptyResult() {
        XCTAssertTrue(InputMethodManager.filtered([]).isEmpty)
    }

    /// 真实环境冒烟：能拿到当前输入源，且列表里没有重复显示名。
    func testLiveInputSourcesAreUniqueAndCurrentSourceIsKnown() throws {
        let sources = InputMethodManager.shared.getAllInputSources()
        XCTAssertEqual(Set(sources.map(\.name)).count, sources.count, "输入源显示名不应重复")

        if let current = InputMethodManager.shared.getCurrentInputSourceID() {
            XCTAssertFalse(current.isEmpty)
        }
    }
}
