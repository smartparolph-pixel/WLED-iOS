import Foundation
import CoreData

@MainActor
final class ProvisionViewModel: ObservableObject {

    @Published var homeSsid: String = ""
    @Published var homePassword: String = ""
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
        step = .working(.joiningSetupNetwork)
        let request = ProvisioningRequest(homeSsid: ssid, homePassword: homePassword)

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
