import Foundation
import Network

/// VPN / tunnel state detection for JIT-less LocalDevVPN usage.
final class TunnelService {

    struct TunnelStatus: Equatable {
        var vpnConnected: Bool
        var tunnelEndpoint: String
        var reachable: Bool
    }

    /// Detect whether a VPN interface is up (interface index >= 0 with vpn flag is
    /// unavailable to apps; we infer from an active interface that is not Wi-Fi).
    static func currentStatus(endpoint: String) -> TunnelStatus {
        let interfaces = NWInterface.list()
        let hasVPN = interfaces.contains { iface in
            iface.type == .interface
            && !iface.name.lowercased().contains("wifi")
            && !iface.name.lowercased().contains("awdl")
            && !iface.name.lowercased().contains("en0")
        }
        return TunnelStatus(vpnConnected: hasVPN, tunnelEndpoint: endpoint, reachable: false)
    }

    /// Probe the configured tunnel endpoint (best-effort, 2s timeout).
    static func probe(endpoint: String) async -> Bool {
        guard let url = URL(string: endpoint), url.scheme?.hasPrefix("http") == true else { return false }
        await withTaskGroup(of: Bool.self) { group in
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
