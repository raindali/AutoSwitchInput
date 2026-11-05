import AppKit
import Carbon

/// Wraps the Carbon TIS (Text Input Source) API for listing and selecting input methods.
@MainActor
public final class InputMethodManager {
    public static let shared = InputMethodManager()

    public struct InputSource: Identifiable, Hashable, Sendable {
        public let id: String   // TIS input source ID, e.g. "com.apple.keylayout.ABC"
        public let name: String // Localized display name, e.g. "ABC" or "简体拼音"

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// TIS 原始属性，单独抽出来是为了让筛选逻辑可以脱离 Carbon 单测。
    struct RawInputSource {
        let id: String
        let name: String
        let category: String
        let type: String
        let isEnabled: Bool
    }

    nonisolated static let keyboardCategory = "TISCategoryKeyboardInputSource"
    nonisolated static let parentContainerType = "TISTypeKeyboardInputMethodModeEnabled"

    private var cache: [InputSource] = []
    private var cacheTime: Date?

    public init() {}

    /// Returns all enabled keyboard input sources, sorted by name.
    public func getAllInputSources() -> [InputSource] {
        // Cache for 5 seconds to avoid repeated Carbon calls
        if let cacheTime = cacheTime,
           Date().timeIntervalSince(cacheTime) < 5,
           !cache.isEmpty {
            return cache
        }

        let sorted = Self.filtered(Self.loadRawInputSources())
        cache = sorted
        cacheTime = Date()
        return sorted
    }

    nonisolated static func filtered(_ sources: [RawInputSource]) -> [InputSource] {
        var result: [InputSource] = []
        var seenNames = Set<String>()

        for source in sources {
            guard source.category == keyboardCategory else { continue }
            guard source.isEnabled else { continue }
            // 排除父容器输入法（如「简体中文」包裹「简体拼音」），否则选择器里会出现重复项。
            guard source.type != parentContainerType else { continue }
            // 去重：同名输入源（极少数情况下多个 ID 共享显示名）只保留第一个
            guard !seenNames.contains(source.name) else { continue }

            seenNames.insert(source.name)
            result.append(InputSource(id: source.id, name: source.name))
        }

        return result.sorted { $0.name < $1.name }
    }

    private static func loadRawInputSources() -> [RawInputSource] {
        withAllInputSources { all in
            var sources: [RawInputSource] = []
            sources.reserveCapacity(all.count)

            for source in all {
                guard let id = stringProperty(source, kTISPropertyInputSourceID),
                      let name = stringProperty(source, kTISPropertyLocalizedName)
                else { continue }

                let category = stringProperty(source, kTISPropertyInputSourceCategory) ?? ""
                let type = stringProperty(source, kTISPropertyInputSourceType) ?? ""
                let isEnabled = boolProperty(source, kTISPropertyInputSourceIsEnabled) ?? false

                sources.append(RawInputSource(id: id, name: name, category: category, type: type, isEnabled: isEnabled))
            }

            return sources
        }
    }

    /// 枚举全部输入源；`body` 执行期间持有底层 CFArray，避免其中的对象被提前释放。
    private static func withAllInputSources<T>(_ body: ([TISInputSource]) -> T) -> T {
        guard let unmanaged = TISCreateInputSourceList(nil, false) else { return body([]) }
        let cfArray = unmanaged.takeRetainedValue()
        let sources: [TISInputSource] = (0..<CFArrayGetCount(cfArray)).map { i in
            let rawPtr = CFArrayGetValueAtIndex(cfArray, i)!
            return Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()
        }
        return body(sources)
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    /// Selects the input source with the given ID. Returns true on success.
    @discardableResult
    public func selectInputSource(id: String) -> Bool {
        // 让 Carbon 按 ID 过滤，避免为了找一个 ID 把全部输入源都转成 Swift String。
        // 必须带 includeAllInstalled=true 过滤才生效；随后自己排除未启用的输入源，
        // 与旧实现「只枚举已启用输入源」的行为保持一致。
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        if let unmanaged = TISCreateInputSourceList(filter, true) {
            let cfArray = unmanaged.takeRetainedValue()
            for i in 0..<CFArrayGetCount(cfArray) {
                guard let rawPtr = CFArrayGetValueAtIndex(cfArray, i) else { continue }
                let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()
                guard Self.boolProperty(source, kTISPropertyInputSourceIsEnabled) ?? false else { continue }
                return TISSelectInputSource(source) == noErr
            }
            // 过滤到了同名输入源但全部未启用：与旧实现（只枚举已启用输入源）一样返回失败。
            if CFArrayGetCount(cfArray) > 0 { return false }
        }

        // 过滤未生效时回落到全量枚举，保持与旧行为一致。
        return Self.withAllInputSources { sources in
            for source in sources {
                guard let sourceID = Self.stringProperty(source, kTISPropertyInputSourceID) else { continue }
                if sourceID == id {
                    return TISSelectInputSource(source) == noErr
                }
            }
            return false
        }
    }

    /// Returns the ID of the currently selected input source.
    public func getCurrentInputSourceID() -> String? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return nil }
        return Self.stringProperty(unmanaged.takeRetainedValue(), kTISPropertyInputSourceID)
    }

    /// Returns the display name for a given input source ID.
    public func name(for id: String) -> String {
        getAllInputSources().first { $0.id == id }?.name ?? id
    }

    /// 该输入源当前是否仍处于启用状态（用于校验记住的输入源是否还有效）。
    public func isEnabled(id: String) -> Bool {
        // 与 selectInputSource 一样按 ID 过滤，避免为回答一个问题枚举全部输入源。
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        if let unmanaged = TISCreateInputSourceList(filter, true) {
            let cfArray = unmanaged.takeRetainedValue()
            let count = CFArrayGetCount(cfArray)
            for i in 0..<count {
                guard let rawPtr = CFArrayGetValueAtIndex(cfArray, i) else { continue }
                let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()
                if Self.boolProperty(source, kTISPropertyInputSourceIsEnabled) ?? false { return true }
            }
            if count > 0 { return false }
        }

        return Self.withAllInputSources { sources in
            sources.contains { Self.stringProperty($0, kTISPropertyInputSourceID) == id }
        }
    }
}
