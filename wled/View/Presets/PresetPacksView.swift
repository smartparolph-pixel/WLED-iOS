import SwiftUI

/// The device's playlists (`PresetPacks.all`). Any that are missing are added without asking when this
/// opens; tapping one plays it, and the one playing is ticked.
struct PresetPacksView: View {
    @ObservedObject var device: DeviceWithState
    /// Nil while the playlists are being checked (and added if missing).
    @State private var setup: PackSetupResult?
    /// Playlist name of the playlist being started, if any.
    @State private var starting: String?
    @State private var playFailed = false

    init(device: DeviceWithState) {
        _device = ObservedObject(wrappedValue: device)
    }

    private var address: String? { device.device.address }

    var body: some View {
        List {
            Section {
                switch setup {
                case nil:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing playlists…")
                    }
                case .ready(let playlistIds, _, _, _):
                    let playingId = device.stateInfo?.state.selectedPlaylistId.map { Int($0) }
                    ForEach(PresetPacks.all, id: \.playlist.name) { pack in
                        let id = playlistIds[pack.playlist.name]
                        Button {
                            play(pack, id: id)
                        } label: {
                            HStack {
                                Text(pack.playlist.name)
                                    .foregroundStyle(id != nil && id == playingId ? Color.accentColor : Color.primary)
                                Spacer()
                                if starting == pack.playlist.name {
                                    ProgressView()
                                } else if id != nil && id == playingId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityLabel("Playing")
                                }
                            }
                        }
                        .disabled(id == nil || starting != nil)
                    }
                case .nothingAvailable, .unreachable:
                    if let setup {
                        Text(setup.setupMessage)
                    }
                    if setup == .unreachable {
                        Button("Retry Connection") { prepare() }
                    }
                }
            } header: {
                Text("Tap a playlist to play it on this device.")
                    .textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let notes = setup?.notes {
                        Text(notes)
                    }
                    if playFailed {
                        Text("Could not reach the device. Make sure it is on and try again.")
                    }
                }
            }
        }
        .navigationTitle("Presets & Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .task { prepare() }
    }

    /// Adds any missing playlists without asking.
    private func prepare() {
        guard let address else {
            setup = .unreachable
            return
        }
        setup = nil
        Task {
            setup = await PresetPackInstaller(address: address).ensureAll()
        }
    }

    private func play(_ pack: PresetPack, id: Int?) {
        guard let address, let id else { return }
        starting = pack.playlist.name
        playFailed = false
        Task {
            playFailed = !(await PresetPackInstaller(address: address).play(id: id))
            starting = nil
        }
    }
}
