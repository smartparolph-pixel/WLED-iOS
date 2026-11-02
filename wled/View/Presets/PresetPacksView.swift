import SwiftUI

/// Lists the preset packs (`PresetPacks.all`) with a button to add each to the device.
struct PresetPacksView: View {
    private let address: String?
    /// Playlist name of the pack being added, if any.
    @State private var working: String?
    @State private var result: PackInstallResult?

    init(device: Device) {
        address = device.address
    }

    var body: some View {
        List {
            Section {
                ForEach(PresetPacks.all, id: \.playlist.name) { pack in
                    Button {
                        add(pack)
                    } label: {
                        HStack {
                            Text("Add \(pack.playlist.name)")
                            Spacer()
                            if working == pack.playlist.name {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(working != nil || address == nil)
                }
            } header: {
                Text("Adds ready-made presets and a playlist to this device and starts the playlist. Presets already on the device are kept, so nothing is added twice.")
                    .textCase(nil)
            } footer: {
                if let result {
                    Text(result.message)
                }
            }
        }
        .navigationTitle("Presets & Playlists")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add(_ pack: PresetPack) {
        guard let address else { return }
        working = pack.playlist.name
        result = nil
        Task {
            result = await PresetPackInstaller(address: address).install(pack)
            working = nil
        }
    }
}
