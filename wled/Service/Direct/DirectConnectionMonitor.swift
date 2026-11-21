import Foundation
import Network

/// Finds a lantern when the phone is on the lantern's own WiFi (the lantern was moved where there is no
/// home WiFi). It only asks 4.3.2.1 who it is when the phone has an address on such a WiFi, so nothing is
/// sent anywhere at home.
///
/// iOS sends requests for 4.3.2.x over that WiFi even when it has no internet, so nothing else is needed for
/// the app to reach the lantern. Joining the lantern's WiFi from the app needs NEHotspotConfiguration (paid
/// Apple Developer account); until then users join it in Settings › Wi-Fi.
@MainActor
final class DirectConnectionMonitor: ObservableObject {
    static let shared = DirectConnectionMonitor()

    /// The MAC of the lantern answering on its own WiFi, if any.
    @Published private(set) var lanternMac: String?

    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private var probeTask: Task<Void, Never>?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private init() {
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        monitor.start(queue: DispatchQueue(label: "DirectConnectionMonitor"))
    }

    /// Looks again, e.g. when the app comes back to the foreground.
    func check() {
        probeTask?.cancel()
        guard DirectConnection.isOnLanternNetwork(addresses: Self.localIPv4Addresses()) else {
            lanternMac = nil
            return
        }
        probeTask = Task { [weak self] in
            // The lantern may need a few seconds after the WiFi is up.
            for attempt in 0..<5 {
                guard let self, !Task.isCancelled else { return }
                if let mac = await self.fetchMac() {
                    self.lanternMac = mac
                    return
                }
                if attempt < 4 { try? await Task.sleep(for: .seconds(2)) }
            }
            self?.lanternMac = nil
        }
    }

    private func fetchMac() async -> String? {
        guard let url = URL(string: "http://\(DirectConnection.apAddress)/json/info"),
              let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let mac = json["mac"] as? String, !mac.isEmpty else { return nil }
        return mac
    }

    /// The phone's IPv4 addresses on all interfaces.
    private static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: host))
            }
        }
        return addresses
    }
}
