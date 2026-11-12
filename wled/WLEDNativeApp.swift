import SwiftUI

@main
struct WLEDNativeApp: App {
    static let dateLastUpdateKey = "lastUpdateReleasesDate"
    
    let persistenceController = PersistenceController.shared
    @ObservedObject private var appLock = AppLock.shared
    /// Result of opening a "Share Parol" link, shown as an alert.
    @State private var shareMessage: String?
    
    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    refreshVersionsSync()
                }
                .onOpenURL { url in
                    guard let address = ParolShareLink.address(from: url) else { return }
                    Task { await addSharedLantern(address: address) }
                }
                .alert(
                    shareMessage ?? "",
                    isPresented: Binding(get: { shareMessage != nil }, set: { if !$0 { shareMessage = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                }
                .appLock(appLock)
        }
    }
    
    /// A scanned "Share Parol" QR code: contact the lantern and add it to the list.
    private func addSharedLantern(address: String) async {
        do {
            let id = try await DeviceFirstContactService().fetchAndUpsertDevice(rawAddress: address)
            let device = persistenceController.container.viewContext.object(with: id) as? Device
            let name = device?.displayName ?? address
            shareMessage = String(localized: "\(name) was added.")
        } catch {
            shareMessage = String(localized: "Could not reach the lantern at \(address). Make sure this phone is on the same WiFi.")
        }
    }

    private func refreshVersionsSync() {
        Task {
            // Only update automatically from Github once per 24 hours to avoid rate limits
            // and reduce network usage.
            let date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: WLEDNativeApp.dateLastUpdateKey))
            var dateComponent = DateComponents()
            dateComponent.day = 1
            let dateToRefresh = Calendar.current.date(byAdding: dateComponent, to: date)
            let dateNow = Date()
            guard let dateToRefresh = dateToRefresh else {
                return
            }
            if dateNow <= dateToRefresh {
                return
            }
            print("Refreshing available Releases")
            await ReleaseService(context: persistenceController.container.viewContext).refreshVersions()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: WLEDNativeApp.dateLastUpdateKey)
        }
    }
}
