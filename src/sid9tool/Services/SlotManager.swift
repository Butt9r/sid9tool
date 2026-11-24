import Foundation

/// Free-account slot quota (3 signed apps) with expiry countdown.
final class SlotManager {

    enum SlotResult: Equatable {
        case granted
        case noSlotsLeft
        case expired
    }

    /// Validate whether a new signing/install can proceed.
    static func canInstall(current: SlotUsage) -> SlotResult {
        if let expiresAt = current.expiresAt, expiresAt < Date() {
            return .expired
        }
        guard current.occupiedSlots < current.totalSlots else {
            return .noSlotsLeft
        }
        return .granted
    }

    /// Days (rounded up) until the slot window expires, or nil if open-ended.
    static func daysUntilExpiry(_ current: SlotUsage) -> Int? {
        guard let expiresAt = current.expiresAt else { return nil }
        return max(0, Int(ceil(expiresAt.timeIntervalSinceNow / 86400)))
    }

    /// Rotate the slot window after a successful re-sign (v1: +7 days).
    static func renew(_ current: SlotUsage) -> SlotUsage {
        var updated = current
        updated.expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        return updated
    }
}
