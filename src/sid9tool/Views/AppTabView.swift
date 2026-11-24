import SwiftUI

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
            .background(.background.secondary)
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

/// Minimal import sheet (v1: name + Bundle ID, real IPA picker in next iteration).
struct ImportIPASheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bundleId = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField(localization.t("App 名稱", "App Name", "App 名称"), text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Bundle ID", text: $bundleId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                GlassButton(title: localization.t("加入清單", "Add", "加入清单")) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appState.addApp(name: trimmed, bundleId: bundleId.isEmpty ? trimmed : bundleId)
                    }
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .navigationTitle(localization.t("匯入 IPA", "Import IPA", "导入 IPA"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("取消", "Cancel", "取消")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
