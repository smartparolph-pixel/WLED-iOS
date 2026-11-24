//
//  DeviceEditViewModel.swift
//  WLED
//
//  Created by Christophe Gagnier on 2025-12-23.
//

import Foundation
import CoreData
import Combine

@MainActor
class DeviceEditViewModel: ObservableObject {
    private let context: NSManagedObjectContext

    private var cancellables = Set<AnyCancellable>()

    @Published var device: DeviceWithState

    /// The lantern's name, saved on the lantern so every phone shows it.
    @Published var lanternName: String = ""
    @Published private(set) var renameStatus: RenameStatus = .idle

    enum RenameStatus: Equatable {
        case idle
        case saving
        /// Saved on the lantern: every phone shows it.
        case savedOnLantern
        /// The lantern couldn't be reached (or has a settings PIN): saved on this phone only.
        case savedOnPhone
        case empty
        case tooLong
    }
    @Published var hideDevice: Bool = false
    @Published var branch: Branch = .unknown

    @Published var isCheckingForUpdates: Bool = false

    init(device: DeviceWithState, context: NSManagedObjectContext) {
        self.context = context
        self.device = device
        lanternName = device.device.displayName
        hideDevice = device.device.isHidden
        branch = device.device.branchValue

        setupCustomNameDebouncedListener()
        setupHideDeviceListener()
        setupBranchListener()
    }

    // MARK: - Form change listeners

    /// Renames the lantern once typing stops; unchanged names (e.g. when the view first loads) are skipped.
    private func setupCustomNameDebouncedListener() {
        $lanternName
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] newName in
                guard let self else { return }
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                guard trimmed != self.device.device.displayName else { return }
                Task { await self.rename(to: trimmed) }
            }
            .store(in: &cancellables)
    }

    /// Saves the name on the lantern (`id.name`) and clears any name kept on this phone only. If the lantern
    /// can't be reached, the name is kept on this phone only, as before.
    private func rename(to name: String) async {
        guard !name.isEmpty else {
            renameStatus = .empty
            return
        }
        guard name.utf8.count <= ProvisioningDefaults.deviceNameMaxBytes else {
            renameStatus = .tooLong
            return
        }
        renameStatus = .saving
        var savedOnLantern = false
        if let address = device.address, let url = URL(string: "http://\(address)/json/cfg") {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? ProvisioningPayloads.nameConfigJSON(name)
            if let result = try? await URLSession.shared.data(for: request),
               let code = (result.1 as? HTTPURLResponse)?.statusCode {
                savedOnLantern = (200..<300).contains(code)
            }
        }
        if savedOnLantern {
            device.device.customName = ""
            device.device.originalName = name
        } else {
            device.device.customName = name
        }
        saveDevice()
        renameStatus = savedOnLantern ? .savedOnLantern : .savedOnPhone
    }

    var renameHint: String {
        switch renameStatus {
        case .idle, .saving:
            return String(localized: "Saved on the Parol, so every phone shows this name.")
        case .savedOnLantern:
            return String(localized: "Saved on the Parol.")
        case .savedOnPhone:
            return String(localized: "Couldn't reach the Parol, so this name is saved on this phone only. Type it again when the Parol is online.")
        case .empty:
            return String(localized: "Enter a name for the lantern.")
        case .tooLong:
            return String(localized: "The lantern name is too long.")
        }
    }

    private func setupHideDeviceListener() {
        $hideDevice
            .removeDuplicates() // Only fire if the bool actually flips
            .sink { [weak self] isHidden in
                guard let self = self else { return }

                // Check against the source of truth to prevent loops
                if self.device.device.isHidden != isHidden {
                    self.device.device.isHidden = isHidden
                    self.saveDevice()
                }
            }
            .store(in: &cancellables)
    }

    private func setupBranchListener() {
        $branch
            .removeDuplicates()
            .sink { [weak self] newBranch in
                guard let self = self else { return }

                if self.device.device.branchValue != newBranch {
                    self.device.device.branchValue = newBranch
                    self.device.device.skipUpdateTag = ""
                    self.saveDevice()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func checkForUpdate() async {
        isCheckingForUpdates = true
        print("Refreshing available Releases")
        await ReleaseService(context: context).refreshVersions()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WLEDNativeApp.dateLastUpdateKey)

        device.device.skipUpdateTag = ""
        isCheckingForUpdates = false
        saveDevice()
    }

    private func saveDevice() {
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            print("Unresolved error saving device: \(nsError), \(nsError.userInfo)")
        }
    }
}
