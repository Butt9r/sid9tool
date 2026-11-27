import SwiftUI
import UniformTypeIdentifiers

/// Settings tab — pairing / certificates / container / VPN / storage / language / About.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @State private var storage: [StorageService.SectionUsage] = StorageService.scanUsage()
    @State private var showPairingPicker = false
    @State private var showP12Picker = false
    @State private var showProvisionPicker = false
    @State private var certNote: String?

    private static let pairingTypes: [UTType] = {
        var types: [UTType] = []
        if let pairing = UTType(filenameExtension: "mobiledevicepairing") { types.append(pairing) }
        if let json = UTType(filenameExtension: "json") { types.append(json) }
        if types.isEmpty { types = [.item] }
        return types
    }()
    private static var p12Type: UTType? { UTType(filenameExtension: "p12") }
    private static var provisionType: UTType? { UTType(filenameExtension: "mobileprovision") }

    var body: some View {
        NavigationStack {
            List {
                pairingSection
                certificateSection
                containerSection
                advancedSignSection
                vpnSection
                storageSection
                languageSection
                aboutSection
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(localization.t("設定", "Settings", "设置"))
            .fileImporter(isPresented: $showPairingPicker,
                          allowedContentTypes: Self.pairingTypes,
                          allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error):
                    certNote = error.localizedDescription
                case .success(let urls):
                    if let url = urls.first {
                        appState.pairing = PairingService().importPairing(from: url)
                    }
                }
            }
            .fileImporter(isPresented: $showP12Picker,
                          allowedContentTypes: [Self.p12Type].compactMap { $0 },
                          allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error):
                    certNote = error.localizedDescription
                case .success(let urls):
                    if let url = urls.first { handleCertificateFile(url) }
                }
            }
            .fileImporter(isPresented: $showProvisionPicker,
                          allowedContentTypes: [Self.provisionType].compactMap { $0 },
                          allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error):
                    certNote = error.localizedDescription
                case .success(let urls):
                    if let url = urls.first { handleCertificateFile(url) }
                }
            }
        }
    }

    private func handleCertificateFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        let profile = CertificateService().importFile(url)
        if didAccess { url.stopAccessingSecurityScopedResource() }
        if let profile {
            appState.certificate = profile
            certNote = localization.t(".p12 + .mobileprovision 匯入完成",
                                      ".p12 + .mobileprovision imported",
                                      ".p12 + .mobileprovision 导入完成")
        } else {
            certNote = localization.t("已存入。請同時匯入 .p12 與 .mobileprovision",
                                      "Stored. Import both .p12 and .mobileprovision",
                                      "已存入。请同时导入 .p12 与 .mobileprovision")
        }
    }

    private var pairingSection: some View {
        Section {
            HStack {
                Label(localization.t("Pairing \(appState.pairing == nil ? "未匯入" : (appState.pairing?.isTrusted == true ? "已匯入" : "格式無法辨識"))",
                        "Pairing \(appState.pairing == nil ? "not imported" : (appState.pairing?.isTrusted == true ? "imported" : "unrecognized"))",
                        "Pairing \(appState.pairing == nil ? "未导入" : (appState.pairing?.isTrusted == true ? "已导入" : "格式无法识别"))"),
                        systemImage: "person.crop.circle.badge.checkmark")
                Spacer()
                if let pairing = appState.pairing {
                    Button(localization.t("移除", "Remove", "移除"), role: .destructive) {
                        appState.pairing = nil
                        PairingService().reset()
                    }
                    .font(.caption)
                }
            }
            if let udid = appState.pairing?.deviceUDID {
                LabeledContent("UDID", value: udid).font(.caption)
            }
            Button {
                showPairingPicker = true
            } label: {
                Label(localization.t("匯入 Pairing 檔", "Import Pairing File", "导入配对文件"), systemImage: "square.and.arrow.down")
            }
        } header: {
            Text(localization.t("配對檔案", "Pairing", "配对文件"))
        }
    }

    private var certificateSection: some View {
        Section {
            if let cert = appState.certificate {
                LabeledContent("Team", value: cert.teamName ?? "-")
                LabeledContent("App ID", value: cert.appID ?? "-")
                if let expiry = cert.expirationDate {
                    LabeledContent(localization.t("過期日", "Expires", "过期日"),
                                   value: expiry.formatted(date: .abbreviated, time: .omitted))
                }
                Button(localization.t("移除憑證", "Remove Certificates", "移除证书"), role: .destructive) {
                    appState.certificate = nil
                }
            } else {
                Text(localization.t("尚未匯入 .p12 / .mobileprovision",
                                   "No .p12 / .mobileprovision imported",
                                   "尚未导入 .p12 / .mobileprovision"))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(localization.t("匯入 .p12", "Import .p12", "导入 .p12")) { showP12Picker = true }
                Button(localization.t("匯入 .mobileprovision", "Import .mobileprovision", "导入 .mobileprovision")) { showProvisionPicker = true }
            }
            .font(.caption)
            if let certNote {
                Text(certNote).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(localization.t("憑證", "Certificates", "证书"))
        }
    }

    private var containerSection: some View {
        Section {
            Toggle(localization.t("JIT-less 模式 (LocalDevVPN)", "JIT-less mode (LocalDevVPN)", "JIT-less 模式 (LocalDevVPN)"),
                   isOn: $appState.container.jitlessMode)
            Toggle(localization.t("啟用隧道", "Enable tunnel", "启用隧道"), isOn: $appState.container.tunnelEnabled)
        } header: {
            Text(localization.t("容器", "Containers", "容器"))
        }
    }

    private var advancedSignSection: some View {
        Section {
            // P0-3: ResignAdvanced.customBundleID is the single source of truth.
            TextField(localization.t("自訂 Bundle ID（留空=原樣）",
                                    "Custom Bundle ID (empty = original)",
                                    "自定义 Bundle ID（留空=原样）"),
                      text: $appState.advanced.customBundleID)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Toggle(localization.t("移除 get-task-allow 除錯權限",
                                 "Strip get-task-allow debug entitlement",
                                 "移除 get-task-allow 调试权限"),
                   isOn: $appState.container.stripDebugEntitlement)
        } header: {
            Text(localization.t("重簽進階設定", "Advanced re-sign settings", "重签高级设置"))
        } footer: {
            Text(localization.t("自訂 Bundle ID 需被 .mobileprovision 的 App ID 涵蓋；自簽名免費帳號建議使用萬用 * App ID。",
                              "A custom Bundle ID must be covered by the profile's App ID; use a wildcard * App ID for free self-signed profiles.",
                              "自定义 Bundle ID 需被 .mobileprovision 的 App ID 涵盖；自签名免费账号建议通配 * App ID。"))
        }
    }

    private var vpnSection: some View {
        Section {
            TextField("Tunnel URL", text: $appState.container.tunnelEndpoint)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task {
                    let ok = await TunnelService.probe(endpoint: appState.container.tunnelEndpoint)
                    appState.container.tunnelEnabled = ok
                }
            } label: {
                Label(localization.t("偵測 VPN", "Detect VPN", "检测 VPN"), systemImage: "antenna.radiowaves.left.and.right")
            }
            LabeledContent(localization.t("隧道狀態", "Tunnel", "隧道状态"), value: appState.container.tunnelEnabled
                           ? localization.t("已連線", "connected", "已连接")
                           : localization.t("未偵測到", "not detected", "未检测到"))
        } header: {
            Text("VPN / Tunnel")
        }
    }

    private var storageSection: some View {
        Section {
            ForEach(storage, id: \.section) { item in
                LabeledContent(
                    item.section == .downloads ? "Downloads" :
                    item.section == .containers ? "Containers" : "Cache",
                    value: item.formatted
                )
            }
            Button(localization.t("清空快取", "Clear Cache", "清空缓存"), role: .destructive) {
                StorageService.clearSection(.cache)
                storage = StorageService.scanUsage()
            }
        } header: {
            Text(localization.t("儲存空間", "Storage", "存储空间"))
        }
    }

    private var languageSection: some View {
        Section {
            Picker(localization.t("語言", "Language", "语言"), selection: $localization.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
            Link(destination: URL(string: "https://github.com/Butt9r/sid9tool")!) {
                Label("GitHub — Butt9r/sid9tool", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            LabeledContent(localization.t("上游致敬", "Upstream", "上游致敬"),
                           value: "LiveContainer / FrizzleM SideInstaller")
        } header: {
            Text(localization.t("關於", "About", "关于"))
        }
    }
}
