import SwiftUI
import AppKit
import AutoSwitchInputCore

// MARK: - Settings Window (Redesigned)

public struct SettingsView: View {
    @ObservedObject private var store = RuleStore.shared

    public init() {}

    @State private var showingAddSheet = false
    @State private var inputSources: [InputMethodManager.InputSource] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 结构过渡统一动效；系统开启「减少动态效果」时自动关闭。
    private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    public var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            ScrollView {
                VStack(alignment: .leading, spacing: Design.spacing6) {
                    generalSection
                    rulesSection
                }
                .padding(Design.spacing6)
            }
            // 隐藏系统滚动条：macOS 接鼠标时常驻显示较粗的系统条，显眼且不控于 SwiftUI 外观；
            // 隐藏后内容直接悬浮于玻璃窗口上，更轻、更液态玻璃。
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 背景透明：液态玻璃由窗口层（NSVisualEffectView）提供，SwiftUI 内容悬浮其上
        .background(Color.clear)
        // 强调色改为深灰，覆盖 Toggle / Picker 选中 / 按钮 / Header 方块等
        // 注意：macOS 上 Toggle(switch) 的开态颜色由 .tint 控制，故 accentColor 与 tint 都设
        .accentColor(Design.accent)
        .tint(Design.accent)
        .onAppear { inputSources = InputMethodManager.shared.getAllInputSources() }
        .sheet(isPresented: $showingAddSheet) {
            AddRuleSheet(store: store, inputSources: inputSources)
        }
    }

    // MARK: 通用
    private var generalSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Design.spacing4) {
                Text(L10n.t("settings.general.title")).font(.headline)

                settingRow(
                    icon: "arrow.left.arrow.right",
                    title: L10n.t("settings.autoSwitch.title"),
                    subtitle: L10n.t("settings.autoSwitch.subtitle")
                ) {
                    Toggle(isOn: $store.autoSwitchEnabled) { }
                        .toggleStyle(.switch)
                        .tint(Design.accent)
                        .labelsHidden()
                }

                Divider().padding(.vertical, Design.spacing1)

                settingRow(
                    icon: "power",
                    title: L10n.t("settings.launchAtLogin.title"),
                    subtitle: L10n.t("settings.launchAtLogin.subtitle")
                ) {
                    Toggle(isOn: $store.launchAtLogin) { }
                        .toggleStyle(.switch)
                        .tint(Design.accent)
                        .labelsHidden()
                }

                Divider().padding(.vertical, Design.spacing1)

                settingRow(
                    icon: "globe",
                    title: L10n.t("settings.defaultInputSource.title"),
                    subtitle: L10n.t("settings.defaultInputSource.subtitle")
                ) {
                    AutoInputMenu(
                        items: [
                            AutoInputMenu.Item(name: L10n.t("settings.defaultInputSource.none"), value: nil, isSelected: store.defaultInputSourceID == nil),
                        ] + inputSources.map { source in
                            AutoInputMenu.Item(name: source.name, value: source.id, isSelected: store.defaultInputSourceID == source.id)
                        },
                        selectedName: (store.defaultInputSourceID.flatMap { id in inputSources.first { $0.id == id }?.name }) ?? L10n.t("settings.defaultInputSource.none"),
                        fixedWidth: 170
                    ) { newID in
                        store.defaultInputSourceID = newID
                    }
                    .opacity(store.autoSwitchEnabled ? 1 : 0.5)
                    .disabled(!store.autoSwitchEnabled)
                }
            }
        }
    }

    /// 设置行模板：前导图标磁贴稳定锚点 + 标题/副标题 + 尾随控件。
    private func settingRow<Control: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing control: () -> Control
    ) -> some View {
        HStack(spacing: Design.spacing3) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Design.spacing3)
            control()
        }
        .animation(motion, value: store.autoSwitchEnabled)
    }

    // MARK: 应用规则
    private var rulesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Design.spacing4) {
                HStack {
                    Text(L10n.t("settings.rules.title")).font(.headline)
                    if !store.rules.isEmpty {
                        Text("\(store.rules.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    Spacer()
                    Button(action: { showingAddSheet = true }) {
                        Label(L10n.t("settings.rules.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // 联动提示：自动切换关闭时，规则暂不生效
                if !store.autoSwitchEnabled {
                    HStack(spacing: 7) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(Design.statusOff)
                        Text(L10n.t("settings.rules.disabledHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(Design.spacing3)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if store.rules.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: Design.spacing2) {
                        ForEach(store.rules) { rule in
                            RuleRow(
                                rule: rule,
                                inputSources: inputSources,
                                onDelete: {
                                    removeRule(rule)
                                },
                                onChangeInputSource: { newID in
                                    if let idx = store.rules.firstIndex(where: { $0.id == rule.id }) {
                                        store.rules[idx].inputSourceID = newID
                                        store.rules[idx].inputSourceName = InputMethodManager.shared.name(for: newID)
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                        }
                    }
                    // 「自动切换」关闭时整组置灰，让规则区与全局状态联动
                    .opacity(store.autoSwitchEnabled ? 1 : 0.5)
                    .allowsHitTesting(store.autoSwitchEnabled)
                    .animation(motion, value: store.rules)
                }
            }
        }
        .animation(motion, value: store.autoSwitchEnabled)
    }

    /// 空状态：图标 + 一句说明 + 明确的一级引导，邀请用户建立第一条规则。
    private var emptyState: some View {
        VStack(spacing: Design.spacing3) {
            RoundedRectangle(cornerRadius: Design.radiusMd, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.tertiary)
                )
            Text(L10n.t("settings.rules.empty.title"))
                .font(.headline)
            Text(L10n.t("settings.rules.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button {
                showingAddSheet = true
            } label: {
                Label(L10n.t("settings.rules.empty.action"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.spacing6)
        .padding(.horizontal, Design.spacing3)
    }

    private func removeRule(_ rule: AppRule) {
        if reduceMotion {
            store.rules.removeAll { $0.id == rule.id }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                store.rules.removeAll { $0.id == rule.id }
            }
        }
    }
}

// MARK: - Header (Brand Area)

struct HeaderView: View {
    @ObservedObject private var store = RuleStore.shared

    var body: some View {
        HStack(spacing: Design.spacing4) {
            RoundedRectangle(cornerRadius: Design.radiusSm, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "keyboard")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("settings.header.title")).font(.title3.weight(.semibold))
                Text(L10n.t("settings.header.subtitle")).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
        .padding(.horizontal, Design.spacing6)
        .padding(.vertical, Design.spacing5)
        // 头部毛玻璃条：半透明材质 + 底部高光分隔线（Liquid Glass 风格）
        .background(.ultraThinMaterial)
        .overlay(
            LinearGradient(
                colors: [.white.opacity(0.12), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 1),
            alignment: .bottom
        )
        // 开/关状态实时反映在头部，避免用户只看到「启用自动切换」这一个开关而忽略全局状态
        .animation(.easeOut(duration: 0.2), value: store.autoSwitchEnabled)
    }

    /// 全局状态胶囊：状态点 + 文案，一眼判断当前是否在工作。
    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.autoSwitchEnabled ? Design.statusOn : Design.statusOff)
                .frame(width: 7, height: 7)
            Text(store.autoSwitchEnabled ? L10n.t("settings.status.running") : L10n.t("settings.status.paused"))
                .font(.caption.weight(.medium))
                .foregroundStyle(store.autoSwitchEnabled ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .help(store.autoSwitchEnabled ? L10n.t("settings.status.running.help") : L10n.t("settings.status.paused.help"))
    }
}
