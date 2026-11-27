import SwiftUI
import UniformTypeIdentifiers

/// App tab — 3-slot quota header + unlimited reorderable container list.
struct AppTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @State private var importing = false
    @State private var showAdvanced = false
    @State private var appToDelete: SideloadedApp?
    @State private var showDeleteConfirmation = false

    /// P0-6: shared instance so container removal uses the on-disk manifest.
    @StateObject private var containerManager = ContainerManager()

    private var advancedSummary: String {
        let a = appState.advanced
        var parts: [String] = []
        if !a.customBundleID.isEmpty { parts.append("Bundle ID") }
        if a.useAutomaticBundleID { parts.append("Auto ID") }
        if a.changeAppName { parts.append("Name") }
        if a.changeAppVersion { parts.append("Version") }
        if a.enableFileSharing { parts.append("FileSharing") }
        if a.removeAppExtensions { parts.append("NoPlugIns") }
        if a.removeDeviceLimitation { parts.append("AllDevices") }
        if !a.injectDylibs.isEmpty || !a.injectFrameworks.isEmpty { parts.append("Tweak") }
        if !a.plistFields.isEmpty { parts.append("Plist \(a.plistFields.count)") }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    slotHeader
                        .listRowSeparator(.hidden)
                }
                if appState.apps.isEmpty {
                    Section {
                        Text(localization.t("尚未簽名任何 App", "No signed apps yet", "尚未签名任何 App"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(appState.apps) { app in
                            appRow(app)
                        }
                        .onMove { offsets, destination in
                            appState.moveApp(from: offsets, to: destination)
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first, index < appState.apps.count {
                                appToDelete = appState.apps[index]
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("App")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel(localization.t("匯入 IPA", "Import IPA", "导入 IPA"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdvanced = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(localization.t("高級安裝設定", "Advanced Install Settings", "高级安装设置"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .confirmationDialog(
                localization.t("移除容器", "Remove container", "移除容器"),
                isPresented: $showDeleteConfirmation,
                presenting: appToDelete
            ) { app in
                Button(
                    localization.t("移除", "Remove", "移除"),
                    role: .destructive
                ) {
                    deleteApp(app)
                }
                Button(localization.t("取消", "Cancel", "取消"), role: .cancel) {}
            } message: { app in
                Text(localization.t(
                    "將移除「\(app.name)」並釋放一個 slot，同時刪除其容器目錄。",
                    "This removes \"\(app.name)\" and frees a slot, and deletes its container directory.",
                    "这将移除“\(app.name)”并释放一个 slot，同时删除其容器目录。"
                ))
            }
            .sheet(isPresented: $importing) {
                ImportIPASheet()
            }
            .sheet(isPresented: $showAdvanced) {
                AdvancedResignSheet()
            }
        }
    }

    private var slotHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(localization.t(
                    "已用 \(appState.slot.occupiedSlots)/\(appState.slot.totalSlots) slot",
                    "Slots \(appState.slot.occupiedSlots)/\(appState.slot.totalSlots)",
                    "已用 \(appState.slot.occupiedSlots)/\(appState.slot.totalSlots) slot"
                ), systemImage: "cube.box.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            if !advancedSummary.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(advancedSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// P0-6: remove the app entry (frees a slot) and delete its container
    /// directory via `ContainerManager.removeContainer`.
    private func deleteApp(_ app: SideloadedApp) {
        let bundleId = app.bundleId
        appState.removeApp(app)
        Task { @MainActor in
            containerManager.removeContainer(bundleId: bundleId)
        }
    }

    /// P0-6: row content. Kept as a `@ViewBuilder` method (not a separate
    /// `struct AppRow: View`) so the `ForEach`'s row type is a plain view
    /// and `.onMove` / `.onDelete` resolve without type-checker ambiguity.
    @ViewBuilder
    private func appRow(_ app: SideloadedApp) -> some View {
        HStack(spacing: 12) {
            AppIconView(name: app.name, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.subheadline.weight(.medium))
                Text(app.bundleId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if app.isActive {
                StatusChip(title: "JIT", isPositive: true)
            }
        }
    }
}

/// Import sheet — real .ipa file picker (`.fileImporter`) + SigningEngine parsing
/// of Bundle ID / display name / version from the IPA's Info.plist.
struct ImportIPASheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var parsed: SigningEngine.ParsedIPA?
    @State private var errorMessage: String?
    @State private var showAdvanced = false

    private static let ipaTypes: [UTType] = {
        if let ipa = UTType(filenameExtension: "ipa") { return [ipa, .zip] }
        return [.zip]
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                GlassButton(title: localization.t("選擇 .ipa 檔案", "Choose .ipa File", "选择 .ipa 文件")) {
                    errorMessage = nil
                    showFilePicker = true
                }

                if let parsed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localization.t("名稱", "Name", "名称")).font(.caption).foregroundStyle(.secondary)
                        Text(parsed.displayName).font(.subheadline.weight(.medium))
                        Text("Bundle ID").font(.caption).foregroundStyle(.secondary)
                        Text(parsed.bundleId).font(.caption).monospaced()
                        Text("Version").font(.caption).foregroundStyle(.secondary)
                        Text(parsed.shortVersion).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        showAdvanced = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                            Text(localization.t("高級安裝設定", "Advanced Install Settings", "高级安装设置"))
                                .fontWeight(.medium)
                            Spacer()
                            Text(localization.t("變更", "Edit", "编辑"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)

                    GlassButton(title: localization.t("加入清單", "Add", "加入清单")) {
                        switch appState.addApp(name: parsed.displayName,
                                               bundleId: parsed.bundleId,
                                               version: parsed.shortVersion) {
                        case .granted:
                            dismiss()
                        case .noSlotsLeft:
                            errorMessage = localization.t(
                                "Slot 配額已滿（3 個），請先移除一個容器再試",
                                "Slot quota is full (3 apps). Remove a container first",
                                "Slot 配额已满（3 个），请先移除一个容器再试"
                            )
                        case .expired:
                            errorMessage = localization.t(
                                "Slot 配額已過期，請重新簽章以續約 7 天",
                                "Slot quota expired. Re-sign an app to renew for 7 days",
                                "Slot 配额已过期，请重新签章以续约 7 天"
                            )
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(localization.t("匯入 IPA", "Import IPA", "导入 IPA"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("取消", "Cancel", "取消")) { dismiss() }
                }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: Self.ipaTypes,
                          allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error):
                    errorMessage = error.localizedDescription
                case .success(let urls):
                    if let url = urls.first {
                        handleSelection(url)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showAdvanced) {
            AdvancedResignSheet()
        }
    }

    private func handleSelection(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        do {
            let destination = StorageService.downloads.appendingPathComponent("import-\(UUID().uuidString).ipa")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            parsed = try SigningEngine.parse(ipaAt: destination)
            errorMessage = nil
        } catch {
            parsed = nil
            errorMessage = error.localizedDescription
        }
        if didAccess { url.stopAccessingSecurityScopedResource() }
    }
}
