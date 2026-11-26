import SwiftUI

/// First-run PC-free onboarding (5 pages, references FrizzleM/SideInstaller flow).
/// Page 5: Terms & Privacy consent (checkboxes) + 3-language switch (pill).
/// Consent flags persist to UserDefaults; `>` links open the GitHub LICENSE / PRIVACY.md.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @Environment(\.openURL) private var openURL

    @State private var page = 0
    @State private var agreedTerms = false
    @State private var agreedPrivacy = false

    private let termsURL = URL(string: "https://github.com/Butt9r/sid9tool/blob/main/LICENSE")!
    private let privacyURL = URL(string: "https://github.com/Butt9r/sid9tool/blob/main/docs/PRIVACY.md")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    pairingPage.tag(1)
                    certificatePage.tag(2)
                    signPage.tag(3)
                    consentPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))

                controls
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .tabBar)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 10) {
            Spacer()
            AppIconView(name: "sid9tool", size: 72)
            Text("sid9tool")
                .font(.largeTitle.bold())
            Text(localization.t(
                "免電腦 Side-loading，一機完成 Pairing、簽章與安裝",
                "PC-free sideloading — pairing, signing and install all on-device",
                "免电脑 Side-loading，一机完成 Pairing、签章与安装"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }

    private func stepPage(_ number: Int,
                          title: String, enTitle: String, hansTitle: String,
                          detail: String, enDetail: String, hansDetail: String,
                          icon: String) -> some View {
        VStack {
            Spacer()
            GlassCard {
                HStack(spacing: 12) {
                    Text("\(number)")
                        .font(.headline.bold())
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.tint.opacity(0.25)))
                    VStack(alignment: .leading, spacing: 4) {
                        Label(localization.t(title, enTitle, hansTitle), systemImage: icon)
                            .font(.headline)
                        Text(localization.t(detail, enDetail, hansDetail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding()
    }

    private var pairingPage: some View {
        stepPage(1,
                 title: "匯入 Pairing", enTitle: "Import Pairing", hansTitle: "导入 Pairing",
                 detail: "由 SideInstaller 匯入 RPPairing 檔案並信任",
                 enDetail: "Import the RPPairing file from SideInstaller and trust it",
                 hansDetail: "由 SideInstaller 导入 RPPairing 文件并信任",
                 icon: "link.badge.plus")
    }

    private var certificatePage: some View {
        stepPage(2,
                 title: "匯入憑證", enTitle: "Import Certificates", hansTitle: "导入凭证",
                 detail: ".p12 + .mobileprovision，自動檢查到期日",
                 enDetail: ".p12 + .mobileprovision, expiry checked automatically",
                 hansDetail: ".p12 + .mobileprovision，自动检查到期日",
                 icon: "checkmark.shield.fill")
    }

    private var signPage: some View {
        stepPage(3,
                 title: "簽章安裝", enTitle: "Sign & Install", hansTitle: "签章安装",
                 detail: "免費帳號 3 個 slot 配額，JIT-less 容器啟動",
                 enDetail: "Free account 3-slot quota, JIT-less container launch",
                 hansDetail: "免费账号 3 个 slot 配额，JIT-less 容器启动",
                 icon: "cube.box.fill")
    }

    private var consentPage: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.t("條款與隱私", "Terms & Privacy", "条款与隐私"))
                        .font(.headline)
                    Label {
                        Text(localization.t(
                            "使用 sid9tool 即表示你同意使用條款（含 LiveContainer / SideInstaller 授權說明）。",
                            "By using sid9tool you agree to the terms (including LiveContainer / SideInstaller attribution).",
                            "使用 sid9tool 即表示你同意使用条款（含 LiveContainer / SideInstaller 授权说明）。"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.tint)
                    }
                    consentToggle(
                        text: localization.t("我已閱讀並同意《使用條款》",
                                             "I have read and agree to the Terms",
                                             "我已阅读并同意《使用条款》"),
                        isOn: $agreedTerms
                    ) {
                        openURL(termsURL)
                    }
                    consentToggle(
                        text: localization.t("我已閱讀並同意《隱私政策》",
                                             "I have read and agree to the Privacy Policy",
                                             "我已阅读并同意《隐私政策》"),
                        isOn: $agreedPrivacy
                    ) {
                        openURL(privacyURL)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    private func consentToggle(text: String, isOn: Binding<Bool>, linkAction: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: isOn) {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.button)
            .tint(.primary)
            Button {
                linkAction()
            } label: {
                Label(localization.t("更多", "More", "更多"), systemImage: "chevron.right.circle.fill")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Controls (language pill + navigation)

    private var controls: some View {
        VStack(spacing: 10) {
            languagePill
            if page < 4 {
                HStack {
                    Button(localization.t("上一步", "Back", "上一步")) { page = max(0, page - 1) }
                        .disabled(page == 0)
                    Spacer()
                    Button(localization.t("下一步", "Next", "下一步")) {
                        page += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                GlassButton(
                    title: localization.t("開始使用", "Get Started", "开始使用"),
                    systemImage: "checkmark.circle.fill"
                ) {
                    UserDefaults.standard.set(agreedTerms, forKey: "agreedTerms")
                    UserDefaults.standard.set(agreedPrivacy, forKey: "agreedPrivacy")
                    appState.onboardingCompleted = true
                }
                .disabled(!agreedTerms || !agreedPrivacy)
            }
        }
    }

    private var languagePill: some View {
        HStack(spacing: 6) {
            ForEach(AppLanguage.allCases) { lang in
                Button(lang.displayName) {
                    localization.language = lang
                }
                .font(.caption.weight(localization.language == lang ? .bold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(localization.language == lang
                                  ? Color.accentColor.opacity(0.25)
                                  : Color(.secondarySystemFill))
                )
            }
        }
    }
}
