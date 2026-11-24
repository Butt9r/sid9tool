import Foundation

/// Filesystem + persistence layer inside the App Sandbox.
///
/// Directory layout:
///   Documents/downloads   – imported / downloaded IPA files
///   Documents/containers  – per-app container sandboxes (unlimited)
///   Documents/cache       – featured feed cache, icons, temp files
final class StorageService: ObservableObject {

    // MARK: - Paths

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var downloads: URL {
        let u = documents.appendingPathComponent("downloads", isDirectory: true)
        ensureDirectory(u)
        return u
    }

    static var containers: URL {
        let u = documents.appendingPathComponent("containers", isDirectory: true)
        ensureDirectory(u)
        return u
    }

    static var cache: URL {
        let u = documents.appendingPathComponent("cache", isDirectory: true)
        ensureDirectory(u)
        return u
    }

    static var settingsFile: URL {
        documents.appendingPathComponent("sid9tool-settings.json")
    }

    static func containerDirectory(for app: SideloadedApp) -> URL {
        let u = containers.appendingPathComponent(app.bundleId, isDirectory: true)
        ensureDirectory(u)
        return u
    }

    // MARK: - Size scanning

    static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
        }
        return total
    }

    struct SectionUsage: Equatable {
        let section: StorageSection
        let bytes: Int64
        var formatted: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    static func scanUsage() -> [SectionUsage] {
        [
            SectionUsage(section: .downloads, bytes: directorySize(downloads)),
            SectionUsage(section: .containers, bytes: directorySize(containers)),
            SectionUsage(section: .cache, bytes: directorySize(cache))
        ]
    }

    // MARK: - Cleanup

    static func clearSection(_ section: StorageSection) {
        let target: URL
        switch section {
        case .downloads: target = downloads
        case .containers: target = containers
        case .cache: target = cache
        }
        for item in (try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }

    static func clearAll() {
        clearSection(.downloads)
        clearSection(.cache)
        clearSection(.containers)
    }

    // MARK: - Settings persistence (single JSON blob)

    static func save<T: Encodable>(_ value: T, to file: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            try data.write(to: file, options: .atomic)
        } catch {
            print("[StorageService] save failed: \(error)")
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    // MARK: - Helpers

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func humanBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}