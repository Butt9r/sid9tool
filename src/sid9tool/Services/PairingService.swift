import Foundation

/// Pairing file (RPPairing / .mobiledevicepairing) import & persistence.
final class PairingService {
    static var directory: URL {
        let u = StorageService.documents.appendingPathComponent("pairing", isDirectory: true)
        StorageService.ensureDirectory(u)
        return u
    }

    /// Import a pairing file into the App Support directory and parse basic metadata.
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
            return PairingProfile(
                importedFileName: fileName,
                importedAt: .now,
                fileSize: (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0,
                isRP: isRP,
                deviceUDID: parseUDID(fromFileAt: destURL) ?? guessUDID(named: fileName),
                isTrusted: true
            )
        } catch {
            return nil
        }
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
