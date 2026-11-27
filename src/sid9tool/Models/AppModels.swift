import Foundation

// MARK: - Container App (unlimited list, drag-reorderable, persisted)

struct SideloadedApp: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bundleId: String
    var version: String // CFBundleShortVersionString from the IPA's Info.plist
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
    /// P1-1: Common Name of the .p12 signing certificate (display only).
    var certCommonName: String?
    var provisionFileName: String?
    var provisionImportedAt: Date?
    var teamName: String?
    var teamID: String?
    var appID: String?
    var notBefore: Date?
    var expirationDate: Date?
    var provisioningContents: Data?
    /// P1-2: DER data of every cert in the profile's `DeveloperCertificates`.
    var developerCertificates: [Data]?
    /// P1-2: raw `ProvisionedDevices` entries (UDIDs or device IDs); nil = all-devices profile.
    var provisionedDevices: [String]?

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var daysUntilExpiry: Int? {
        guard let expirationDate else { return nil }
        return max(0, Int(ceil(expirationDate.timeIntervalSince(Date()) / 86400)))
    }
}

// MARK: - Container / JIT settings

struct ContainerSettings: Codable, Equatable {
    var jitlessMode: Bool = true
    var localDevVPN: Bool = false
    var tunnelEnabled: Bool = false
    var tunnelEndpoint: String = ""
    /// LEGACY (P0-3): kept only for backward-compatible decoding of old
    /// persisted data. Single source of truth is `ResignAdvanced.customBundleID`;
    /// `AppState.init` migrates a non-empty value there once, then clears this.
    var bundleIdOverride: String = ""
    /// Advanced re-sign: strip Apple's get-task-allow debug entitlement.
    var stripDebugEntitlement: Bool = true

    init() {}

    /// Tolerant decode: missing keys (older persisted data) fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jitlessMode = try c.decodeIfPresent(Bool.self, forKey: .jitlessMode) ?? true
        localDevVPN = try c.decodeIfPresent(Bool.self, forKey: .localDevVPN) ?? false
        tunnelEnabled = try c.decodeIfPresent(Bool.self, forKey: .tunnelEnabled) ?? false
        tunnelEndpoint = try c.decodeIfPresent(String.self, forKey: .tunnelEndpoint) ?? ""
        bundleIdOverride = try c.decodeIfPresent(String.self, forKey: .bundleIdOverride) ?? ""
        stripDebugEntitlement = try c.decodeIfPresent(Bool.self, forKey: .stripDebugEntitlement) ?? true
    }
}

// MARK: - Advanced resign settings (AltStore-style, v2 Step 3/4)

struct ResignAdvanced: Codable, Equatable {
    // 一般
    var supportOlderIOS7: Bool = false
    var removeDeviceLimitation: Bool = false
    var enableFileSharing: Bool = false
    var removeAppExtensions: Bool = false
    // 進階 Bundle ID
    var changeAppName: Bool = false
    var newAppName: String = ""
    var changeAppVersion: Bool = false
    var newAppVersion: String = ""
    var useAutomaticBundleID: Bool = false
    var customBundleID: String = ""
    var useCustomEntitlements: Bool = false
    var customEntitlementsJSON: String = ""
    // Tweak Injection
    var injectDylibs: [String] = []
    var injectFrameworks: [String] = []
    var cydiaSubstrate: Bool = false
    var substitute: Bool = false
    var sideloadSpoofer: Bool = false
    // Info.plist 進階
    var plistFields: [PlistFieldEdit] = []

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        supportOlderIOS7 = try c.decodeIfPresent(Bool.self, forKey: .supportOlderIOS7) ?? false
        removeDeviceLimitation = try c.decodeIfPresent(Bool.self, forKey: .removeDeviceLimitation) ?? false
        enableFileSharing = try c.decodeIfPresent(Bool.self, forKey: .enableFileSharing) ?? false
        removeAppExtensions = try c.decodeIfPresent(Bool.self, forKey: .removeAppExtensions) ?? false
        changeAppName = try c.decodeIfPresent(Bool.self, forKey: .changeAppName) ?? false
        newAppName = try c.decodeIfPresent(String.self, forKey: .newAppName) ?? ""
        changeAppVersion = try c.decodeIfPresent(Bool.self, forKey: .changeAppVersion) ?? false
        newAppVersion = try c.decodeIfPresent(String.self, forKey: .newAppVersion) ?? ""
        useAutomaticBundleID = try c.decodeIfPresent(Bool.self, forKey: .useAutomaticBundleID) ?? false
        customBundleID = try c.decodeIfPresent(String.self, forKey: .customBundleID) ?? ""
        useCustomEntitlements = try c.decodeIfPresent(Bool.self, forKey: .useCustomEntitlements) ?? false
        customEntitlementsJSON = try c.decodeIfPresent(String.self, forKey: .customEntitlementsJSON) ?? ""
        injectDylibs = try c.decodeIfPresent([String].self, forKey: .injectDylibs) ?? []
        injectFrameworks = try c.decodeIfPresent([String].self, forKey: .injectFrameworks) ?? []
        cydiaSubstrate = try c.decodeIfPresent(Bool.self, forKey: .cydiaSubstrate) ?? false
        substitute = try c.decodeIfPresent(Bool.self, forKey: .substitute) ?? false
        sideloadSpoofer = try c.decodeIfPresent(Bool.self, forKey: .sideloadSpoofer) ?? false
        plistFields = try c.decodeIfPresent([PlistFieldEdit].self, forKey: .plistFields) ?? []
    }
}

struct PlistFieldEdit: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var key: String
    var value: String // JSON-ish scalar (string/bool/int) applied to Info.plist
}

// MARK: - Storage sections

enum StorageSection: String, CaseIterable {
    case downloads = "downloads"
    case containers = "containers"
    case cache = "cache"
}