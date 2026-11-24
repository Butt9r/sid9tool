import Foundation
import Combine

struct AppStateSnapshot: Codable, Equatable {
    var apps: [SideloadedApp]
    var slot: SlotUsage
    var pairing: PairingProfile?
    var certificate: CertificateProfile?
    var container: ContainerSettings
    var feedURL: String
    var onboardingCompleted: Bool
}

/// Single source of truth for the app, persisted to the App Sandbox.
final class AppState: ObservableObject {

    private struct Keys: RawRepresentable {
        let rawValue: String
        static let apps = Self(rawValue: "apps")
        static let slot = Self(rawValue: "slot")
        static let pairing = Self(rawValue: "pairing")
        static let certificate = Self(rawValue: "certificate")
        static let container = Self(rawValue: "container")
        static let feedURL = Self(rawValue: "feedURL")
        static let onboarding = Self(rawValue: "onboardingCompleted")
    }

    @Published var apps: [SideloadedApp] { didSet { persist() } }
    @Published var slot: SlotUsage { didSet { persist() } }
    @Published var pairing: PairingProfile? { didSet { persist() } }
    @Published var certificate: CertificateProfile? { didSet { persist() } }
    @Published var container: ContainerSettings { didSet { persist() } }
    @Published var feedURL: String { didSet { persist() } }
    @Published var onboardingCompleted: Bool { didSet { persist() } }

    static let defaultFeedURL = "https://raw.githubusercontent.com/Butt9r/sid9tool/main/featured.json"

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        apps = (try? decoder.decode([SideloadedApp].self, from: Self.decodeData(Keys.apps))) ?? Self.sampleApps()
        slot = (try? decoder.decode(SlotUsage.self, from: Self.decodeData(Keys.slot)))
            ?? SlotUsage(occupiedSlots: 1, expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()))
        pairing = try? decoder.decode(PairingProfile.self, from: Self.decodeData(Keys.pairing))
        certificate = try? decoder.decode(CertificateProfile.self, from: Self.decodeData(Keys.certificate))
        container = (try? decoder.decode(ContainerSettings.self, from: Self.decodeData(Keys.container))) ?? ContainerSettings()
        feedURL = UserDefaults.standard.string(forKey: Keys.feedURL.rawValue) ?? Self.defaultFeedURL
        onboardingCompleted = UserDefaults.standard.bool(forKey: Keys.onboarding.rawValue)
    }

    // MARK: - App list operations

    func addApp(name: String, bundleId: String) {
        let app = SideloadedApp(
            id: UUID().uuidString,
            name: name,
            bundleId: bundleId,
            iconTint: Int.random(in: 0..<12),
            installedAt: Date(),
            lastSignatureAt: Date(),
            signatureExpiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            isActive: true
        )
        apps.append(app)
        if slot.occupiedSlots < slot.totalSlots { slot.occupiedSlots += 1 }
    }

    func removeApp(_ app: SideloadedApp) {
        apps.removeAll { $0.id == app.id }
        if slot.occupiedSlots > 1 { slot.occupiedSlots -= 1 }
    }

    func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    private static func decodeData(_ key: Keys) -> Data {
        (try? Data(contentsOf: StorageService.documents.appendingPathComponent("\(key.rawValue).json"))) ?? Data()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func write<T: Encodable>(_ value: T, _ key: Keys) {
            if let data = try? encoder.encode(value) {
                let url = StorageService.documents.appendingPathComponent("\(key.rawValue).json")
                try? data.write(to: url, options: .atomic)
            }
        }
        write(apps, Keys.apps)
        write(slot, Keys.slot)
        if let pairing { write(pairing, Keys.pairing) }
        if let certificate { write(certificate, Keys.certificate) }
        write(container, Keys.container)
        UserDefaults.standard.set(feedURL, forKey: Keys.feedURL.rawValue)
        UserDefaults.standard.set(onboardingCompleted, forKey: Keys.onboarding.rawValue)
    }

    // MARK: - Sample data

    private static func sampleApps() -> [SideloadedApp] {
        [
            SideloadedApp(id: "demo-1",
                           name: "LiveContainer",
                           bundleId: "dev.livecontainer.app",
                           iconTint: 2,
                           installedAt: .now,
                           lastSignatureAt: .now,
                           signatureExpiresAt: Calendar.current.date(byAdding: .day, value: 6, to: Date()),
                           isActive: true),
            SideloadedApp(id: "demo-2",
                           name: "FileX",
                           bundleId: "com.filex.app",
                           iconTint: 5,
                           installedAt: .now,
                           lastSignatureAt: .now,
                           signatureExpiresAt: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
                           isActive: false)
        ]
    }
}