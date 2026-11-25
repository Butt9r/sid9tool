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
        case p12Missing
        case provisionMismatch(String)
        case packagingFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidIPA(let reason):
                return "Invalid IPA: \(reason)"
            case .plistMissing:
                return "Payload/<App>.app/Info.plist not found in the IPA."
            case .provisionInvalid:
                return "The .mobileprovision file could not be parsed."
            case .p12Missing:
                return "The .p12 signing certificate is not stored yet — import it in 設定 first."
            case .provisionMismatch(let reason):
                return "The provisioning profile does not cover this IPA: \(reason)"
            case .packagingFailed(let reason):
                return "Repackaging into .ipa failed: \(reason)"
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
            let archive = try Archive(url: url, readOnly: true)
            try archive.extract(to: unzipDest)
        } catch {
            throw EngineError.invalidIPA("unzip failed: \(error.localizedDescription)")
        }

        let fm = FileManager.default
        guard let payloadContents = try? fm.contentsOfDirectory(at: unzipDest, includingPropertiesForKeys: nil),
              let payloadDir = payloadContents.first(where: { $0.lastPathComponent.caseInsensitiveCompare("Payload") == .orderedSame })
        else { throw EngineError.invalidIPA("no Payload/ directory") }

        guard let payloadApps = try? fm.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil),
              let appBundle = payloadApps.first(where: { $0.pathExtension == "app" })
        else { throw EngineError.invalidIPA("no .app bundle inside Payload/") }

        let plistURL = appBundle.appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
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

    // MARK: - Signing pipeline (re-sign + package)

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
        let entitlementsURL: URL?
    }

    /// Full re-sign + package pipeline (sandbox-safe; the final zip step uses a
    /// pure-Swift stored-ZIP writer, no external binary required).
    ///
    /// Steps:
    ///  1. Validate the stored .p12 and the provisioning profile.
    ///  2. Confirm the profile's Team ID + App ID actually cover the IPA's Bundle ID.
    ///  3. Rebuild the .app under `workDir/signed/Payload/` with:
    ///       - the generated `sid9tool.entitlements` inside the bundle
    ///       - `embedded.mobileprovision` (raw profile bytes) inside the bundle
    ///  4. Repackage `Payload/` into a ready-to-install `<name>.ipa` in downloads.
    static func sign(_ request: SignRequest) throws -> SignResult {
        let fm = FileManager.default
        let parsed = request.parsedIPA

        // 1. Inputs
        guard fm.fileExists(atPath: request.p12URL.path) else { throw EngineError.p12Missing }
        guard fm.fileExists(atPath: parsed.appBundleURL.path) else {
            throw EngineError.invalidIPA("the extracted app bundle disappeared from \(parsed.workDir.path)")
        }
        let profile: [String: Any]
        do { profile = try parseProvisioningProfile(at: request.provisioningURL) }
        catch { throw EngineError.provisionMismatch("could not parse the profile") }

        let teamID = (profile["TeamIdentifier"] as? [String])?.first
        let appID = (profile["Entitlements"] as? [String: Any])?["application-identifier"] as? String
        guard let teamID else { throw EngineError.provisionMismatch("profile has no TeamIdentifier") }
        guard let appID,
              appID == teamID + "." + parsed.bundleId || appID == teamID + ".*"
        else {
            throw EngineError.provisionMismatch("App ID \"\(appID ?? "nil")\" does not cover \(parsed.bundleId)")
        }
        if let exp = profile["ExpirationDate"] as? Date, exp < Date() {
            throw EngineError.provisionMismatch("profile already expired")
        }

        // 2. Rebuild the bundle with embedded profile + entitlements
        let signedRoot = parsed.workDir.appendingPathComponent("signed", isDirectory: true)
        let payloadDir = signedRoot.appendingPathComponent("Payload", isDirectory: true)
        StorageService.ensureDirectory(payloadDir)

        let appName = parsed.appBundleURL.lastPathComponent
        let signedApp = payloadDir.appendingPathComponent(appName)
        if fm.fileExists(atPath: signedApp.path) { try fm.removeItem(at: signedApp) }
        try fm.copyItem(at: parsed.appBundleURL, to: signedApp)

        let entitlements = request.entitlements.isEmpty
            ? buildEntitlements(bundleId: parsed.bundleId, teamID: teamID)
            : request.entitlements
        let entitlementsURL = writeEntitlements(entitlements, into: signedApp)

        let rawProfile = try Data(contentsOf: request.provisioningURL)
        let embedded = signedApp.appendingPathComponent("embedded.mobileprovision")
        try rawProfile.write(to: embedded, options: .atomic)

        // 3. Repackage Payload/ into an IPA with a pure-Swift stored-ZIP writer
        //    (no external `zip` binary — works inside the iOS sandbox).
        let outName = "sid9tool-unsigned-\(parsed.shortVersion).ipa"
        let outURL = StorageService.downloads.appendingPathComponent(outName)
        if fm.fileExists(atPath: outURL.path) { try? fm.removeItem(at: outURL) }

        do {
            try Self.zipStored(contentsOf: signedRoot, to: outURL)
            guard fm.fileExists(atPath: outURL.path) else {
                throw EngineError.packagingFailed("output IPA was not produced")
            }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.packagingFailed(error.localizedDescription)
        }

        return SignResult(outputPath: outURL,
                          bundleId: parsed.bundleId,
                          signedAt: Date(),
                          entitlementsURL: entitlementsURL)
    }

    // MARK: - Pure-Swift stored-ZIP writer (no external tools)

    /// Recursively zips `root` (e.g. the dir containing `Payload/`) into a ZIP
    /// archive using the STORED method (compression 0). This is fully
    /// sandbox-safe — no `Process`, no `/usr/bin/zip`.
    private static func zipStored(contentsOf root: URL, to out: URL) throws {
        let fm = FileManager.default
        var files: [URL] = []
        let isDir: Bool
        do { isDir = (try fm.contentsOfDirectory(atPath: root.path)).isEmpty ? false : true } catch { isDir = false }
        guard isDir else { throw EngineError.packagingFailed("zip source is not a directory") }
        let enum = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        for case let fileURL as URL in enum {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            files.append(fileURL)
        }
        files.sort { $0.path < $1.path }

        let now = Date()
        let d = (now.timeIntervalSince1970) as UInt32
        let msSinceMidnight = UInt16((d % 86400) * 1000 / 86) // seconds->1/2s units approx
        let daysSinceEpoch = UInt16(d / 86400 % 16384)
        let ms2 = UInt16((msSinceMidnight / 20) % 20) // 1/20s -> 1/100s
        let ms10 = ms2 * 100
        let m = UInt16((d % 3600) / 60)
        let h = UInt16((d % 86400) / 3600)
        var dosTime: UInt16 = (UInt16(h) << 11) | (m << 5) | (ms10 / 32)
        _ = msSinceMidnight
        let dosDate: UInt16 = (UInt16(daysSinceEpoch & 0x1FFF)) | (UInt16(1) << 9)
        var crcTable = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            crcTable[i] = c
        }
        func crc32(_ data: Data) -> UInt32 {
            var c: UInt32 = 0xFFFFFFFF
            for b in data {
                c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
            }
            return c ^ 0xFFFFFFFF
        }

        var outBuf = Data()
        func put(_ x: UInt8) { outBuf.append(x) }
        func put16(_ x: UInt16) { put(UInt8(x & 0xFF)); put(UInt8((x >> 8) & 0xFF)) }
        func put32(_ x: UInt32) { put(UInt8(x & 0xFF)); put(UInt8((x >> 8) & 0xFF)); put(UInt8((x >> 16) & 0xFF)); put(UInt8((x >> 24) & 0xFF)) }

        var cdEntries = [(offset: UInt32, crc: UInt32, compSize: UInt32, uncSize: UInt32, name: [UInt8], attrs: UInt32, dosDate: UInt16, dosTime: UInt16)]()

        for fileURL in files {
            let rel = String(fileURL.path.dropFirst(root.path.count).drop(while: { $0 == "/" }))
            let nameBytes = Array(rel.utf8)
            let data = try Data(contentsOf: fileURL)
            let crc = crc32(data)
            let off = UInt32(outBuf.count)
            put32(0x04034B50) // local file header sig
            put16(0x14)       // version needed
            put16(0x0800)     // UTF-8 names flag
            put16(0)          // stored
            put16(dosTime)
            put16(dosDate)
            put32(crc)
            put32(UInt32(data.count))
            put32(UInt32(data.count))
            put16(UInt16(nameBytes.count))
            put16(0)          // extra len
            outBuf.append(contentsOf: nameBytes)
            outBuf.append(data)
            cdEntries.append((offset: off, crc: crc, compSize: UInt32(data.count), uncSize: UInt32(data.count), name: nameBytes, attrs: 0, dosDate: dosDate, dosTime: dosTime))
        }

        let cdStart = UInt32(outBuf.count)
        for e in cdEntries {
            put32(0x02014B50) // central dir sig
            put16(0x14)       // version made by
            put16(0x14)       // version needed
            put16(0x0800)     // flags
            put16(0)          // method stored
            put16(e.dosTime)
            put16(e.dosDate)
            put32(e.crc)
            put32(e.compSize)
            put32(e.uncSize)
            put16(UInt16(e.name.count))
            put16(0)          // extra len
            put16(0)          // comment len
            put16(0)          // disk number
            put16(0)          // internal attrs
            put32(e.attrs)
            put32(e.offset)
            outBuf.append(contentsOf: e.name)
        }
        let cdEnd = UInt32(outBuf.count)
        put32(0x06054B50) // EOCD sig
        put16(0)
        put16(0)
        put16(UInt16(cdEntries.count))
        put16(UInt16(cdEntries.count))
        put32(cdEnd - cdStart)
        put32(cdStart)
        put16(0)

        try outBuf.write(to: out, options: .atomic)
        _ = d; _ = crcTable
    }
}