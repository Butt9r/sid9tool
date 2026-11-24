import Foundation

/// Multi-container sandbox management (LiveContainer-style layout).
///
/// v1 scope: container directory lifecycle + manifest persistence + JIT/JIT-less
/// launch policy. Real dyld injection arrives in a later iteration (TODO §5).
final class ContainerManager: ObservableObject {

    @Published private(set) var containers: [ContainerRecord]

    struct ContainerRecord: Identifiable, Codable, Equatable {
        var id: String          // bundleId
        var bundleId: String
        var directory: String
        var jitless: Bool
        var createdAt: Date
        var lastLaunchedAt: Date?
    }

    private let manifestFile = StorageService.documents.appendingPathComponent("containers/manifest.json")

    init() {
        containers = StorageService.load([ContainerRecord].self, from: manifestFile) ?? []
    }

    // MARK: - Container lifecycle

    /// Create (or reuse) the sandbox directory for a bundled app.
    @MainActor
    func ensureContainer(for app: SideloadedApp, jitless: Bool) -> ContainerRecord {
        if let existing = containers.first(where: { $0.bundleId == app.bundleId }) {
            return existing
        }
        let dir = StorageService.containerDirectory(for: app)
        let record = ContainerRecord(
            id: app.bundleId,
            bundleId: app.bundleId,
            directory: dir.path,
            jitless: jitless,
            createdAt: .now,
            lastLaunchedAt: nil
        )
        containers.append(record)
        persist()
        return record
    }

    @MainActor
    func removeContainer(bundleId: String) {
        guard let record = containers.first(where: { $0.bundleId == bundleId }) else { return }
        containers.removeAll { $0.bundleId == bundleId }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: record.directory))
        persist()
    }

    /// Mark a container as launched (v1 bookkeeping only).
    @MainActor
    func markLaunched(bundleId: String) {
        guard let i = containers.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        containers[i].lastLaunchedAt = .now
        persist()
    }

    private func persist() {
        StorageService.save(containers, to: manifestFile)
    }
}
