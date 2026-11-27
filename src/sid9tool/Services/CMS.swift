import Foundation
import Security
import CryptoKit

/// P1-5: CMS / PKCS#7 signing & verification (pure Swift + Security.framework).
///
/// - `sign` uses `SecKeyCreateSignature` (RSA PKCS#1 v1.5 SHA-256) and
///   manually constructs a CMS SignedData DER blob (RFC 5652).
/// - `verify` parses the PKCS#7 structure in pure Swift and checks the
///   signature with `SecKeyVerifySignature`.
///
/// The blob embeds the signing certificate in its `certificates` field, so P1-6
/// can extract it and verify the chain against the provisioning profile.
enum CMS {

    // MARK: - OIDs
    static let oidSignedData: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
    static let oidData: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]
    static let oidSHA256: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    static let oidRSA: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    static let oidEContentType: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x03]
    static let oidMessageDigest: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04]

    /// Sign `content` with `identity` and return a CMS SignedData DER blob (RFC 5652).
    static func sign(identity: SecIdentity, cert: SecCertificate, content: Data,
                     contentType: [UInt8] = oidData) throws -> Data {
        var privKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privKey) == errSecSuccess,
              let key = privKey else { throw CMSError.signFailed(errSecAuthFailed) }
        let certDER = SecCertificateCopyData(cert)
        let cb = [UInt8](certDER as Data)
        guard let outer = tlv(cb, 0), outer.tag == 0x30,
              let tbs = tlv(outer.value, 0), tbs.tag == 0x30 else {
            throw CMSError.signFailed(errSecInternalComponent)
        }
        var off = 0
        if let v = tlv(tbs.value, off), v.tag == 0xA0 { off = v.next }
        guard let serial = tlv(tbs.value, off), serial.tag == 0x02 else {
            throw CMSError.signFailed(errSecInternalComponent)
        }
        off = serial.next
        if let sa = tlv(tbs.value, off), sa.tag == 0x30 { off = sa.next }
        guard let issuer = tlv(tbs.value, off), issuer.tag == 0x30 else {
            throw CMSError.signFailed(errSecInternalComponent)
        }
        let hash = [UInt8](SHA256.hash(data: content))
        let attr1 = derSeq(derOID(oidEContentType) + derSet(derOID(contentType)))
        let attr2 = derSeq(derOID(oidMessageDigest) + derSet(derOctetString(hash)))
        let attrsContent = attr1 + attr2
        let signedAttrsEnc = derTLV(0xA0, attrsContent)
        var err: Unmanaged<CFError>?
        guard let sigData = SecKeyCreateSignature(key, .rsaSignatureDigestPKCS1v15SHA256,
                                                  Data(signedAttrsEnc) as CFData, &err) else {
            throw CMSError.signFailed(errSecInternalComponent)
        }
        let signature = sigData as Data
        let digestAlg = derSeq(derOID(oidSHA256) + derNull())
        let sigAlg = derSeq(derOID(oidRSA) + derNull())
        let ias = derSeq(derSeq(issuer.value) + derInteger(serial.value))
        let siContent = derInteger([0x01]) + ias + digestAlg + signedAttrsEnc + sigAlg
            + derOctetString([UInt8](signature))
        let signerInfo = derSeq(siContent)
        let signerInfos = derSet(signerInfo)
        let digestAlgs = derSet(digestAlg)
        let eci = derSeq(derOID(oidData) + derTLV(0xA0, [UInt8](content)))
        let certsField = derTLV(0xA0, cb)
        let sdContent = derInteger([0x01]) + digestAlgs + eci + certsField + signerInfos
        let sd = derTLV(0xA0, sdContent)
        return Data(derSeq(derOID(oidSignedData) + sd))
    }

    /// Verify a CMS SignedData blob against `content`.
    /// Certificates are extracted from the blob; signature checked via `SecKeyVerifySignature`.
    static func verify(data: Data, content: Data) -> Bool {
        let b = [UInt8](data)
        guard let ci = tlv(b, 0), ci.tag == 0x30 else { return false }
        var off = 0
        guard let oid = tlv(ci.value, 0), oid.tag == 0x06 else { return false }
        off = oid.next
        guard let sdTLV = tlv(ci.value, off), sdTLV.tag == 0xA0 else { return false }
        var so = 0
        if let v = tlv(sdTLV.value, so), v.tag == 0x02 { so = v.next }
        if let s = tlv(sdTLV.value, so), s.tag == 0x31 { so = s.next }
        guard let eci = tlv(sdTLV.value, so), eci.tag == 0x30 else { return false }
        so = eci.next
        // Parse eContent from encapContentInfo
        var eo = 0
        if let eoid = tlv(eci.value, eo), eoid.tag == 0x06 { eo = eoid.next }
        guard let eContent = tlv(eci.value, eo), eContent.tag == 0xA0 else { return false }
        guard Data(eContent.value) == content else { return false }
        // certificates
        guard let certsTLV = tlv(sdTLV.value, so), certsTLV.tag == 0xA0 else { return false }
        so = certsTLV.next
        // signerInfos SET
        guard let siSet = tlv(sdTLV.value, so), siSet.tag == 0x31 else { return false }
        guard let si = tlv(siSet.value, 0), si.tag == 0x30 else { return false }
        // Parse SignerInfo: version, ias, digestAlg, signedAttrs, sigAlg, signature
        var io = 0
        if let iv = tlv(si.value, io), iv.tag == 0x02 { io = iv.next }
        if let ias = tlv(si.value, io), ias.tag == 0x30 { io = ias.next }
        if let da = tlv(si.value, io), da.tag == 0x30 { io = da.next }
        guard let sa = tlv(si.value, io), sa.tag == 0xA0 else { return false }
        io = sa.next
        if let alg = tlv(si.value, io), alg.tag == 0x30 { io = alg.next }
        guard let sig = tlv(si.value, io), sig.tag == 0x04 else { return false }
        // Rebuild signedAttrs for verification
        let hash = [UInt8](SHA256.hash(data: content))
        let attr1 = derSeq(derOID(oidEContentType) + derSet(derOID(oidData)))
        let attr2 = derSeq(derOID(oidMessageDigest) + derSet(derOctetString(hash)))
        let signedAttrsEnc = derTLV(0xA0, attr1 + attr2)
        // Get public key from embedded cert
        let certs = extractCertificates(from: data)
        guard !certs.isEmpty else { return false }
        for certDER in certs {
            guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else { continue }
            guard let pubKey = SecCertificateCopyKey(cert) else { continue }
            let ok = SecKeyVerifySignature(pubKey, .rsaSignatureDigestPKCS1v15SHA256,
                                           Data(signedAttrsEnc) as CFData,
                                           Data(sig.value) as CFData, nil)
            if ok { return true }
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
        guard let sd = tlv(ci.value, off), sd.tag == 0xA0 else { return [] }
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
            certs.append(Data(Array(c.value[co..<cert.next])))
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
    // MARK: - DER helpers (in-memory, for selfCheck only)

    /// Minimal DER TLV encoder: tag byte + length + value.
    private static func derTLV(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        var out = [tag]
        if value.count < 0x80 {
            out.append(UInt8(value.count))
        } else {
            var len = value.count
            var lenBytes: [UInt8] = []
            while len > 0 { lenBytes.insert(UInt8(len & 0xFF), at: 0); len >>= 8 }
            out.append(UInt8(0x80 | lenBytes.count))
            out.append(contentsOf: lenBytes)
        }
        out.append(contentsOf: value)
        return out
    }

    private static func derSeq(_ content: [UInt8]) -> [UInt8] { derTLV(0x30, content) }
    private static func derSet(_ content: [UInt8]) -> [UInt8] { derTLV(0x31, content) }
    private static func derNull() -> [UInt8] { [0x05, 0x00] }
    private static func derOctetString(_ data: [UInt8]) -> [UInt8] { derTLV(0x04, data) }
    private static func derOID(_ bytes: [UInt8]) -> [UInt8] { derTLV(0x06, bytes) }

    /// Encode raw bytes as a DER INTEGER (adds leading 0x00 if high bit set).
    private static func derInteger(_ bytes: [UInt8]) -> [UInt8] {
        var b = bytes
        if b.isEmpty { b = [0] }
        if b[0] & 0x80 != 0 { b.insert(0, at: 0) } // keep positive
        return derTLV(0x02, b)
    }

    // MARK: - Self-check (runs on the CI macOS runner, see main.swift)
    #if os(macOS)
    /// Build a self-signed X.509 v3 certificate (DER) in pure Swift.
    /// `SecCertificateCreateWithProperties` is not a public API, so the
    /// certificate is assembled by hand from the DER helpers above.
    struct SelfSignedCert { let cert: Data; let tbs: Data }
    static func makeSelfSignedCert(privateKey: SecKey, cn: String) -> SelfSignedCert? {
        // SubjectPublicKeyInfo (DER): SecKeyCopyExternalRepresentation returns
        // the DER-encoded SPKI for an RSA public key (macOS 10.15+ / iOS 13+).
        guard let pubKey = SecKeyCopyPublicKey(privateKey) else {
            FileHandle.standardError.write("makeSelfSignedCert: SecKeyCopyPublicKey failed\n".data(using: .utf8)!)
            return nil
        }
        var repErr: Unmanaged<CFError>?
        guard let spki = SecKeyCopyExternalRepresentation(pubKey, &repErr) else {
            FileHandle.standardError.write("makeSelfSignedCert: SecKeyCopyExternalRepresentation failed err=\(String(describing: repErr))\n".data(using: .utf8)!)
            return nil
        }
        let spkiBytes = [UInt8](spki as Data)
        FileHandle.standardError.write("makeSelfSignedCert: SPKI size=\(spkiBytes.count) firstByte=0x\(String(format: "%02X", spkiBytes.first ?? 0))\n".data(using: .utf8)!)
        // X509Name { CN = cn }
        let c = [UInt8](cn.utf8)
        let atv = derOID([0x55, 0x04, 0x03]) + derTLV(0x0C, c) // OID(2.5.4.3) + UTF8String value
        let atvTLV = derSeq(atv)   // SEQUENCE { OID, UTF8String } = AttributeTypeAndValue
        let rdn = derSet(atvTLV)   // SET { ATV } = RelativeDistinguishedName
        let name = derSeq(rdn)     // SEQUENCE { RDN } = Name
        // Validity (UTCTime): now-1d .. now+365d
        func utc(_ d: Date) -> [UInt8] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
            let p = cal.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: d)
            let s = String(format: "%02d%02d%02d%02d%02d%02dZ",
                           (p.year ?? 0) % 100, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0, p.second ?? 0)
            return [UInt8](s.utf8)
        }
        let now = Date()
        let validity = derSeq(derTLV(0x17, utc(now.addingTimeInterval(-86_400)))
            + derTLV(0x17, utc(now.addingTimeInterval(365 * 86_400))))
        // sha256WithRSAEncryption (1.2.840.113549.1.1.11)
        let sigAlg = derSeq(derOID([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]) + derNull())
        let version = derTLV(0xA0, derInteger([0x02]))
        let tbs = derSeq(version + derInteger([0x01]) + sigAlg + name + validity + name + spkiBytes)
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureDigestPKCS1v15SHA256,
                                              Data(tbs) as CFData, &err) else {
            FileHandle.standardError.write("makeSelfSignedCert: SecKeyCreateSignature failed err=\(String(describing: err))\n".data(using: .utf8)!)
            return nil
        }
        let sigBits = derTLV(0x03, [0x00] + [UInt8](sig as Data))
        return SelfSignedCert(cert: Data(derSeq(tbs + sigAlg + sigBits)), tbs: Data(tbs))
    }

    /// Returns "" on success, otherwise a human-readable failure report.
    static func selfCheck() -> String {
        // 1. Generate a throwaway RSA-2048 key + self-signed cert for the test.
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var err: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &err) else {
            return "selfCheck: SecKeyCreateRandomKey failed"
        }
        guard let made = makeSelfSignedCert(privateKey: privateKey, cn: "sid9tool-selfcheck") else {
            return "selfCheck: makeSelfSignedCert returned nil (SPKI/sign step)"
        }
        let certData = made.cert
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return "selfCheck: SecCertificateCreateWithData rejected \(certData.count)-byte DER"
        }
        guard let id = SecIdentityCreate(nil, certificate, privateKey) else {
            return "selfCheck: SecIdentityCreate failed"
        }

        let content = Data("sid9tool CMS self-check payload".utf8)
        // 2. Sign.
        do {
            let cms = try sign(identity: id, cert: certificate, content: content)
            // 3. Certificates must be embedded in the blob.
            let certs = extractCertificates(from: cms)
            guard !certs.isEmpty else {
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
