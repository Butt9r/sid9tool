import SwiftUI

/// First-run PC-free onboarding (references FrizzleM/SideInstaller flow).
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    stepCards
                    GlassButton(
                        title: localization.t("開始使用", "Get Started", "开始使用"),
                        systemImage: "checkmark.circle.fill"
                    ) {
                        appState.onboardingCompleted = true
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .tabBar)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
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
        }
        .padding(.top, 24)
    }

    private var stepCards: some View {
        VStack(spacing: 12) {
            OnboardingStepCard(number: 1,
                               title: localization.t("匯入 Pairing", "Import Pairing", "导入 Pairing"),
                               detail: localization.t("由 SideInstaller 匯入 RPPairing 檔案並信任", "Import the RPPairing file from SideInstaller and trust it", "由 SideInstaller 导入 RPPairing 文件并信任"),
                               icon: "link.badge.plus")
            OnboardingStepCard(number: 2,
                               title: localization.t("匯入憑證", "Import Certificates", "导入凭证"),
                               detail: localization.t(".p12 + .mobileprovision，自動檢查到期日", ".p12 + .mobileprovision, expiry checked automatically", ".p12 + .mobileprovision，自动检查到期日"),
                               icon: "checkmark.shield.fill")
            OnboardingStepCard(number: 3,
                               title: localization.t("簽章安裝", "Sign & Install", "签章安装"),
                               detail: localization.t("免費帳號 3 個 slot 配額，JIT-less 容器啟動", "Free account 3-slot quota, JIT-less container launch", "免费账号 3 个 slot 配额，JIT-less 容器启动"),
                               icon: "cube.box.fill")
        }
    }
}

struct OnboardingStepCard: View {
    let number: Int
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.headline.bold())
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.tint.opacity(0.25)))
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: icon)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
