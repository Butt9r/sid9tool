import Foundation

// MARK: - Container App (unlimited list, drag-reorderable, persisted)

struct SideloadedApp: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bundleId: String
    var iconTint: Int // simple placeholder tint index
    var installedAt: Date
    var lastSignatureAt: Date?
    var signatureExpiresAt: Date?
    var isActive: Bool
}

// MARK: - Slot model (free account: 3 signed apps)

struct SlotUsage: Codable, Equatable {
    var totalSlots: Int = 3
    var occupiedSlots: Int
    var expiresAt: Date?
}

// MARK: - Featured feed (remote JSON schema)

struct FeaturedFeed: Codable, Equatable {
    var version: Int
    var updatedAt: Date?
    var apps: [FeaturedApp]
}

struct FeaturedApp: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bundleId: String
    var iconUrl: URL?
    var ipaUrl: URL?
    var description: String
    var tags: [String]
    var addedAt: Date?
}

// MARK: - Pairing (mobiledevicepairing / RPPairing)

struct PairingProfile: Codable, Equatable {
    var importedFileName: String
    var importedAt: Date
    var fileSize: Int64
    var isRP: Bool // true = RPPairing, false = .mobiledevicepairing
    var deviceUDID: String?
    var isTrusted: Bool
}

// MARK: - Certificates (.p12 + .mobileprovision)

struct CertificateProfile: Codable, Equatable {
    var p12FileName: String
    var p12ImportedAt: Date
    var provisionFileName: String?
    var provisionImportedAt: Date?
    var teamName: String?
    var teamID: String?
    var appID: String?
    var notBefore: Date?
    var expirationDate: Date?
    var provisioningContents: Data?

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var daysUntilExpiry: Int? {
        guard let expirationDate else { return nil }
        return max(0, Int(ceil(expirationDate.timeIntervalSince(Date) / 86400)))
    }
}

// MARK: - Container / JIT settings

struct ContainerSettings: Codable, Equatable {
    var jitlessMode: Bool = true
    var localDevVPN: Bool = false
    var tunnelEnabled: Bool = false
    var tunnelEndpoint: String = ""
}

// MARK: - Storage sections

enum StorageSection: String, CaseIterable {
    case downloads = "downloads"
    case containers = "containers"
    case cache = "cache"
}