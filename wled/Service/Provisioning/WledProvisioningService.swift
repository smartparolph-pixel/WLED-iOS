import Foundation
import CoreData
import NetworkExtension
import OSLog

/// Tapo-style onboarding for a WLED device:
///
///  1. Join the device's setup AP (system-confirmed via `NEHotspotConfiguration`).
///  2. Verify it is WLED and read its MAC (`GET /json/info`).
///  3. Push home WiFi credentials (`POST /json/cfg`) and reboot it (`POST /json/state {"rb":true}`).
///  4. Drop the AP configuration so the phone falls back to its normal WiFi.
///  5. Wait for the device to re-appear over Bonjour, matching on MAC, and add it to the app.
///
/// Requires the "Hotspot Configuration" capability (`wled.entitlements`) and a paid developer
/// account; it does not work in the simulator.
@MainActor
final class WledProvisioningService {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ca.cgagnier.wled-native",
        category: "WledProvisioningService"
    )
    private let firstContactService: DeviceFirstContactService

    init(firstContactService: DeviceFirstContactService = DeviceFirstContactService()) {
        self.firstContactService = firstContactService
    }

    /// - Returns: The Core Data object ID of the added device (resolve it on the main context).
    func provision(
        _ request: ProvisioningRequest,
        onProgress: @escaping @MainActor (ProvisioningProgress) -> Void
    ) async throws -> NSManagedObjectID {
        onProgress(.joiningSetupNetwork)
        try await joinSetupNetwork(request)

        let info: Info
        do {
            let session = makeSession()
            info = try await fetchInfo(session)

            onProgress(.sendingCredentials)
            try await postCredentials(session, request)

            onProgress(.rebootingDevice)
            try await Task.sleep(for: ProvisioningDefaults.configWriteGrace)
            await requestReboot(session)
        } catch {
            await leaveSetupNetwork(prefix: request.apSsidPrefix)
            throw error
        }
        await leaveSetupNetwork(prefix: request.apSsidPrefix)

        onProgress(.waitingForDevice)
        try await Task.sleep(for: ProvisioningDefaults.rebootSettle)
        let address = try await waitForDevice(macAddress: info.mac)
        return try await firstContactService.fetchAndUpsertDevice(rawAddress: address)
    }

    // MARK: - Step 1: join / leave the setup AP

    private func joinSetupNetwork(_ request: ProvisioningRequest) async throws {
        let configuration: NEHotspotConfiguration
        if let password = request.apPassword {
            configuration = NEHotspotConfiguration(ssidPrefix: request.apSsidPrefix, passphrase: password, isWEP: false)
        } else {
            configuration = NEHotspotConfiguration(ssidPrefix: request.apSsidPrefix)
        }
        // Not persisted: iOS forgets the AP on its own when we are done.
        configuration.joinOnce = true

        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
        } catch let error as NSError {
            guard error.domain == NEHotspotConfigurationErrorDomain,
                  let code = NEHotspotConfigurationError(rawValue: error.code) else {
                logger.error("Join failed: \(error.localizedDescription)")
                throw ProvisioningError.setupNetworkUnavailable
            }
            switch code {
            case .alreadyAssociated:
                break
            case .userDenied:
                throw ProvisioningError.setupNetworkDeclined
            default:
                logger.error("Join failed with NEHotspotConfigurationError \(error.code)")
                throw ProvisioningError.setupNetworkUnavailable
            }
        }
    }

    private func leaveSetupNetwork(prefix: String) async {
        let manager = NEHotspotConfigurationManager.shared
        let ssids: [String] = await withCheckedContinuation { continuation in
            manager.getConfiguredSSIDs { continuation.resume(returning: $0) }
        }
        for ssid in ssids where ssid.hasPrefix(prefix) {
            manager.removeConfiguration(forSSID: ssid)
        }
    }

    // MARK: - Steps 2-3: talk to the device through the AP

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // The setup AP has no internet. Never let iOS "helpfully" route this over cellular.
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = ProvisioningDefaults.httpTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func apURL(_ path: String) throws -> URL {
        guard let url = URL(string: "http://\(ProvisioningDefaults.apHost)\(path)") else {
            throw ProvisioningError.unknown
        }
        return url
    }

    /// Association can still be settling right after `apply` returns, so retry a few times.
    private func fetchInfo(_ session: URLSession) async throws -> Info {
        var lastError: Error?
        for attempt in 0..<ProvisioningDefaults.infoRetries {
            if attempt > 0 { try await Task.sleep(for: ProvisioningDefaults.infoRetryDelay) }
            do {
                let (data, response) = try await session.data(from: try apURL("/json/info"))
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProvisioningError.notAWledDevice }
                let info = try JSONDecoder().decode(Info.self, from: data)
                guard let mac = info.mac, !mac.isEmpty else { throw ProvisioningError.notAWledDevice }
                return info
            } catch {
                lastError = error
                logger.debug("GET /json/info attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }
        logger.error("Giving up on /json/info: \(lastError?.localizedDescription ?? "unknown")")
        throw ProvisioningError.notAWledDevice
    }

    private func postCredentials(_ session: URLSession, _ request: ProvisioningRequest) async throws {
        var urlRequest = URLRequest(url: try apURL("/json/cfg"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try ProvisioningPayloads.wifiConfigJSON(
            ssid: request.homeSsid,
            password: request.homePassword,
            timezone: request.timezone
        )
        let (_, response) = try await session.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProvisioningError.credentialsRejected(http.statusCode)
        }
    }

    private func requestReboot(_ session: URLSession) async {
        guard let url = try? apURL("/json/state") else { return }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = ProvisioningPayloads.rebootJSON
        do {
            _ = try await session.data(for: urlRequest)
        } catch {
            // The device often resets before it finishes answering. That is the success path.
            logger.debug("Connection dropped while rebooting device (expected): \(error.localizedDescription)")
        }
    }

    // MARK: - Step 5: find it again

    private func waitForDevice(macAddress: String?) async throws -> String {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let discovery = DiscoveryService { address, mdnsMac in
            if ProvisioningPayloads.sameMac(mdnsMac, macAddress) {
                continuation.yield(address)
            }
        }
        discovery.scan()
        defer {
            discovery.browser?.cancel()
            continuation.finish()
        }

        let found: String? = try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                for await address in stream { return address }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: ProvisioningDefaults.deviceReappearTimeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let found else { throw ProvisioningError.deviceDidNotReappear }
        return found
    }
}
