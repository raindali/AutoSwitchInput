import SwiftUI
import AppKit
import AutoSwitchInputCore

// MARK: - 自制输入法下拉框
/// 用普通 Button 实现：普通 Button 的 .frame(width:) 可靠生效（原生 Picker / borderlessButton
/// Menu 会被压缩成跟随内容宽度，无法固定），故能锁定固定宽度；弹出层用系统 popover 毛玻璃，
/// 触发按钮背景为极淡主题色（深色偏灰、浅色近乎透明），彻底避免原生控件那种突兀的白色长条。
struct AutoInputMenu: View {
    struct Item: Identifiable {
        let name: String
        let value: String?
        var id: String { name }
    }

    let items: [Item]
    let selection: String?
    var placeholder: String
    var fixedWidth: CGFloat = 240
    var onSelect: (String?) -> Void = { _ in }

    @State private var isOpen = false

    private var selectedName: String {
        items.first { $0.value == selection }?.name ?? placeholder
    }

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 6) {
                Text(selectedName)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 10)
            .frame(width: fixedWidth, height: 24, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { (item: AutoInputMenu.Item) in
                    if item.id != (items.first?.id ?? "") {
                        Divider().padding(.horizontal, 8)
                    }
                    Button {
                        onSelect(item.value)
                        isOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.body)
                            Spacer(minLength: 8)
                            if item.value == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .frame(minWidth: 200)
            .padding(.vertical, 5)
        }
    }
}
