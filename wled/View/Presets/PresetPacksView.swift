import SwiftUI

/// The device's playlists (`PresetPacks.all`, then the user's own). Any built-in ones that are missing are
/// added without asking when this opens; tapping one plays it, and the one playing is ticked. Edit, at the
/// bottom, opens `PresetEditorView`.
struct PresetPacksView: View {
    @ObservedObject var device: DeviceWithState
    /// Nil while the playlists are being checked (and added if missing).
    @State private var setup: PackSetupResult?
    /// Id of the playlist being started, if any.
    @State private var starting: Int?
    @State private var playFailed = false
    @State private var confirmingRepair = false
    @State private var repairing = false
    /// Why the last repair did not work, if it did not.
    @State private var repairProblem: String?

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
                case .ready(let playlistIds, _, _, _, let custom):
                    let playingId = device.stateInfo?.state.selectedPlaylistId.map { Int($0) }
                    let rows: [(String, Int?)] = PresetPacks.all.map { ($0.playlist.name, playlistIds[$0.playlist.name]) }
                        + custom.map { ($0.name, Optional($0.id)) }
                    ForEach(rows, id: \.0) { name, id in
                        Button {
                            play(id: id)
                        } label: {
                            HStack {
                                Text(name)
                                    .foregroundStyle(id != nil && id == playingId ? Color.accentColor : Color.primary)
                                Spacer()
                                if let id, starting == id {
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
                case .presetsUnreadable(let kept, let dropped, let problem):
                    Text(PackSetupResult.damagedMessage(kept: kept, dropped: dropped))
                    Text("Details: \(problem)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let repairProblem {
                        Text(repairProblem).foregroundStyle(.red)
                    }
                    if repairing {
                        ProgressView()
                    } else {
                        Button("Repair") { confirmingRepair = true }
                    }
                    Button("Retry Connection") { prepare() }
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
        .alert("Repair presets file?", isPresented: $confirmingRepair) {
            Button("Repair") { repair() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if case .presetsUnreadable(let kept, let dropped, _) = setup {
                Text("The device's presets.json will be replaced with a clean copy holding the \(kept) intact presets and playlists. The \(dropped) damaged parts cannot be recovered.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let address, case .ready = setup {
                NavigationLink {
                    SettingsGate { PresetEditorView(address: address) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        // Runs again when coming back from the editor: cheap when nothing changed (presets.json's time).
        .task { await refresh() }
    }

    /// Like `prepare`, but keeps showing the current list while checking.
    private func refresh() async {
        guard let address, case .ready = setup else {
            prepare()
            return
        }
        let result = await PresetPackInstaller(address: address).ensureAll()
        if case .ready = result { setup = result }
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

    /// Rebuilds a damaged presets.json from its intact entries, then checks the playlists again.
    private func repair() {
        guard let address else { return }
        repairing = true
        repairProblem = nil
        Task {
            let result = await PresetPackInstaller(address: address).repairPresets()
            repairing = false
            switch result {
            case .repaired, .notNeeded:
                prepare()
            case .locked:
                repairProblem = String(localized: "This device has a settings PIN. Unlock it on the device's web page (Config), then try again.")
            case .failed:
                repairProblem = String(localized: "Could not repair the file. Check the connection to the device and try again.")
            }
        }
    }

    private func play(id: Int?) {
        guard let address, let id else { return }
        starting = id
        playFailed = false
        Task {
            playFailed = !(await PresetPackInstaller(address: address).play(id: id))
            starting = nil
        }
    }
}
