import Foundation
import Security

/// P1-5: CMS / PKCS#7 signing & verification (pure Security.framework, sandbox-safe).
///
/// - `sign` produces a PKCS#7 SignedData DER blob via `SecCreateSignatureTransform`
///   (works on the iOS 16 SDK; no external `codesign`/`openssl` needed).
/// - `verify` parses the PKCS#7 structure in pure Swift (no `SecContentEncoder` —
///   absent from the iOS SDK) and checks the signature with `SecCreateVerifyTransform`.
///
/// The blob embeds the signing certificate in its `certificates` field, so P1-6
/// can extract it and verify the chain against the provisioning profile.
enum CMS {

    /// PKCS#7 SignedData content type (OID 1.2.840.113549.1.7.2).
    static let signedDataOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]

    /// Sign `content` with `identity` and return a PKCS#7 SignedData DER blob.
    /// `contentType` defaults to `signedDataOID` (the ad-hoc / in-house app case,
    /// where the signed payload is the app bundle).
    static func sign(identity: SecIdentity, cert: SecCertificate, content: Data,
                     contentType: [UInt8] = signedDataOID) throws -> Data {
        var transform: SecTransform?
        let status = SecCreateSignatureTransform(
            identity, cert, contentType as Data, nil, &transform)
        guard status == errSecSuccess, let t = transform else {
            throw CMSError.signFailed(status)
        }
        SecTransformSetAttribute(t, kSecTransformInputAttributeName, content as CFData, nil)
        var result: CFTypeRef?
        let execStatus = SecTransformExecute(t, nil, &result)
        guard execStatus == errSecSuccess, let r = result,
              let out = r as? Data else {
            throw CMSError.signFailed(execStatus)
        }
        return out
    }

    /// Verify a PKCS#7 SignedData blob against `content`.
    /// The certificates are extracted from the blob itself, so no external
    /// trust store is required (sideloading verifies against the profile's
    /// DeveloperCertificates, not the system store).
    static func verify(data: Data, content: Data) -> Bool {
        guard let certs = extractCertificates(from: data), !certs.isEmpty else { return false }
        for cert in certs {
            var transform: SecTransform?
            let status = SecCreateVerifyTransform(
                cert, signedDataOID as Data, &transform)
            guard status == errSecSuccess, let t = transform else { continue }
            SecTransformSetAttribute(t, kSecTransformInputAttributeName, content as CFData, nil)
            var out: CFTypeRef?
            if SecTransformExecute(t, nil, &out) == errSecSuccess { return true }
        }
        return false
    }

    /// Extract the embedded X.509 certificates (DER) from a PKCS#7 SignedData blob.
    /// Pure-Swift ASN.1 walk: ContentInfo → [0] SignedData → [0] certificates.
    static func extractCertificates(from data: Data) -> [Data] {
        let b = [UInt8](data)
        guard let ci = tlv(b, 0), ci.tag == 0x30 else { return [] }
        var off = 0
        // content type OID
        guard let oid = tlv(ci.value, 0), oid.tag == 0x06 else { return [] }
        off = oid.next
        // [0] SignedData (explicit)
        guard let sd = tlv(ci.value, off), sd.tag == 0x0E else { return [] }
        var so = 0
        // version INTEGER
        if let v = tlv(sd.value, 0), v.tag == 0x02 { so = v.next }
        // digestAlgorithms SET
        if let s = tlv(sd.value, so), s.tag == 0x31 { so = s.next }
        // encapContentInfo SEQUENCE
        if let e = tlv(sd.value, so), e.tag == 0x30 { so = e.next }
        // [0] certificates (optional)
        guard let c = tlv(sd.value, so), c.tag == 0xA0 else { return [] }
        var certs: [Data] = []
        var co = 0
        while co < c.value.count {
            guard let cert = tlv(c.value, co), cert.tag == 0x30 else { break }
            certs.append(Data(cert.value))
            co = cert.next
        }
        return certs
    }

    /// Read one DER TLV at `offset` → (tag, value, nextOffset) or nil.
    private static func tlv(_ b: [UInt8], _ offset: Int) -> (tag: Int, value: [UInt8], next: Int)? {
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
    // MARK: - Self-check (runs on the CI macOS runner, see main.swift)
    #if os(macOS)
    /// Returns "" on success, otherwise a human-readable failure report.
    static func selfCheck() -> String {
        // 1. Generate a throwaway RSA-2048 key + self-signed cert for the test.
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var priv: SecKey?
        guard SecKeyCreateRandomKey(keyAttrs as CFDictionary, nil, &priv) == errSecSuccess,
              let privateKey = priv else {
            return "selfCheck: SecKeyCreateRandomKey failed"
        }
        // Subject: X509Name { CN = "sid9tool-selfcheck" } (DER, in-memory only).
        var name = Data()
        let cn = [UInt8]("sid9tool-selfcheck".utf8)
        let atv = [0x55, 0x04, 0x03] + cn                      // AttributeValue
        let atvTLV = [0x30, UInt8(atv.count)] + atv             // SEQUENCE
        let set = [0x31, UInt8(atvTLV.count)] + atvTLV          // SET
        let rdn = [0x30, UInt8(set.count)] + set                // RDN
        name.append(contentsOf: [0x30, UInt8(rdn.count)] + rdn) // X509Name
        let certAttrs: [String: Any] = [
            kSecCertPropertySubject as String: name,
            kSecPrivateKeyAttrs as String: [kSecAttrKeyType as String: kSecAttrKeyTypeRSA]
        ]
        var cert: SecCertificate?
        guard SecCertificateCreateWithProperties(nil, certAttrs as CFDictionary, &cert) == errSecSuccess,
              let certificate = cert else {
            return "selfCheck: SecCertificateCreateWithProperties failed"
        }
        var identity: SecIdentity?
        guard SecIdentityCreate(nil, certificate, privateKey, &identity) == errSecSuccess,
              let id = identity else {
            return "selfCheck: SecIdentityCreate failed"
        }

        let content = Data("sid9tool CMS self-check payload".utf8)
        // 2. Sign.
        do {
            let cms = try sign(identity: id, cert: certificate, content: content)
            // 3. Certificates must be embedded in the blob.
            guard let certs = extractCertificates(from: cms), !certs.isEmpty else {
                return "selfCheck: no certificates embedded in PKCS#7 blob"
            }
            // 4. Verify (positive).
            guard verify(data: cms, content: content) else {
                return "selfCheck: verify failed on matching content"
            }
            // 5. Verify (negative): tampered content must not verify.
            var bad = content
            bad.append(0x00)
            if verify(data: cms, content: bad) {
                return "selfCheck: verify unexpectedly succeeded on tampered content"
            }
        } catch {
            return "selfCheck: sign threw \(error)"
        }
        return ""
    }
    #endif

    enum CMSError: LocalizedError {
        case signFailed(OSStatus)
        var errorDescription: String? {
            switch self {
            case .signFailed(let s): return "CMS sign failed (OSStatus \(s))"
            }
        }
    }
}
