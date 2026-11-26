import SwiftUI
import UniformTypeIdentifiers

/// Guided, PC-free sid9tool self-installation flow (references FrizzleM/SideInstaller).
///
/// Four steps: pairing file → Apple ID certificate (.p12 + .mobileprovision)
/// → optional LocalDevVPN (JIT-less) → re-sign the sid9tool IPA on-device.
struct SelfInstallGuideView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @Environment(\.dismiss) private var dismiss

    /// UserDefaults key: ISO timestamp of the last successful self re-sign.
    static let lastSignedKey = "selfInstall.lastSignedAt"
    static let lastSignedURLKey = "selfInstall.lastSignedIPA"

    @State private var pairingImporter = false
    @State private var certImporter = false
    @State private var ipaImporter = false
    @State private var message: String?

    /// Allowed UTTypes per picker step (iOS 16.0-compatible classic API).
    private static let pairingTypes: [UTType] = {
        var types: [UTType] = []
        if let t = UTType(filenameExtension: "mobiledevicepairing") { types.append(t) }
        if let t = UTType.json { types.append(t) }
        if types.isEmpty { types = [.item] }
        return types
    }()
    private static let certTypes: [UTType] = {
        var types: [UTType] = []
        if let t = UTType(filenameExtension: "p12") { types.append(t) }
        if let t = UTType(filenameExtension: "mobileprovision") { types.append(t) }
        if types.isEmpty { types = [.item] }
        return types
    }()
    private static let ipaTypes: [UTType] = {
        var types: [UTType] = []
        if let t = UTType(filenameExtension: "ipa") { types.append(t) }
        if types.isEmpty { types = [.zip] }
        return types
    }()

    var body: some View {
        NavigationStack {
            List {
                Section(
                    header: Text(localization.t("引導式 PC-free 安裝（參考 FrizzleM/SideInstaller）",
                                                "Guided PC-free install (see FrizzleM/SideInstaller)",
                                                "引导式 PC-free 安装（参考 FrizzleM/SideInstaller）")),
                    footer: Text("github.com/FrizzleM/SideInstaller")
                        .font(.caption2).monospaced().foregroundStyle(.secondary)
                ) {
                    step(1,
                         localization.t("匯入 Pairing 檔案", "Import pairing file", "导入 Pairing 文件"),
                         done: appState.pairing != nil) { pairingImporter = true }
                    step(2,
                         localization.t("匯入 Apple ID 憑證 (.p12 + .mobileprovision)",
                                        "Import Apple ID certificate (.p12 + .mobileprovision)",
                                        "导入 Apple ID 证书 (.p12 + .mobileprovision)"),
                         done: appState.certificate != nil && appState.certificate?.isExpired == false) { certImporter = true }
                    step(3,
                         localization.t("LocalDevVPN（可選，JIT-less）", "LocalDevVPN (optional, JIT-less)", "LocalDevVPN（可选，JIT-less）"),
                         done: !appState.container.jitlessMode || TunnelService.currentStatus(endpoint: appState.container.tunnelEndpoint).vpnConnected) {
                        appState.container.tunnelEnabled = !appState.container.tunnelEnabled
                    }
                    step(4,
                         localization.t("重簽 sid9tool IPA", "Re-sign sid9tool IPA", "重新签章 sid9tool IPA"),
                         done: !(UserDefaults.standard.string(forKey: Self.lastSignedKey) ?? "").isEmpty) { ipaImporter = true }
                }

                if let message {
                    Section {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(localization.t("sid9tool 自身安裝", "sid9tool self-install", "sid9tool 自身安装"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("完成", "Done", "完成")) { dismiss() }
                }
            }
            .fileImporter(isPresented: $pairingImporter,
                          allowedContentTypes: Self.pairingTypes,
                          allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error):
                    message = error.localizedDescription
                case .success(let urls):
                    if let url = urls.first { handlePairing(url) }
                }
            }
            .fileImporter(isPresented: $certImporter,
                          allowedContentTypes: Self.certTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .failure(let error):
                    message = error.localizedDescription
                case .success(let urls):
                    handleCertificates(urls)
                }
            }
            .fileImporter(isPresented: $ipaImporter,
                          allowedContentTypes: Self.ipaTypes,
                          allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error):
                    message = error.localizedDescription
                case .success(let urls):
                    if let url = urls.first { handleSelfIPA(url) }
                }
            }
        }
    }


    /// One checklist row with a state icon + tappable action.
    @ViewBuilder
    private func step(_ index: Int, _ title: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(index).circle")
                    .foregroundStyle(done ? Color.green : .secondary)
                Text(title).font(.subheadline)
                Spacer()
                if !done {
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Handlers

    private func handlePairing(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let profile = PairingService().importPairing(from: url)
        if let profile {
            appState.pairing = profile
            message = localization.t("Pairing 已就緒", "Pairing ready", "Pairing 已就绪")
        } else {
            message = localization.t("Pairing 匯入失敗", "Pairing import failed", "Pairing 导入失败")
        }
    }

    private func handleCertificates(_ urls: [URL]) {
        let service = CertificateService()
        var profile: CertificateProfile?
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            profile = service.importFile(url) ?? profile
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        if let profile {
            appState.certificate = profile
            message = localization.t("憑證已匯入", "Certificate imported", "证书已导入")
        } else {
            message = localization.t("需要 .p12 與 .mobileprovision 各一個",
                                     "Need one .p12 and one .mobileprovision",
                                     "需要一个 .p12 和一个 .mobileprovision")
        }
    }

    private func handleSelfIPA(_ url: URL) {
        guard let certificate = appState.certificate, !certificate.p12FileName.isEmpty else {
            message = localization.t("請先完成 Pairing 與憑證", "Finish pairing & certificate first", "请先完成 Pairing 与证书")
            return
        }
        Task { @MainActor in
            do {
                let certDir = CertificateService.directory
                guard let p12 = try? FileManager.default.contentsOfDirectory(atPath: certDir.path).first(where: { $0.hasSuffix(".p12") }),
                      let prov = try? FileManager.default.contentsOfDirectory(atPath: certDir.path).first(where: { $0.hasSuffix(".mobileprovision") })
                else {
                    message = localization.t("缺少 .p12 或 .mobileprovision", "Missing .p12 or .mobileprovision", "缺少 .p12 或 .mobileprovision")
                    return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                let parsed = try SigningEngine.parse(ipaAt: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
                let request = SigningEngine.SignRequest(
                    parsedIPA: parsed,
                    entitlements: SigningEngine.buildEntitlements(bundleId: parsed.bundleId, teamID: certificate.teamID),
                    p12URL: certDir.appendingPathComponent(p12),
                    provisioningURL: certDir.appendingPathComponent(prov),
                    bundleIdOverride: appState.container.bundleIdOverride,
                    stripDebugEntitlement: appState.container.stripDebugEntitlement
                )
                let result = try SigningEngine.sign(request)
                let iso = ISO8601DateFormatter()
                UserDefaults.standard.set(iso.string(from: Date()), forKey: Self.lastSignedKey)
                UserDefaults.standard.set(result.outputPath.path, forKey: Self.lastSignedURLKey)
                message = localization.t("sid9tool 重簽完成：\(result.outputPath.lastPathComponent)",
                                         "sid9tool re-signed: \(result.outputPath.lastPathComponent)",
                                         "sid9tool 重新签章完成：\(result.outputPath.lastPathComponent)")
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
