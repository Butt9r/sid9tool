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
            .background(Color(.systemGroupedBackground))
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var localization: LocalizationService
    @State private var installing = false
    @State private var statusMessage: String?

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
                            installFromFeed()
                        } label: {
                            if installing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title3)
                            }
                        }
                        .disabled(installing)
                        .accessibilityLabel(localization.t("安裝", "Install", "安装"))
                    }
                }
                Text(app.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    /// Download the IPA from the feed, parse it with SigningEngine (Bundle ID /
    /// name / version from Info.plist), and add it to the container list.
    private func installFromFeed() {
        guard let remote = app.ipaUrl, !installing else { return }
        installing = true
        statusMessage = localization.t("下載中…", "Downloading…", "下载中…")
        Task {
            do {
                let dest = StorageService.downloads.appendingPathComponent("featured-\(UUID().uuidString).ipa")
                let (tempURL, _) = try await URLSession.shared.download(from: remote)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                statusMessage = localization.t("解析中…", "Parsing…", "解析中…")
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try SigningEngine.parse(ipaAt: dest)
                }.value
                await MainActor.run {
                    appState.addApp(name: parsed.displayName,
                                    bundleId: parsed.bundleId,
                                    version: parsed.shortVersion)
                    statusMessage = localization.t("已加入清單", "Added to list", "已加入清单")
                    installing = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    installing = false
                }
            }
        }
    }
}
