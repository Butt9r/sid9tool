import Foundation
import Security

/// Certificate (.p12 + .mobileprovision) import & expiry parsing.
final class CertificateService {

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

    /// Parse a .mobileprovision (DER or XML plist) into basic fields.
    private func parseProvision(_ url: URL) -> (Data, [String: Any])? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Try plist directly first.
        if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return (data, dict)
        }
        // DER provisioning profile: use SecCMServerLoadContents (returns [dicts]).
        guard let contents = SecCMServerLoadContents(data as CFData, nil) as? [[String: Any]] else {
            return nil
        }
        return (data, contents.first ?? [:])
    }
}
