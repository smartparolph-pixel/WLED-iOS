import SwiftUI

/// Lists the preset packs (`PresetPacks.all`) with a button to add each to the device.
struct PresetPacksView: View {
    private let address: String?
    /// Playlist name of the pack being added, if any.
    @State private var working: String?
    @State private var addingAll = false
    /// What the last tap did.
    @State private var status: String?

    private var busy: Bool { working != nil || addingAll || address == nil }

    init(device: Device) {
        address = device.address
    }

    var body: some View {
        List {
            Section {
                Button {
                    addAll()
                } label: {
                    HStack {
                        Text("Add all playlists").bold()
                        Spacer()
                        if addingAll {
                            ProgressView()
                        }
                    }
                }
                .disabled(busy)
            } header: {
                Text("Adds ready-made presets and a playlist to this device and starts the playlist. Presets already on the device are kept, so nothing is added twice.")
                    .textCase(nil)
            } footer: {
                if let status {
                    Text(status)
                }
            }
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
                    .disabled(busy)
                }
            }
        }
        .navigationTitle("Presets & Playlists")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add(_ pack: PresetPack) {
        guard let address else { return }
        working = pack.playlist.name
        status = nil
        Task {
            status = await PresetPackInstaller(address: address).install(pack).message
            working = nil
        }
    }

    /// Adds every pack, ending on `PresetPacks.playsAfterSetup` so that one is left playing.
    private func addAll() {
        guard let address else { return }
        addingAll = true
        status = nil
        Task {
            status = PackOutcome.summary(await PresetPackInstaller(address: address).installAll())
            addingAll = false
        }
    }
}
