import Foundation
import CoreData

@MainActor
final class ProvisionViewModel: ObservableObject {

    /// The lantern's name, saved on it so every phone shows the same name.
    @Published var deviceName: String = ProvisioningDefaults.deviceName
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
        /// `presets` is nil while the playlists are still being added to the new device.
        /// `lanternWifi`: the lantern's own WiFi as set during setup.
        case success(deviceName: String, presets: PackSetupResult?, lanternWifi: LanternWifiCredentials?)

        var isForm: Bool {
            if case .form = self { return true }
            return false
        }
    }

    /// Lantern WiFis saved on this phone, offered as the setup network when setting a lantern up again.
    var savedLanternWifis: [LanternWifiCredentials] {
        LanternWifiStore.shared.all.values.sorted { $0.ssid < $1.ssid }
    }

    /// Sets the setup network to a lantern's own WiFi saved on this phone.
    func use(_ credentials: LanternWifiCredentials) {
        apSsidPrefix = credentials.ssid
        apPassword = credentials.password
    }

    func start() {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            step = .form(errorMessage: String(localized: "Enter a name for the lantern."))
            return
        }
        guard name.utf8.count <= ProvisioningDefaults.deviceNameMaxBytes else {
            step = .form(errorMessage: String(localized: "The lantern name is too long."))
            return
        }
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
            timezone: TimezoneCatalog.setting(for: TimeZone.current.identifier),
            deviceName: name
        )

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.provision(request) { [weak self] progress in
                    self?.step = .working(progress)
                }
                let context = PersistenceController.shared.container.viewContext
                let device = context.object(with: result.deviceID) as? Device
                let name = device?.displayName ?? ""
                let wifi = result.lanternWifi
                step = .success(deviceName: name, presets: nil, lanternWifi: wifi)
                let presets = await addPresetPacks(address: device?.address)
                step = .success(deviceName: name, presets: presets, lanternWifi: wifi)
            } catch is CancellationError {
                // Dismissed by the user; nothing to show.
            } catch let error as ProvisioningError {
                step = .form(errorMessage: error.localizedDescription)
            } catch {
                step = .form(errorMessage: ProvisioningError.unknown.localizedDescription)
            }
        }
    }

    /// Adds the playlists to the new device and starts the default, `PresetPacks.playsAfterSetup`.
    private func addPresetPacks(address: String?) async -> PackSetupResult {
        guard let address else { return .unreachable }
        return await PresetPackInstaller(address: address).ensureAll(play: PresetPacks.playsAfterSetup)
    }

    func cancel() {
        task?.cancel()
    }
}
