import SwiftUI

/// Featured tab — remote JSON feed with cache / builtin fallback banner.
struct FeaturedView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @StateObject private var feedService = FeaturedFeedService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if feedService.status != .live {
                        fallbackBanner
                    }
                    ForEach(feedService.feed.apps) { app in
                        FeaturedCard(app: app)
                    }
                }
                .padding()
            }
            .background(.background.secondary)
            .navigationTitle(localization.t("精選", "Featured", "精选"))
            .refreshable {
                await feedService.refresh(feedURL: appState.feedURL)
            }
            .task {
                await feedService.refresh(feedURL: appState.feedURL)
            }
        }
    }

    private var fallbackBanner: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                Text(localization.t(
                    "離線模式：顯示本地快取 / 內建清單",
                    "Offline: showing cached / builtin list",
                    "离线模式：显示本地缓存 / 内建清单"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct FeaturedCard: View {
    let app: FeaturedApp
    @EnvironmentObject var localization: LocalizationService

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AppIconView(name: app.name, url: app.iconUrl, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.headline)
                        Text(app.bundleId)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if app.ipaUrl != nil {
                        Button {
                            // v1: deep-link install flow handled by SigningEngine later
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title3)
                        }
                        .accessibilityLabel(localization.t("安裝", "Install", "安装"))
                    }
                }
                Text(app.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(app.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            }
        }
    }
}
