import Foundation
import Network

/// VPN / tunnel state detection for JIT-less LocalDevVPN usage.
final class TunnelService {

    struct TunnelStatus: Equatable {
        var vpnConnected: Bool
        var tunnelEndpoint: String
        var reachable: Bool
    }

    /// Detect whether a VPN/tunnel interface is up (utun/ipsec/tun present on the
    /// device — the reliable way for an app to infer an active VPN on iOS).
    static func currentStatus(endpoint: String) -> TunnelStatus {
        let hasVPN = Self.hasTunnelInterface()
        return TunnelStatus(vpnConnected: hasVPN, tunnelEndpoint: endpoint, reachable: false)
    }

    private static func hasTunnelInterface() -> Bool {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return false }
        defer { freeifaddrs(ifap) }
        return Self.scan(ifaddrs: ifap)
    }

    /// Recursively walk the ifaddrs linked list (guaranteed finite — the kernel
    /// terminates the list with a nil ifa_next).
    private static func scan(ifaddrs current: UnsafeMutablePointer<ifaddrs>?) -> Bool {
        guard let current = current else { return false }
        let name = String(cString: current.pointee.ifa_name)
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("tun") {
            return true
        }
        return Self.scan(ifaddrs: current.pointee.ifa_next)
    }

    /// Probe the configured tunnel endpoint (best-effort, 2s timeout).
    static func probe(endpoint: String) async -> Bool {
        guard let url = URL(string: endpoint), url.scheme?.hasPrefix("http") == true else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 2
                    let (data, response) = try await URLSession.shared.data(for: request)
                    _ = data
                    return (response as? HTTPURLResponse)?.statusCode ?? 0 < 100
                } catch {
                    return false
                }
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
