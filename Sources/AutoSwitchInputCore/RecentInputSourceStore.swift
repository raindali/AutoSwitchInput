import Foundation

/// 按 App 记住最近一次使用的输入源。
public final class RecentInputSourceStore {
    private struct Entry: Codable, Equatable {
        var bundleID: String
        var inputSourceID: String
    }

    public static let defaultLimit = 200
    static let defaultsKey = "recentInputSources"

    private let defaults: UserDefaults
    private let limit: Int
    private var entries: [Entry]

    public init(defaults: UserDefaults = .standard, limit: Int = RecentInputSourceStore.defaultLimit) {
        self.defaults = defaults
        self.limit = limit
        entries = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    /// 该 App 上次离开时使用的输入源；没有记录返回 nil。
    public func source(for bundleID: String) -> String? {
        entries.last { $0.bundleID == bundleID }?.inputSourceID
    }

    /// 记录一次；同一 App 会移到最近使用的位置。
    public func remember(_ inputSourceID: String, for bundleID: String) {
        let entry = Entry(bundleID: bundleID, inputSourceID: inputSourceID)
        guard entries.last != entry else { return }
        entries.removeAll { $0.bundleID == bundleID }
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
