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
                deviceUDID: guessUDID(named: fileName),
                isTrusted: true
            )
        } catch {
            return nil
        }
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
        try? FileManager.default.removeItem(at: StorageService.support.appendingPathComponent("pairing"))
    }
}
