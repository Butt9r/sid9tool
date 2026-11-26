import SwiftUI

/// Home tab — actionable status cards & quick setup status.
struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @State private var showImportSheet = false
    @State private var showSelfInstall = false
    @AppStorage(SelfInstallGuideView.lastSignedKey) private var lastSignedAt = ""

    /// sid9tool 自身安裝的 4 步就緒狀態（Pairing / 憑證 / VPN / 重簽）。
    private var installSteps: [(String, Bool)] {
        let vpn = TunnelService.currentStatus(endpoint: appState.container.tunnelEndpoint)
        let certOK = appState.certificate != nil && appState.certificate?.isExpired == false
        return [
            (localization.t("Pairing 檔案", "Pairing file", "Pairing 文件"), appState.pairing != nil),
            (localization.t("Apple ID + 憑證", "Apple ID + certificate", "Apple ID + 证书"), certOK),
            (localization.t("LocalDevVPN (JIT-less)", "LocalDevVPN (JIT-less)", "LocalDevVPN (JIT-less)"),
             !appState.container.jitlessMode || vpn.vpnConnected),
            (localization.t("sid9tool 重簽完成", "sid9tool re-signed", "sid9tool 重新签章完成"), !lastSignedAt.isEmpty)
        ]
    }

    /// 憑證狀態文字（供卡片用）。
    private var certTitle: String {
        if appState.certificate == nil { return "未匯入" }
        return appState.certificate?.isExpired == true ? "過期" : "有效"
    }
    private var certTitleEN: String {
        if appState.certificate == nil { return "missing" }
        return appState.certificate?.isExpired == true ? "expired" : "valid"
    }
    private var certTitleHans: String {
        if appState.certificate == nil { return "未导入" }
        return appState.certificate?.isExpired == true ? "过期" : "有效"
    }
    /// Pairing 狀態文字（供卡片用）。
    private var pairingStatus: String { appState.pairing == nil ? "未匯入" : "已就緒" }
    private var pairingStatusEN: String { appState.pairing == nil ? "missing" : "ready" }
    private var pairingStatusHans: String { appState.pairing == nil ? "未导入" : "已就绪" }
    /// 憑證到期天數。
    private var certDays: Int { appState.certificate?.daysUntilExpiry ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    pairingCard
                    certificateCard
                    vpnCard
                    selfInstallCard
                    slotCard
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
            .sheet(isPresented: $showSelfInstall) {
                SelfInstallGuideView()
            }
        }
    }

    // MARK: - Status cards

    private var pairingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Pairing", systemImage: "link")
                HStack(spacing: 8) {
                    StatusChip(title: localization.t("Pairing \(appState.pairing == nil ? "未匯入" : "已就緒")",
                               "Pairing \(appState.pairing == nil ? "missing" : "ready")",
                               "Pairing \(appState.pairing == nil ? "未导入" : "已就绪")"),
                               isPositive: appState.pairing != nil)
                    if let udid = appState.pairing?.deviceUDID {
                        Text(udid.prefix(12))
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
                if let name = appState.pairing?.importedFileName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var certificateCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: localization.t("Apple ID + 憑證", "Apple ID + Certificate", "Apple ID + 证书"),
                              systemImage: "person.crop.circle.badge.checkmark")
                HStack(spacing: 8) {
                    StatusChip(title: localization.t("憑證 \(certTitle)",
                               "Cert \(certTitleEN)",
                               "证书 \(certTitleHans)"),
                               isPositive: appState.certificate != nil && appState.certificate?.isExpired == false)
                    if let days = appState.certificate?.daysUntilExpiry {
                        Text(localization.t("到期 \(days) 天", "\(days)d to expire", "到期 \(days) 天"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let team = appState.certificate?.teamName {
                    Text(team)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var vpnCard: some View {
        let status = TunnelService.currentStatus(endpoint: appState.container.tunnelEndpoint)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "LocalDevVPN", systemImage: "network")
                HStack(spacing: 8) {
                    StatusChip(title: status.vpnConnected
                               ? localization.t("VPN Tunnel 已連線", "VPN tunnel up", "VPN Tunnel 已连接")
                               : localization.t("VPN Tunnel 未偵測到", "No VPN tunnel detected", "未检测到 VPN Tunnel"),
                               isPositive: status.vpnConnected)
                    if !appState.container.tunnelEndpoint.isEmpty {
                        Text(appState.container.tunnelEndpoint)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 10) {
                    Toggle(localization.t("JIT-less 模式", "JIT-less mode", "JIT-less 模式"), isOn: $appState.container.jitlessMode)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if appState.container.jitlessMode {
                        TextField("VPN endpoint (e.g. 127.0.0.1:port)",
                                  text: $appState.container.tunnelEndpoint)
                            .font(.caption2)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(maxWidth: 220)
                    }
                }
            }
        }
    }

    private var selfInstallCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: localization.t("sid9tool 自身安裝", "sid9tool self-install", "sid9tool 自身安装"),
                              systemImage: "hammer")
                VStack(spacing: 6) {
                    ForEach(installSteps, id: \.0) { step in
                        HStack(spacing: 8) {
                            Image(systemName: step.1 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.1 ? Color.green : .secondary)
                                .font(.caption)
                            Text(step.0).font(.caption)
                        }
                    }
                }
                GlassButton(title: localization.t("開始引導式安裝", "Start guided install", "开始引导式安装"),
                            systemImage: "arrow.right.circle") {
                    showSelfInstall = true
                }
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
                showSelfInstall = true
            }
        }
    }
}
