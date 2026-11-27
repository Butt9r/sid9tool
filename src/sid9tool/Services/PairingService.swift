import Foundation

/// Pairing file (RPPairing / .mobiledevicepairing) import & persistence.
final class PairingService {
    static var directory: URL {
        let u = StorageService.documents.appendingPathComponent("pairing", isDirectory: true)
        StorageService.ensureDirectory(u)
        return u
    }

    /// Import a pairing file into the App Support directory and parse basic metadata.
    /// `isTrusted` is true only when a well-formed device UDID was resolved from the
    /// file contents or the `RPPairing-<UDID>` filename convention; otherwise the file
    /// is still kept, but flagged as unrecognized so the UI can warn the user.
    @MainActor
    func importPairing(from sourceURL: URL) -> PairingProfile? {
        let fileName = sourceURL.lastPathComponent
        let isRP = fileName.hasPrefix("RPPairing")
        do {
            let destURL = Self.directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let resolved = parseUDID(fromFileAt: destURL) ?? guessUDID(named: fileName)
            let trusted = (resolved != nil) && Self.isValidUDID(resolved)
            return PairingProfile(
                importedFileName: fileName,
                importedAt: .now,
                fileSize: (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0,
                isRP: isRP,
                deviceUDID: resolved,
                isTrusted: trusted
            )
        } catch {
            return nil
        }
    }

    /// Well-formed iOS device UDID: classic 25-hex + "-" + 1-hex, or 40-hex (newer devices).
    static func isValidUDID(_ s: String?) -> Bool {
        guard let value = s?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return false }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        func allHex(_ body: Substring, _ count: Int) -> Bool {
            body.count == count && body.unicodeScalars.allSatisfy { hex.contains($0) }
        }
        if allHex(Substring(value), 40) { return true }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && allHex(parts[0], 25) && allHex(parts[1], 1)
    }

    /// Parse the pairing file's plist/JSON for the device UDID (Host.UDID, RPPairing, or ProvisionedUDID).
    private func parseUDID(fromFileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var dict: [String: Any]?
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            dict = plist
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = json
        }
        guard let dict else { return nil }
        if let host = dict["Host"] as? [String: Any] {
            if let udid = host["UDID"] as? String { return udid }
            if let options = host["HostOptions"] as? [String: Any], let udid = options["UDID"] as? String { return udid }
        }
        if let udid = dict["RPPairing"] as? [String: Any],
           let host = udid["Host"] as? [String: Any], let value = host["UDID"] as? String { return value }
        if let udid = dict["ProvisionedUDID"] as? String { return udid }
        return nil
    }

    private func guessUDID(named fileName: String) -> String? {
        // RPPairing-<UDID>.json convention
        let base = (fileName as NSString).deletingPathExtension
        let parts = base.split(separator: "-")
        return parts.last.map(String.init)
    }

    /// Remove all stored pairing data.
    @MainActor
    func reset() {
        try? FileManager.default.removeItem(at: StorageService.documents.appendingPathComponent("pairing"))
    }
}
