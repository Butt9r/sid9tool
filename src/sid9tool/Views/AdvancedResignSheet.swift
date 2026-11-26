import SwiftUI
import UniformTypeIdentifiers

/// v2 Step 4 — AltStore-style advanced install settings on the App page.
/// 一般 / 進階 Bundle ID / Tweak Injection / Info.plist 進階.
struct AdvancedResignSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @State private var model = ResignAdvanced()
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State private var showEntitlementsPicker = false
    @State private var showDylibPicker = false
    @State private var showFrameworkPicker = false

    private func t(_ zh: String, _ en: String, _ zhHans: String) -> String { localization.t(zh, en, zhHans) }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                bundleIDSection
                tweakSection
                plistSection
            }
            .navigationTitle(t("高級安裝設定", "Advanced Install Settings", "高级安装设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("取消", "Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("儲存", "Save", "保存"), action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .fileImporter(isPresented: $showEntitlementsPicker,
                      allowedContentTypes: [UTType.json],
                      allowsMultipleSelection: false) { result in
            handleImport(result) { url, name in
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    model.customEntitlementsJSON = String(data: data, encoding: .utf8) ?? name
                }
            }
        }
        .fileImporter(isPresented: $showDylibPicker,
                      allowedContentTypes: [UTType(filenameExtension: "dylib"), .data],
                      allowsMultipleSelection: true) { result in
            handleImport(result) { _, name in
                if !model.injectDylibs.contains(name) { model.injectDylibs.append(name) }
            }
        }
        .fileImporter(isPresented: $showFrameworkPicker,
                      allowedContentTypes: [UTType(filenameExtension: "framework"), .data],
                      allowsMultipleSelection: true) { result in
            handleImport(result) { _, name in
                if !model.injectFrameworks.contains(name) { model.injectFrameworks.append(name) }
            }
        }
    }

    // MARK: - 一般 (General)

    private var generalSection: some View {
        Section(t("一般", "General", "一般")) {
            Toggle(t("Try to support older iOS versions (7+)",
                     "Try to support older iOS versions (7+)",
                     "尝试支持更旧的 iOS 版本 (7+)"), isOn: $model.supportOlderIOS7)
            Toggle(t("Remove limitation on supported devices",
                     "Remove limitation on supported devices",
                     "移除支援裝置限制"), isOn: $model.removeDeviceLimitation)
            Toggle("Enable File Sharing", isOn: $model.enableFileSharing)
            Toggle(t("Remove App Extensions (PlugIns)",
                     "Remove App Extensions (PlugIns)",
                     "移除 App Extensions (PlugIns)"), isOn: $model.removeAppExtensions)
        }
    }

    // MARK: - 進階 Bundle ID

    private var bundleIDSection: some View {
        Section(t("進階 Bundle ID", "Advanced Bundle ID", "高级 Bundle ID")) {
            Toggle(t("Change app name", "Change app name", "更改应用名称"), isOn: $model.changeAppName)
            if model.changeAppName {
                TextField(t("Enter the new app name", "Enter the new app name", "输入新的应用名称"),
                          text: $model.newAppName)
                    .textInputAutocapitalization(.never)
            }
            Toggle(t("Change app version", "Change app version", "更改应用版本"), isOn: $model.changeAppVersion)
            if model.changeAppVersion {
                TextField("e.g. 1.2.3", text: $model.newAppVersion)
                    .autocorrectionDisabled()
            }
            Toggle(t("Use automatic bundle ID", "Use automatic bundle ID", "使用自动 Bundle ID"),
                   isOn: $model.useAutomaticBundleID)
            if !model.useAutomaticBundleID {
                TextField(t("Enter the desired Bundle ID", "Enter the desired Bundle ID", "输入期望的 Bundle ID"),
                          text: $model.customBundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Toggle(t("Use custom entitlements", "Use custom entitlements", "使用自订 Entitlements"),
                   isOn: $model.useCustomEntitlements)
            if model.useCustomEntitlements {
                TextField("{\"keychain-access-groups\":[\"*\"]}",
                          text: $model.customEntitlementsJSON, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(t("Browse…", "Browse…", "浏览…"), systemImage: "folder") { showEntitlementsPicker = true }
            }
        }
    }
    // MARK: - Tweak Injection

    private var tweakSection: some View {
        Section(t("Tweak Injection", "Tweak Injection", "Tweak 注入")) {
            HStack(spacing: 8) {
                Button(t("+ dylib / deb", "+ dylib / deb", "+ dylib / deb"),
                       systemImage: "plus") { showDylibPicker = true }
                Button(t("+ framework / bundle", "+ framework / bundle", "+ framework / bundle"),
                       systemImage: "plus") { showFrameworkPicker = true }
                Spacer()
            }
            .font(.caption)
            ForEach(Array(model.injectDylibs.enumerated()), id: \.offset) { index, name in
                HStack {
                    Text(name).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Del", role: .destructive) { model.injectDylibs.remove(at: index) }
                        .font(.caption)
                }
            }
            ForEach(Array(model.injectFrameworks.enumerated()), id: \.offset) { index, name in
                HStack {
                    Text(name).font(.caption).lineLimit(1)
                    Spacer()
                    Button("Del", role: .destructive) { model.injectFrameworks.remove(at: index) }
                        .font(.caption)
                }
            }
            Divider()
            Toggle("Cydia Substrate", isOn: $model.cydiaSubstrate)
            Toggle("Substitute", isOn: $model.substitute).disabled(!model.cydiaSubstrate)
            Toggle("Sideload Spoofer", isOn: $model.sideloadSpoofer)
        }
    }

    // MARK: - Info.plist 進階

    private var plistSection: some View {
        Section {
            ForEach(Array(model.plistFields.enumerated()), id: \.offset) { index, field in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(field.key).font(.caption.monospaced())
                        Text("=")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(field.value).font(.caption.monospaced()).lineLimit(2)
                    }
                    Button(t("Del", "Del", "删除"), role: .destructive) {
                        model.plistFields.remove(at: index)
                    }
                    .font(.caption2)
                }
            }
            TextField(t("Key (e.g. UIRequiresFullScreen)", "Key (e.g. UIRequiresFullScreen)",
                        "键 (如 UIRequiresFullScreen)"),
                      text: $newFieldKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField(t("Value (JSON scalar: true / 1.0 / \"x\")",
                        "Value (JSON scalar: true / 1.0 / \"x\")",
                        "值 (JSON 标量)"),
                      text: $newFieldValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(t("Add field", "Add field", "新增欄位"), systemImage: "plus") { addPlistField() }
                .disabled(newFieldKey.isEmpty)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Info.plist 進階", "Advanced Info.plist", "Info.plist 进阶"))
                Text("\(model.plistFields.count) \(t("field changes", "field changes", "欄位變更"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func addPlistField() {
        let key = newFieldKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        model.plistFields.append(
            PlistFieldEdit(key: key,
                           value: newFieldValue.trimmingCharacters(in: .whitespaces)))
        newFieldKey = ""
        newFieldValue = ""
    }

    private func save() {
        appState.advanced = model
        dismiss()
    }

    private func handleImport(_ result: Result<[URL], Error>,
                              transform: (String) -> Void) {
        switch result {
        case .success(let urls):
            for url in urls where url.isFileURL { transform(url.lastPathComponent) }
        case .failure:
            break
        }
    }
}

