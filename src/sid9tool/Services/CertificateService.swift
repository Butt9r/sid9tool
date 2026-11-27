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

    // MARK: - P1-1: password-protected .p12 import (SecPKCS12Import)

    enum P12ImportError: LocalizedError, Equatable {
        case fileNotFound
        case badPassword
        case noIdentity

        /// Localized description (zh-Hant / en / zh-Hans) based on the persisted language.
        var errorDescription: String? {
            let saved = UserDefaults.standard.string(forKey: LocalizationService.storageKey)
            let lang = saved.flatMap { AppLanguage(rawValue: $0) } ?? .zhHant
            switch self {
            case .fileNotFound:
                return Self.t(lang, "找不到檔案", "File not found", "找不到文件")
            case .badPassword:
                return Self.t(lang, ".p12 密碼錯誤", "Wrong .p12 password", ".p12 密码错误")
            case .noIdentity:
                return Self.t(lang, "該 .p12 沒有簽章身分", "No signing identity in .p12", "该 .p12 没有签名身份")
            }
        }

        private static func t(_ lang: AppLanguage, _ zhHant: String, _ en: String, _ zhHans: String) -> String {
            switch lang {
            case .zhHant: return zhHant
            case .en: return en
            case .zhHans: return zhHans
            }
        }
    }

    /// Import a password-protected .p12, extract the SecIdentity + SecCertificate,
    /// store the identity in the Keychain, and return the certificate Common Name.
    /// The password is used in memory only — it is never written to disk,
    /// UserDefaults or the Keychain.
    func importP12(at url: URL, password: String) throws -> (certName: String, identity: SecIdentity) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw P12ImportError.fileNotFound }

        let options: [CFString: Any] = [kSecImportExportPassphrase: password as CFString]

        var result: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &result)
        guard status == errSecSuccess, let items = result else {
            throw P12ImportError.badPassword
        }

        var identity: SecIdentity?
        var cert: SecCertificate?
        for item in items as! [AnyObject] {
            if identity == nil, let id = item as? SecIdentity {
                identity = id
            } else if let c = item as? SecCertificate {
                cert = c
            }
        }
        guard let identity, let cert else { throw P12ImportError.noIdentity }

        // SecPKCS12Import already stored the identity in the default keychain.
        var certName = ""
        if let attrs = SecCertificateCopySubjectAttributes(cert, .all) {
            let dict = attrs as? [CFString: Any]
            if let cn = dict?[kSecAttrCommonName] as? String {
                certName = cn
            }
        }
        return (certName, identity)
    }

    /// Import a .p12 + .mobileprovision pair; returns a parsed profile.
    @MainActor
    func importCertificates(p12URL: URL, provisionURL: URL?) -> CertificateProfile? {
        var profile = CertificateProfile(
            p12FileName: p12URL.lastPathComponent,
            p12ImportedAt: .now,
            certCommonName: nil,
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
