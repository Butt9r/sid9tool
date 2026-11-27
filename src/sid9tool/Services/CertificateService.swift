import Foundation
import Security
import CryptoKit

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
    /// store the identity in the Keychain, and return a display name + the leaf
    /// certificate DER (for P1-2 matching against the profile).
    /// The password is used in memory only — it is never written to disk,
    /// UserDefaults or the Keychain.
    func importP12(at url: URL, password: String) throws -> (certName: String, certData: Data?, identity: SecIdentity) {
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
        let typeSafe = items as! [AnyObject]
        for item in typeSafe {
            if identity == nil && CFGetTypeID(item) == SecIdentityGetTypeID() {
                identity = item as! SecIdentity
            } else if CFGetTypeID(item) == SecCertificateGetTypeID() {
                cert = item as! SecCertificate
            }
        }
        guard let identity, let cert else { throw P12ImportError.noIdentity }

        // SecPKCS12Import already stored the identity in the default keychain.
        // CN is parsed from SecCertificateCopyData (DER X.509) — pure Swift,
        // because SecCertificateCopyName / CopyValues / CopySubjectAttributes
        // are all absent from the iOS SDK (see TODO.md 已試過 list).
        var certData: Data?
        var certName = ""
        let raw = SecCertificateCopyData(cert) as Data
        certData = raw
        certName = Self.parseCommonName(der: raw)
            ?? raw.sha256Fingerprint16()
        return (certName, certData, identity)
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
                // P1-2: keep the profile's developer cert set + device list for matching.
                profile.developerCertificates = (fields["DeveloperCertificates"] as? [Data])
                profile.provisionedDevices = (fields["ProvisionedDevices"] as? [String])
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

    // MARK: - P1-1: pure-Swift X.509 DER helpers (no SecCertificateCopy* CF API)

    /// Read one DER TLV at `offset`; returns (tag, value, nextOffset) or nil.
    private static func derTLV(_ b: [UInt8], _ offset: Int) -> (tag: Int, value: [UInt8], next: Int)? {
        guard offset + 2 <= b.count else { return nil }
        let tag = Int(b[offset])
        var len = Int(b[offset + 1])
        var p = offset + 2
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n > 0, p + n <= b.count else { return nil }
            len = 0
            for i in 0..<n { len = (len << 8) | Int(b[p + i]) }
            p += n
        }
        guard p + len <= b.count else { return nil }
        return (tag, Array(b[p..<(p + len)]), p + len)
    }

    private static func derString(_ tag: Int, _ b: [UInt8]) -> String? {
        switch tag {
        case 0x13, 0x16, 0x1A: return String(data: Data(b), encoding: .ascii)
        case 0x0C: return String(data: Data(b), encoding: .utf8)
        default: return String(data: Data(b), encoding: .utf8)
        }
    }

    /// Extract the Subject Common Name (OID 2.5.4.3) from X.509 DER.
    /// Returns nil if the structure is malformed or has no CN.
    static func parseCommonName(der: Data) -> String? {
        let b = [UInt8](der)
        guard let cert = derTLV(b, 0), cert.tag == 0x30 else { return nil }
        guard let tbs = derTLV(cert.value, 0), tbs.tag == 0x30 else { return nil }
        var off = 0
        if let first = derTLV(tbs.value, 0), first.tag == 0xA0 { off = first.next }
        guard let serial = derTLV(tbs.value, off), serial.tag == 0x02 else { return nil }
        off = serial.next
        guard let sig = derTLV(tbs.value, off), sig.tag == 0x30 else { return nil }
        off = sig.next
        guard let issuer = derTLV(tbs.value, off), issuer.tag == 0x30 else { return nil }
        off = issuer.next
        guard let subject = derTLV(tbs.value, off), subject.tag == 0x30 else { return nil }
        let cnOID: [UInt8] = [0x55, 0x04, 0x03]
        var so = 0
        while so < subject.value.count {
            guard let rdn = derTLV(subject.value, so), rdn.tag == 0x30 else { break }
            so = rdn.next
            var ro = 0
            while ro < rdn.value.count {
                guard let set = derTLV(rdn.value, ro), set.tag == 0x31 else { break }
                ro = set.next
                var ao = 0
                while ao < set.value.count {
                    guard let atv = derTLV(set.value, ao), atv.tag == 0x30 else { break }
                    ao = atv.next
                    guard let oid = derTLV(atv.value, 0) else { break }
                    if oid.value == cnOID, let v = derTLV(atv.value, oid.next) {
                        if let s = derString(v.tag, v.value), !s.isEmpty { return s }
                    }
                }
            }
        }
        return nil
    }
}

extension Data {
    /// First 16 hex chars of the SHA-256 digest — a stable, short display
    /// fallback when the certificate has no parseable Common Name.
    func sha256Fingerprint16() -> String {
        let h = SHA256.hash(data: self)
        return h.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
