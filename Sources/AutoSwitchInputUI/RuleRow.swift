import SwiftUI
import AppKit
import AutoSwitchInputCore

// MARK: - Rule Row

struct RuleRow: View {
    let rule: AppRule
    let inputSources: [InputMethodManager.InputSource]
    let onDelete: () -> Void
    /// 下拉切换输入法时回调，参数为新的输入法 ID。
    let onChangeInputSource: (String) -> Void
    @State private var selectedID: String
    /// 二段式删除确认：第一次点击进入确认态（变红），再点一次才真正删除。
    @State private var pendingDelete = false

    init(rule: AppRule,
         inputSources: [InputMethodManager.InputSource],
         onDelete: @escaping () -> Void,
         onChangeInputSource: @escaping (String) -> Void) {
        self.rule = rule
        self.inputSources = inputSources
        self.onDelete = onDelete
        self.onChangeInputSource = onChangeInputSource
        _selectedID = State(initialValue: rule.inputSourceID)
    }

    var body: some View {
        GlassRow {
            HStack(spacing: Design.spacing3) {
                appIcon(for: rule.bundleIdentifier)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.appName).font(.body.weight(.medium))
                    Text(rule.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }

                Spacer()

                // 输入法选择框 + 删除按钮：紧凑成组并整体右对齐。
                // 用普通 Button 实现的自制下拉（AutoInputMenu）——宽度可被 .frame 固定，
                // 弹出层为 popover，背景用极淡主题色，与液态玻璃页面一致。
                HStack(spacing: 6) {
                    Button {
                        if pendingDelete {
                            onDelete()
                        } else {
                            pendingDelete = true
                        }
                    } label: {
                        Image(systemName: pendingDelete ? "trash.fill" : "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(pendingDelete ? Color.red : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(pendingDelete ? Color.red.opacity(0.14) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(pendingDelete ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.15), value: pendingDelete)
                    .accessibilityLabel(pendingDelete ? L10n.t("settings.rule.deleteConfirm", rule.appName) : L10n.t("settings.rule.delete", rule.appName))
                    .help(pendingDelete ? L10n.t("settings.rule.deleteConfirm", rule.appName) : L10n.t("settings.rule.delete", rule.appName))

                    AutoInputMenu(
                        items: inputSources.map { source in
                            AutoInputMenu.Item(name: source.name, value: source.id, isSelected: selectedID == source.id)
                        },
                        selectedName: inputSources.first { $0.id == selectedID }?.name ?? L10n.t("settings.inputSource.choose"),
                        fixedWidth: 170
                    ) { newID in
                        if let newID, newID != selectedID {
                            selectedID = newID
                            onChangeInputSource(newID)
                        }
                    }
                }
                .help(L10n.t("settings.rule.inputSource.help"))
            }
            .padding(Design.spacing3)
        }
    }
}
