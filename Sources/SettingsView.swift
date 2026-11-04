import SwiftUI
import AppKit

// MARK: - Settings Window (Redesigned)

struct SettingsView: View {
    @ObservedObject private var store = RuleStore.shared
    @State private var showingAddSheet = false
    @State private var inputSources: [InputMethodManager.InputSource] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 结构过渡统一动效；系统开启「减少动态效果」时自动关闭。
    private var motion: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    var body: some View {
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
                Text("通用").font(.headline)

                settingRow(
                    icon: "arrow.left.arrow.right",
                    title: "启用自动切换",
                    subtitle: "切换应用时，按规则自动匹配输入法"
                ) {
                    Toggle(isOn: $store.autoSwitchEnabled) { }
                        .toggleStyle(.switch)
                        .tint(Design.accent)
                        .labelsHidden()
                }

                Divider().padding(.vertical, Design.spacing1)

                settingRow(
                    icon: "power",
                    title: "开机启动",
                    subtitle: "登录系统后自动运行本应用"
                ) {
                    Toggle(isOn: $store.launchAtLogin) { }
                        .toggleStyle(.switch)
                        .tint(Design.accent)
                        .labelsHidden()
                }

                Divider().padding(.vertical, Design.spacing1)

                settingRow(
                    icon: "globe",
                    title: "默认输入法",
                    subtitle: "无匹配规则时使用的输入法"
                ) {
                    AutoInputMenu(
                        items: [
                            AutoInputMenu.Item(name: "不切换", value: nil, isSelected: store.defaultInputSourceID == nil),
                        ] + inputSources.map { source in
                            AutoInputMenu.Item(name: source.name, value: source.id, isSelected: store.defaultInputSourceID == source.id)
                        },
                        selectedName: (store.defaultInputSourceID.flatMap { id in inputSources.first { $0.id == id }?.name }) ?? "不切换",
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
                    Text("应用规则").font(.headline)
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
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // 联动提示：自动切换关闭时，规则暂不生效
                if !store.autoSwitchEnabled {
                    HStack(spacing: 7) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(Design.statusOff)
                        Text("自动切换已关闭，以下规则暂不生效")
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
            Text("还没有应用规则")
                .font(.headline)
            Text("为常用 App 添加规则：当它在前台时自动切换到指定输入法。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button {
                showingAddSheet = true
            } label: {
                Label("添加第一条规则", systemImage: "plus")
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
                Text("输入法自动切换").font(.title3.weight(.semibold))
                Text("按应用自动切换中英文与拼音输入").font(.subheadline).foregroundStyle(.secondary)
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
            Text(store.autoSwitchEnabled ? "运行中" : "已暂停")
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
        .help(store.autoSwitchEnabled ? "自动切换正在工作" : "自动切换已关闭")
    }
}

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
                    .accessibilityLabel(pendingDelete ? "再次点击确定删除 \(rule.appName)" : "删除规则 \(rule.appName)")
                    .help(pendingDelete ? "再次点击确定删除 \(rule.appName)" : "删除规则 \(rule.appName)")

                    AutoInputMenu(
                        items: inputSources.map { source in
                            AutoInputMenu.Item(name: source.name, value: source.id, isSelected: selectedID == source.id)
                        },
                        selectedName: inputSources.first { $0.id == selectedID }?.name ?? "选择输入法",
                        fixedWidth: 170
                    ) { newID in
                        if let newID, newID != selectedID {
                            selectedID = newID
                            onChangeInputSource(newID)
                        }
                    }
                }
                .help("点击下拉切换该应用的输入法")
            }
            .padding(Design.spacing3)
        }
    }
}

// MARK: - Add Rule Sheet (Redesigned)
//
// 视觉语言：去掉 Card 套娃，改用「预览行 + Menu 触发器」。
// - 顶部：标题 + 副标题（一句说明）
// - 中部两个分组：应用预览行 / 输入法预览行；预览行内左侧固定预览，右侧「选择…」菜单
// - 底部固定按钮：取消（borderless）/ 添加（prominent）

struct AddRuleSheet: View {
    @ObservedObject var store: RuleStore
    let inputSources: [InputMethodManager.InputSource]

    @State private var selectedBundleID: String = ""
    @State private var selectedAppName: String = ""
    @State private var selectedInputSourceID: String = ""
    @State private var manualBundleID: String = ""
    @State private var manualAppName: String = ""
    @State private var useManual = false
    /// 打开 sheet 时抓一次运行中应用快照；原来每次重绘都会重新枚举所有进程。
    @State private var runningApps: [NSRunningApplication] = []
    @Environment(\.dismiss) var dismiss

    // MARK: - Derived
    private var finalBundleID: String { useManual ? manualBundleID : selectedBundleID }
    private var finalAppName: String { useManual ? manualAppName : selectedAppName }
    private var selectedInputSourceName: String {
        inputSources.first { $0.id == selectedInputSourceID }?.name ?? ""
    }
    private var hasAppSelected: Bool {
        useManual ? (!manualBundleID.isEmpty && !manualAppName.isEmpty) : !selectedBundleID.isEmpty
    }
    private var canAdd: Bool {
        hasAppSelected && !selectedInputSourceID.isEmpty
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 460, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Design.accent)
        .accentColor(Design.accent)
        .onAppear { runningApps = store.runningApps() }
    }

    // MARK: - Sections
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("添加应用规则").font(.title3.weight(.semibold))
            Text("选择应用并指定该应用激活时自动切换的输入法。").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.spacing5)
        .padding(.top, Design.spacing5)
        .padding(.bottom, Design.spacing4)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Design.spacing5) {
            appPickerSection
            inputMethodSection
        }
        .padding(Design.spacing5)
    }

    private var appPickerSection: some View {
        VStack(alignment: .leading, spacing: Design.spacing2) {
            sectionHeader(icon: "app.badge.checkmark", title: "应用")

            appRow

            if useManual {
                VStack(spacing: 6) {
                    TextField("Bundle Identifier（如 com.tencent.xinWeChat）", text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)
                    TextField("应用名称", text: $manualAppName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: useManual)
    }

    private var appRow: some View {
        HStack(spacing: 10) {
            appRowIcon
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(hasAppSelected ? finalAppName : "未选择应用")
                    .font(.body.weight(.medium))
                    .foregroundStyle(hasAppSelected ? .primary : .secondary)
                    .lineLimit(1)
                Text(hasAppSelected ? finalBundleID : "点击右侧「选择」从运行中的应用或浏览 .app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Menu {
                Section("运行中的应用") {
                    if runningApps.isEmpty {
                        Text("没有运行中的应用").foregroundStyle(.secondary)
                    } else {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button {
                                if useManual { useManual = false }
                                selectedBundleID = app.bundleIdentifier ?? ""
                                selectedAppName = app.localizedName ?? ""
                            } label: {
                                if let bid = app.bundleIdentifier, bid == selectedBundleID, !useManual {
                                    Label(app.localizedName ?? "Unknown", systemImage: "checkmark")
                                } else {
                                    Text(app.localizedName ?? "Unknown")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button {
                    browseForApp()
                } label: {
                    Label("浏览 .app…", systemImage: "folder")
                }
                Divider()
                Toggle(isOn: $useManual) {
                    Label("手动输入 Bundle ID", systemImage: "keyboard")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("选择")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color(nsColor: .controlBackgroundColor))
                )
                .foregroundStyle(Color.primary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Design.rowBackground)
        )
    }

    private var appRowIcon: some View {
        Group {
            if hasAppSelected {
                appIcon(for: finalBundleID)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
    }

    private var inputMethodSection: some View {
        VStack(alignment: .leading, spacing: Design.spacing2) {
            sectionHeader(icon: "globe", title: "输入法")

            Menu {
                if inputSources.isEmpty {
                    Text("暂无可用输入法").foregroundStyle(.secondary)
                } else {
                    ForEach(inputSources) { source in
                        Button {
                            selectedInputSourceID = source.id
                        } label: {
                            if source.id == selectedInputSourceID {
                                Label(source.name, systemImage: "checkmark")
                            } else {
                                Text(source.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                    Text(selectedInputSourceName.isEmpty ? "选择输入法" : selectedInputSourceName)
                        .foregroundStyle(selectedInputSourceName.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.body.weight(.medium))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Design.rowBackground)
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private var footer: some View {
        HStack(spacing: Design.spacing3) {
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: addRule) {
                Text("添加")
                    .frame(minWidth: 64)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canAdd)
        }
        .padding(.horizontal, Design.spacing5)
        .padding(.vertical, Design.spacing4)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Actions
    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url) {
                selectedBundleID = bundle.bundleIdentifier ?? ""
                selectedAppName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func addRule() {
        let name = inputSources.first { $0.id == selectedInputSourceID }?.name ?? ""
        store.rules.append(AppRule(
            bundleIdentifier: finalBundleID,
            appName: finalAppName,
            inputSourceID: selectedInputSourceID,
            inputSourceName: name
        ))
        dismiss()
    }
}

// MARK: - 自制输入法下拉框
/// 用普通 Button 实现：普通 Button 的 .frame(width:) 可靠生效（原生 Picker / borderlessButton
/// Menu 会被压缩成跟随内容宽度，无法固定），故能锁定固定宽度；弹出层用系统 popover 毛玻璃，
/// 触发按钮背景为极淡主题色（深色偏灰、浅色近乎透明），彻底避免原生控件那种突兀的白色长条。
struct AutoInputMenu: View {
    struct Item: Identifiable {
        let name: String
        let value: String?
        let isSelected: Bool
        var id: String { name }
    }

    let items: [Item]
    let selectedName: String
    var fixedWidth: CGFloat = 240
    var onSelect: (String?) -> Void = { _ in }

    @State private var isOpen = false

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
                            if item.isSelected {
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
