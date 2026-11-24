import SwiftUI

/// Root switch: onboarding (first run) → 4-tab Liquid Glass shell.
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService

    var body: some View {
        if appState.onboardingCompleted {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var localization: LocalizationService

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(localization.t("首頁", "Home", "首页"), systemImage: "house.fill")
                }
            AppTabView()
                .tabItem {
                    Label("App", systemImage: "app.badge.fill")
                }
            FeaturedView()
                .tabItem {
                    Label(localization.t("精選", "Featured", "精选"), systemImage: "sparkles")
                }
            SettingsView()
                .tabItem {
                    Label(localization.t("設定", "Settings", "设置"), systemImage: "gearshape.fill")
                }
        }
    }
}
