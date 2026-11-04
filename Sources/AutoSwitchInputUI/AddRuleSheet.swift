import SwiftUI
import AppKit
import AutoSwitchInputCore

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
            Text(L10n.t("settings.add.title")).font(.title3.weight(.semibold))
            Text(L10n.t("settings.add.subtitle")).font(.subheadline).foregroundStyle(.secondary)
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
            sectionHeader(icon: "app.badge.checkmark", title: L10n.t("settings.add.app.section"))

            appRow

            if useManual {
                VStack(spacing: 6) {
                    TextField(L10n.t("settings.add.bundleID.placeholder"), text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.t("settings.add.appName.placeholder"), text: $manualAppName)
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
                Text(hasAppSelected ? finalAppName : L10n.t("settings.add.app.none"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(hasAppSelected ? .primary : .secondary)
                    .lineLimit(1)
                Text(hasAppSelected ? finalBundleID : L10n.t("settings.add.app.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Menu {
                Section(L10n.t("settings.add.runningApps.section")) {
                    if runningApps.isEmpty {
                        Text(L10n.t("settings.add.runningApps.empty")).foregroundStyle(.secondary)
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
                    Label(L10n.t("settings.add.browse"), systemImage: "folder")
                }
                Divider()
                Toggle(isOn: $useManual) {
                    Label(L10n.t("settings.add.manual"), systemImage: "keyboard")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.t("settings.add.choose"))
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
            sectionHeader(icon: "globe", title: L10n.t("settings.add.inputSource.section"))

            Menu {
                if inputSources.isEmpty {
                    Text(L10n.t("settings.add.inputSource.empty")).foregroundStyle(.secondary)
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
                    Text(selectedInputSourceName.isEmpty ? L10n.t("settings.inputSource.choose") : selectedInputSourceName)
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
            Button(L10n.t("settings.add.cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: addRule) {
                Text(L10n.t("settings.add.confirm"))
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
        store.rules.append(AppRule(
            bundleIdentifier: finalBundleID,
            appName: finalAppName,
            inputSourceID: selectedInputSourceID,
            inputSourceName: selectedInputSourceName
        ))
        dismiss()
    }
}
