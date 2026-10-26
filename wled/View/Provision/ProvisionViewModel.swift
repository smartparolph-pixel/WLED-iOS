import Foundation
import CoreData

@MainActor
final class ProvisionViewModel: ObservableObject {

    @Published var homeSsid: String = ""
    @Published var homePassword: String = ""
    /// Start of the device's setup network name. Factory-flashed products may use their own.
    @Published var apSsidPrefix: String = ProvisioningDefaults.apSsidPrefix
    /// Setup network password. Empty means the setup network is open.
    @Published var apPassword: String = ProvisioningDefaults.apPassword
    @Published var step: Step = .form()

    private let service = WledProvisioningService()
    private var task: Task<Void, Never>?

    enum Step: Equatable {
        case form(ssidError: String = "", errorMessage: String = "")
        case working(ProvisioningProgress)
        case success(deviceName: String)

        var isForm: Bool {
            if case .form = self { return true }
            return false
        }
    }

    func start() {
        let ssid = homeSsid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else {
            step = .form(ssidError: String(localized: "Enter your WiFi name"))
            return
        }
        let prefix = apSsidPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else {
            step = .form(errorMessage: String(localized: "Enter the start of the setup network name"))
            return
        }
        // WPA2 passphrases are 8 to 63 characters; NEHotspotConfiguration rejects anything else.
        guard apPassword.isEmpty || (8...63).contains(apPassword.count) else {
            step = .form(errorMessage: String(localized: "WiFi passwords are 8 to 63 characters"))
            return
        }
        step = .working(.joiningSetupNetwork)
        let request = ProvisioningRequest(
            homeSsid: ssid,
            homePassword: homePassword,
            apSsidPrefix: prefix,
            apPassword: apPassword.isEmpty ? nil : apPassword,
            timezone: TimezoneCatalog.setting(for: TimeZone.current.identifier)
        )

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let id = try await service.provision(request) { [weak self] progress in
                    self?.step = .working(progress)
                }
                let context = PersistenceController.shared.container.viewContext
                let name = (context.object(with: id) as? Device)?.displayName ?? ""
                step = .success(deviceName: name)
            } catch is CancellationError {
                // Dismissed by the user; nothing to show.
            } catch let error as ProvisioningError {
                step = .form(errorMessage: error.localizedDescription)
            } catch {
                step = .form(errorMessage: ProvisioningError.unknown.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}
