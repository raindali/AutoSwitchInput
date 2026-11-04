import SwiftUI
import AppKit

/// 应用图标缓存：规则列表每次重绘都会取图标。
@MainActor
private enum AppIconCache {
    static var storage: [String: NSImage] = [:]
    /// 未安装的 App 也记住，避免每次重绘（以及手动输入 bundle ID 时每个按键）都查一次 LaunchServices。
    static var missing: Set<String> = []
    /// 缓存条数上限；超过就整体清空，避免规则很多时无限增长。
    static let limit = 64
    /// 调用方最大渲染 36 pt，按 2x 降采样即可，不必保留全分辨率图标。
    static let targetSize = NSSize(width: 72, height: 72)

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = storage[bundleID] { return cached }
        if missing.contains(bundleID) { return nil }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if missing.count >= limit {
                storage.removeAll(keepingCapacity: true)
                missing.removeAll(keepingCapacity: true)
            }
            missing.insert(bundleID)
            return nil
        }

        let full = NSWorkspace.shared.icon(forFile: url.path)
        let resized = NSImage(size: targetSize, flipped: false) { rect in
            full.draw(in: rect)
            return true
        }
        if storage.count >= limit {
            storage.removeAll(keepingCapacity: true)
            missing.removeAll(keepingCapacity: true)
        }
        storage[bundleID] = resized
        return resized
    }
}

/// 解析应用图标：按 Bundle ID 取真实图标，失败回退到系统 app 符号。
@MainActor
func appIcon(for bundleID: String) -> Image {
    if let icon = AppIconCache.icon(for: bundleID) {
        return Image(nsImage: icon)
    }
    return Image(systemName: "app.fill")
}
