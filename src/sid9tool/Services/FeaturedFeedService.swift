import Foundation

enum FeedStatus: Equatable {
    case live
    case cached(Date?)
    case builtin
}

/// Featured tab data source: remote JSON → local cache → builtin sample.
final class FeaturedFeedService: ObservableObject {
    @Published private(set) var feed: FeaturedFeed
    @Published private(set) var status: FeedStatus

    static let cacheFile = "featured-feed-cache.json"

    init(initialFeed: FeaturedFeed = Self.builtinSample()) {
        self.feed = initialFeed
        self.status = .builtin
    }

    static var cacheURL: URL {
        StorageService.cache.appendingPathComponent(Self.cacheFile)
    }

    /// Load best-available data immediately (cache or builtin).
    static func loadLocal() -> (FeaturedFeed, FeedStatus) {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? decode(data) {
            let mtime = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (cached, .cached(mtime))
        }
        return (builtinSample(), .builtin)
    }

    /// Fetch the remote feed. Falls back to cache / builtin on failure.
    @MainActor
    func refresh(feedURL: String) async {
        guard let url = URL(string: feedURL), url.scheme?.hasPrefix("http") == true else {
            status = .builtin
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fresh = try decode(data)
            try? data.write(to: cacheURL, options: .atomic)
            feed = fresh
            status = .live
        } catch {
            // Keep current feed; mark fallback status.
            let (local, s) = Self.loadLocal()
            feed = local
            status = s
        }
    }

    private static func decode(_ data: Data) throws -> FeaturedFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FeaturedFeed.self, from: data)
    }

    /// Builtin sample used when offline and no cache exists.
    static func builtinSample() -> FeaturedFeed {
        FeaturedFeed(
            version: 1,
            updatedAt: .now,
            apps: [
                FeaturedApp(id: "featured-1",
                            name: "LiveContainer",
                            bundleId: "dev.livecontainer.app",
                            iconUrl: nil,
                            ipaUrl: URL(string: "https://example.invalid/LiveContainer.ipa"),
                            description: "Run iOS apps without actually installing them — containers, multi-version data, JIT-less signing.",
                            tags: ["container", "launcher"],
                            addedAt: .now),
                FeaturedApp(id: "featured-2",
                            name: "SideInstaller",
                            bundleId: "dev.frizzle.sideinstaller",
                            iconUrl: nil,
                            ipaUrl: URL(string: "https://example.invalid/SideInstaller.ipa"),
                            description: "PC-free sideloading: pair once, sign and install fully on-device.",
                            tags: ["sideloading", "pc-free"],
                            addedAt: .now)
            ]
        )
    }
}