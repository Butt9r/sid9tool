import Foundation
import Security

/// Certificate (.p12 + .mobileprovision) import & expiry parsing.
final class CertificateService {
    static var directory: URL {
        let u = StorageService.documents.appendingPathComponent("certificates", isDirectory: true)
        StorageService.ensureDirectory(u)
        return u
    }

    /// Store a .p12 or .mobileprovision file; when both are present, build & return the profile.
    @MainActor
    func importFile(_ sourceURL: URL) -> CertificateProfile? {
        let name = sourceURL.lastPathComponent
        do {
            let destURL = Self.directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            return nil
        }
        let p12File = try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
            .first { $0.hasSuffix(".p12") }
        let provisionFile = try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
            .first { $0.hasSuffix(".mobileprovision") }
        guard let p12File, let provisionFile else { return nil }
        return importCertificates(
            p12URL: Self.directory.appendingPathComponent(p12File),
            provisionURL: Self.directory.appendingPathComponent(provisionFile)
        )
    }

    /// Import a .p12 + .mobileprovision pair; returns a parsed profile.
    @MainActor
    func importCertificates(p12URL: URL, provisionURL: URL?) -> CertificateProfile? {
        var profile = CertificateProfile(
            p12FileName: p12URL.lastPathComponent,
            p12ImportedAt: .now,
            provisionFileName: provisionURL?.lastPathComponent,
            provisionImportedAt: provisionURL.map { _ in Date() },
            teamName: nil, teamID: nil, appID: nil,
            notBefore: nil, expirationDate: nil,
            provisioningContents: nil
        )
        if let provisionURL {
            if let (data, fields) = parseProvision(provisionURL) {
                profile.provisioningContents = data
                profile.teamName = fields["TeamName"] as? String
                profile.teamID = fields["TeamIdentifier"].flatMap { ($0 as? [String])?.first }
                profile.appID = (fields["Entitlements"] as? [String: Any])?["application-identifier"] as? String
                    ?? fields["ProvisionedDevices"] != nil ? "explicit" : nil
                if let nb = fields["NotBefore"] as? Date { profile.notBefore = nb }
                if let exp = fields["ExpirationDate"] as? Date { profile.expirationDate = exp }
            }
        }
        return profile
    }

    /// Parse a .mobileprovision (DER-wrapped or plain XML plist) into basic fields.
    private func parseProvision(_ url: URL) -> (Data, [String: Any])? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Try plist directly first (plain XML provisioning file).
        if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return (data, dict)
        }
        // DER-wrapped profile: carve out the embedded <plist>…</plist> XML and parse it.
        let bytes = [UInt8](data)
        let startMarker = [UInt8]("<plist".utf8)
        guard let start = bytes.indices.dropLast(startMarker.count)
            .first(where: { Array(bytes[$0..<$0 + startMarker.count]) == startMarker })
        else { return nil }
        let tail = Array(bytes.suffix(from: start))
        let endMarker = [UInt8]("</plist>".utf8)
        guard let endOffset = tail.indices.dropLast(endMarker.count)
            .first(where: { Array(tail[$0..<$0 + endMarker.count]) == endMarker })
        else { return nil }
        let xml = Data(tail.prefix(through: endOffset + endMarker.count - 1))
        guard let dict = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any]
        else { return nil }
        return (data, dict)
    }
}
