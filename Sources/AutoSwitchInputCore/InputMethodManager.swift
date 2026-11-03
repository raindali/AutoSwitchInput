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

    /// 纯筛选逻辑：只保留启用的键盘输入法，去掉父容器类型与同名重复项，按名称排序。
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
        guard let unmanaged = TISCreateInputSourceList(nil, false) else { return [] }
        let cfArray = unmanaged.takeRetainedValue()
        let count = CFArrayGetCount(cfArray)
        var sources: [RawInputSource] = []
        sources.reserveCapacity(count)

        for i in 0..<count {
            let rawPtr = CFArrayGetValueAtIndex(cfArray, i)!
            let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()

            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            else { continue }

            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String

            let category = stringProperty(source, kTISPropertyInputSourceCategory) ?? ""
            let type = stringProperty(source, kTISPropertyInputSourceType) ?? ""
            let isEnabled = boolProperty(source, kTISPropertyInputSourceIsEnabled) ?? false

            sources.append(RawInputSource(id: id, name: name, category: category, type: type, isEnabled: isEnabled))
        }

        return sources
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
        guard let unmanaged = TISCreateInputSourceList(nil, false) else { return false }
        let cfArray = unmanaged.takeRetainedValue()
        let count = CFArrayGetCount(cfArray)

        for i in 0..<count {
            let rawPtr = CFArrayGetValueAtIndex(cfArray, i)!
            let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()

            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String

            if sourceID == id {
                let status = TISSelectInputSource(source)
                return status == noErr
            }
        }
        return false
    }

    /// Returns the ID of the currently selected input source.
    /// 直接问系统要「当前输入源」，不必枚举全部输入法（旧实现每次都要建一个 CFArray 并逐个比对）。
    public func getCurrentInputSourceID() -> String? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return nil }
        let source = unmanaged.takeRetainedValue()
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    /// Returns the display name for a given input source ID.
    public func name(for id: String) -> String {
        getAllInputSources().first { $0.id == id }?.name ?? id
    }
}
