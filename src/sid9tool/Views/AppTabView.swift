import SwiftUI
import UniformTypeIdentifiers

/// App tab — 3-slot quota header + unlimited reorderable container list.
struct AppTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @State private var importing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    slotHeader
                    listSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
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
            }
            .sheet(isPresented: $importing) {
                ImportIPASheet()
            }
        }
    }

    private var slotHeader: some View {
        GlassCard {
            HStack {
                Label(localization.t(
                    "已用 \(appState.slot.occupiedSlots)/\(appState.slot.totalSlots) slot",
                    "Slots \(appState.slot.occupiedSlots)/\(appState.slot.totalSlots)",
                    "已用 \(appState.slot.occupiedSlots)/\(appState.slot.totalSlots) slot"
                ), systemImage: "cube.box.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
        }
    }

    private var listSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: localization.t("容器清單", "Containers", "容器清单"), systemImage: "tray.full.fill")
                if appState.apps.isEmpty {
                    Text(localization.t("尚未簽名任何 App", "No signed apps yet", "尚未签名任何 App"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.apps) { app in
                        AppRow(app: app)
                        if app.id != appState.apps.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct AppRow: View {
    let app: SideloadedApp
    @EnvironmentObject var localization: LocalizationService

    var body: some View {
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

                    GlassButton(title: localization.t("加入清單", "Add", "加入清单")) {
                        appState.addApp(name: parsed.displayName,
                                        bundleId: parsed.bundleId,
                                        version: parsed.shortVersion)
                        dismiss()
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
                case .success(let url):
                    handleSelection(url)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
