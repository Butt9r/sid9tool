import Foundation

/// Built-in local signing core (v1 architecture).
///
/// Real work implemented now:
///  - IPA structure parsing (Payload/<Bundle>.app discovery, Info.plist read, Bundle ID extract)
///  - Entitlements pipeline (generate .entitlements from Bundle ID + provisioning Team ID)
///  - `.mobileprovision` parsing (embedded plist: Team Name/ID, App ID, validity dates)
///  - `.p12` custody (stored in sandbox; password held by user at sign time)
///
/// Iteration roadmap (see TODO.md): link the zsign / native codesign binary backend
/// to complete the actual re-sign + inject pipeline on-device.
final class SigningEngine: ObservableObject {

    // MARK: - Errors

    enum EngineError: LocalizedError {
        case invalidIPA(String)
        case plistMissing
        case provisionInvalid
        case signingBackendUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidIPA(let reason):
                return "Invalid IPA: \(reason)"
            case .plistMissing:
                return "Payload/<App>.app/Info.plist not found in the IPA."
            case .provisionInvalid:
                return "The .mobileprovision file could not be parsed."
            case .signingBackendUnavailable:
                return "Local signing backend (zsign) is not linked yet — see TODO.md iteration plan."
            }
        }
    }

    // MARK: - IPA parsing

    struct ParsedIPA {
        let sourceURL: URL
        let workDir: URL
        let appBundleURL: URL
        let bundleId: String
        let displayName: String
        let shortVersion: String
    }

    /// Unzip the IPA into the downloads work area and locate Payload/<App>.app.
    @discardableResult
    static func parse(ipaAt url: URL) throws -> ParsedIPA {
        let workDir = StorageService.downloads.appendingPathComponent("parse-\(UUID().uuidString)", isDirectory: true)
        StorageService.ensureDirectory(workDir)

        let unzipDest = workDir.appendingPathComponent("unzipped", isDirectory: true)
        StorageService.ensureDirectory(unzipDest)

        do {
            let archive = Archive(url: url, readOnly: true)
            try archive.extract(to: unzipDest)
        } catch {
            throw EngineError.invalidIPA("unzip failed: \(error.localizedDescription)")
        }

        let fm = FileManager.default
        guard let payloadDir = fm.contentsOfDirectory(at: unzipDest, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.caseInsensitiveCompare("Payload") == .orderedSame })
            else { throw EngineError.invalidIPA("no Payload/ directory") }

        guard let appBundle = fm.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
            else { throw EngineError.invalidIPA("no .app bundle inside Payload/") }

        guard let plistURL = appBundle.appendingPathComponent("Info.plist"),
              let info = try? PropertyListSerialization.data(fromPropertyListAt: plistURL, options: [], format: nil),
              let dict = try? PropertyListSerialization.propertyList(from: info, options: [], format: nil) as? [String: Any]
        else { throw EngineError.plistMissing }

        let bundleId = (dict["CFBundleIdentifier"] as? String) ?? "unknown.bundle.id"
        let displayName = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String) ?? bundleId
        let shortVersion = (dict["CFBundleShortVersionString"] as? String) ?? "0"

        return ParsedIPA(sourceURL: url,
                         workDir: workDir,
                         appBundleURL: appBundle,
                         bundleId: bundleId,
                         displayName: displayName,
                         shortVersion: shortVersion)
    }

    // MARK: - Entitlements pipeline

    /// Build the .entitlements payload for a target Bundle ID under a Team ID.
    static func buildEntitlements(bundleId: String, teamID: String?) -> [String: Any] {
        var entitlements: [String: Any] = [
            "application-identifier": (teamID ?? "XXXXXXXXXX") + "." + bundleId,
            "keychain-access-groups": [teamID.map { $0 + "." + bundleId } ?? ["*"]],
            "aps-environment": "development",
            "get-task-allow": true
        ]
        if let teamID {
            entitlements["com.apple.developer.team-identifier"] = teamID
        }
        return entitlements
    }

    /// Serialize entitlements to a .entitlements file inside the work dir.
    static func writeEntitlements(_ entitlements: [String: Any], into dir: URL) -> URL? {
        let url = dir.appendingPathComponent("sid9tool.entitlements")
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entitlements,
                                                             format: .openStep,
                                                             options: 0) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Provisioning profile parsing

    /// Extract the embedded XML plist from a .mobileprovision (DER-wrapped) file.
    static func parseProvisioningProfile(at url: URL) throws -> [String: Any] {
        guard let raw = try? Data(contentsOf: url) else { throw EngineError.provisionInvalid }
        let bytes = [UInt8](raw)
        let marker = [UInt8]("<plist".utf8)
        guard let start = bytes.indices.dropLast(marker.count)
            .first(where: { Array(bytes[$0..<$0 + marker.count]) == marker })
        else { throw EngineError.provisionInvalid }
        let tail = Data(bytes.suffix(from: start))
        let endMarker = Data("</plist>".utf8)
        guard let endRange = tail.range(of: endMarker) else { throw EngineError.provisionInvalid }
        let end = tail.index(endRange.lowerBound, offsetBy: endMarker.count)
        let plistData = tail.subdata(in: tail.startIndex..<end)
        guard let dict = try? PropertyListSerialization.propertyList(from: plistData,
                                                                     options: [],
                                                                     format: nil) as? [String: Any]
        else { throw EngineError.provisionInvalid }
        return dict
    }

    /// Parse a profile into the app-facing certificate model.
    @discardableResult
    static func importProvisioning(_ profile: [String: Any], fileName: String, importedAt: Date, existingP12: (fileName: String, importedAt: Date)?) -> CertificateProfile {
        func date(_ key: String) -> Date? {
            profile[key] as? Date
        }
        return CertificateProfile(
            p12FileName: existingP12?.fileName ?? "",
            p12ImportedAt: existingP12?.importedAt ?? importedAt,
            provisionFileName: fileName,
            provisionImportedAt: importedAt,
            teamName: profile["Name"] as? String,
            teamID: (profile["TeamIdentifier"] as? [String])?.first,
            appID: (profile["Entitlements"] as? [String: Any])?["application-identifier"] as? String,
            notBefore: date("ExpirationDate") != nil ? date("CreationDate") : nil,
            expirationDate: date("ExpirationDate"),
            provisioningContents: nil
        )
    }

    // MARK: - Signing pipeline (v1 boundary)

    struct SignRequest {
        let parsedIPA: ParsedIPA
        let entitlements: [String: Any]
        let p12URL: URL
        let provisioningURL: URL
    }

    struct SignResult {
        let outputPath: URL
        let bundleId: String
        let signedAt: Date
    }

    /// v1: validates the pipeline inputs; the actual re-sign binary backend
    /// (zsign) lands in the next iteration (see TODO.md).
    static func sign(_ request: SignRequest) throws -> SignResult {
        guard FileManager.default.fileExists(atPath: request.p12URL.path) else {
            throw EngineError.signingBackendUnavailable
        }
        guard FileManager.default.fileExists(atPath: request.parsedIPA.appBundleURL.path) else {
            throw EngineError.signingBackendUnavailable
        }
        _ = writeEntitlements(request.entitlements, into: request.parsedIPA.workDir)
        throw EngineError.signingBackendUnavailable
    }
}