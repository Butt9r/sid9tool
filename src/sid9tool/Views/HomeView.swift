import SwiftUI

/// Home tab — actionable status cards & quick setup status.
struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @State private var showImportSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    slotCard
                    setupCard
                    containerCard
                    quickActions
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(localization.t("首頁", "Home", "首页"))
            .sheet(isPresented: $showImportSheet) {
                ImportIPASheet()
            }
        }
    }

    private var slotCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: localization.t("簽名配額", "Signing Slots", "签名配额"), systemImage: "cube.box.fill")
                HStack {
                    ForEach(0..<appState.slot.totalSlots, id: \.self) { i in
                        Image(systemName: i < appState.slot.occupiedSlots ? "cube.fill" : "cube")
                            .foregroundStyle(i < appState.slot.occupiedSlots ? Color.accentColor : .secondary)
                    }
                    Spacer()
                    if let expiresAt = appState.slot.expiresAt {
                        Text(localization.t(
                            "剩餘 \(max(0, Int(expiresAt.timeIntervalSinceNow / 86400))) 天",
                            "\(max(0, Int(expiresAt.timeIntervalSinceNow / 86400)))d left",
                            "剩余 \(max(0, Int(expiresAt.timeIntervalSinceNow / 86400))) 天"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var setupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: localization.t("環境狀態", "Environment", "环境状态"), systemImage: "checklist")
                HStack(spacing: 8) {
                    StatusChip(title: localization.t("Pairing \(appState.pairing == nil ? "未匯入" : "已就緒")",
                               "Pairing \(appState.pairing == nil ? "missing" : "ready")",
                               "Pairing \(appState.pairing == nil ? "未导入" : "已就绪")"),
                               isPositive: appState.pairing != nil)
                    StatusChip(title: localization.t("憑證 \(appState.certificate == nil ? "未匯入" : appState.certificate?.isExpired == true ? "過期" : "有效")",
                               "Cert \(appState.certificate == nil ? "missing" : appState.certificate?.isExpired == true ? "expired" : "valid")",
                               "证书 \(appState.certificate == nil ? "未导入" : appState.certificate?.isExpired == true ? "过期" : "有效")"),
                               isPositive: appState.certificate != nil && appState.certificate?.isExpired == false)
                }
            }
        }
    }

    private var containerCard: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.t("容器模式", "Container Mode", "容器模式"))
                        .font(.headline)
                    Text(appState.container.jitlessMode
                         ? localization.t("JIT-less 已啟用", "JIT-less enabled", "JIT-less 已启用")
                         : localization.t("JIT 已啟用", "JIT enabled", "JIT 已启用"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $appState.container.jitlessMode)
                    .labelsHidden()
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            GlassButton(title: localization.t("匯入 IPA", "Import IPA", "导入 IPA"),
                        systemImage: "square.and.arrow.down") {
                showImportSheet = true
            }
            GlassButton(title: localization.t("重新簽章", "Re-sign", "重新签章"),
                        systemImage: "arrow.triangle.2.circlepath") {
                // Re-sign pipeline via SigningEngine (v1 stub)
            }
        }
    }
}
