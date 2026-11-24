import SwiftUI

/// Editor for a device's playlists and effect presets, laid out like the Schedule screens: a list, and an
/// edit screen for the playlist or effect tapped.
struct PresetEditorView: View {
    @StateObject private var viewModel: PresetEditorViewModel

    init(address: String) {
        _viewModel = StateObject(wrappedValue: PresetEditorViewModel(address: address))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            case .loaded(let data):
                lists(data)
            case .unreadable:
                problem(PackSetupResult.unreadableMessage)
            case .unreachable:
                problem(String(localized: "Could not reach the device. Make sure it is on and try again."))
            }
        }
        .navigationTitle("Edit Presets & Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    PlaylistEditView(viewModel: viewModel, draft: PlaylistDraft())
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("New Playlist")
                }
                .disabled(viewModel.data == nil)
            }
        }
        .task {
            if viewModel.data == nil { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func lists(_ data: PresetEditorData) -> some View {
        if let error = viewModel.error {
            Section { Text(error).foregroundStyle(.red) }
        }
        Section {
            Picker("Plays When Powered On", selection: Binding(
                get: { data.powerOnId },
                set: { id in
                    guard let playlist = data.presets.playlists.first(where: { $0.id == id }) else { return }
                    Task { _ = await viewModel.setPowerOn(playlist) }
                }
            )) {
                if !data.presets.playlists.contains(where: { $0.id == data.powerOnId }) {
                    Text("None (static light)").tag(data.powerOnId)
                }
                ForEach(data.presets.playlists) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
            }
            .disabled(viewModel.saving)
        } header: {
            Text("Plays When Powered On")
        } footer: {
            Text("Starts at full brightness when the lantern is plugged in or the power comes back.")
        }
        Section("Playlists") {
            ForEach(data.presets.playlists) { playlist in
                if playlist.pack?.locked == true {
                    HStack {
                        row(playlist.name, String(localized: "Every effect in a new random order each loop. It can't be changed."))
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Locked")
                    }
                } else {
                    NavigationLink {
                        PlaylistEditView(viewModel: viewModel, draft: PlaylistDraft(playlist))
                    } label: {
                        row(playlist.name, summary(playlist))
                    }
                }
            }
        }
        let effects = data.presets.presets.filter(\.editable)
        if !effects.isEmpty {
            Section {
                ForEach(effects) { preset in
                    NavigationLink {
                        EffectEditView(viewModel: viewModel, preset: preset)
                    } label: {
                        row(
                            preset.name,
                            preset.settings.isDefault
                                ? String(localized: "Default settings") : String(localized: "Custom settings")
                        )
                    }
                }
            } header: {
                Text("Effects")
            } footer: {
                Text("Effect settings are shared: a change shows in every playlist that plays the effect, Random included.")
            }
        }
    }

    private func summary(_ playlist: SavedPlaylist) -> String {
        let count = playlist.presetIds.count
        let seconds = playlist.seconds
        let base = String(localized: "\(count) effects · \(seconds) s each")
        return playlist.shuffle ? base + " · " + String(localized: "Shuffle") : base
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func problem(_ message: String) -> some View {
        Text(message).foregroundStyle(.red)
        Button("Retry Connection") {
            Task { await viewModel.load() }
        }
    }
}

/// "New Playlist" / "Edit Playlist": name, timing, shuffle, effects, and Reset to Default or Delete.
struct PlaylistEditView: View {
    @ObservedObject var viewModel: PresetEditorViewModel
    @State var draft: PlaylistDraft
    @State private var adding = false
    @State private var editMode: EditMode = .inactive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let error = viewModel.error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                if draft.pack != nil {
                    // A built-in playlist keeps its name, so the app recognises it (and does not add it again).
                    Text(draft.name).font(.title3)
                } else {
                    TextField("Name", text: $draft.name)
                }
            }
            Section("Timing") {
                Picker("Each effect plays", selection: $draft.seconds) {
                    ForEach(Self.choices(PlaylistDraft.secondsChoices, including: draft.seconds), id: \.self) {
                        Text(Self.secondsText($0)).tag($0)
                    }
                }
                Picker("Fade between effects", selection: $draft.fadeSeconds) {
                    ForEach(Self.choices(PlaylistDraft.fadeChoices, including: draft.fadeSeconds), id: \.self) {
                        Text(Self.secondsText($0)).tag($0)
                    }
                }
                Toggle(isOn: $draft.shuffle) {
                    VStack(alignment: .leading) {
                        Text("Shuffle")
                        Text("New random order each loop").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            effectsSection
            bottomSection
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(draft.id == nil ? "New Playlist" : "Edit Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await viewModel.save(draft) { dismiss() }
                    }
                }
                .disabled(viewModel.saving)
            }
        }
        .sheet(isPresented: $adding) {
            if let data = viewModel.data {
                AddEffectsSheet(presets: data.presets.presets) { ids in
                    draft.presetIds.append(contentsOf: ids)
                }
            }
        }
        .onAppear { viewModel.error = nil }
    }

    private var effectsSection: some View {
        Section {
            if draft.presetIds.isEmpty {
                Text("Add at least one effect.").foregroundStyle(.secondary)
            }
            ForEach(Array(draft.presetIds.enumerated()), id: \.offset) { _, id in
                Text(viewModel.data?.presets.preset(id)?.name ?? String(localized: "Missing preset \(id)"))
            }
            .onMove { draft.presetIds.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { draft.presetIds.remove(atOffsets: $0) }
            Button {
                adding = true
            } label: {
                Label("Add Effects", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("Effects")
                Spacer()
                if !draft.presetIds.isEmpty {
                    Button(editMode == .active ? String(localized: "Done") : String(localized: "Reorder")) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder
    private var bottomSection: some View {
        if let pack = draft.pack {
            Section {
                Button("Reset to Default") {
                    Task {
                        if await viewModel.reset(pack) { dismiss() }
                    }
                }
                .disabled(viewModel.saving)
            } footer: {
                Text("Puts back this playlist's original effects and timing, and those effects' default settings.")
            }
        } else if let id = draft.id {
            Section {
                Button(role: .destructive) {
                    Task {
                        if await viewModel.delete(playlistId: id) { dismiss() }
                    }
                } label: {
                    Text("Delete Playlist").frame(maxWidth: .infinity)
                }
                .disabled(viewModel.saving)
            }
        }
    }

    /// The choices, plus `value` if it is not one of them (e.g. set on WLED's web page).
    private static func choices(_ list: [Int], including value: Int) -> [Int] {
        list.contains(value) ? list : (list + [value]).sorted()
    }

    private static func secondsText(_ seconds: Int) -> String {
        String(localized: "\(seconds) s")
    }
}

/// Picks presets (effects) to add to the end of a playlist.
private struct AddEffectsSheet: View {
    let presets: [SavedPreset]
    let onAdd: ([Int]) -> Void
    @State private var picked: [Int] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(presets) { preset in
                Button {
                    if let index = picked.firstIndex(of: preset.id) {
                        picked.remove(at: index)
                    } else {
                        picked.append(preset.id)
                    }
                } label: {
                    HStack {
                        Text(preset.name).foregroundStyle(Color.primary)
                        Spacer()
                        if picked.contains(preset.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Add Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(picked)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}

/// "Edit Effect": speed, intensity, palette and brightness, shown live on the lights.
struct EffectEditView: View {
    private static let sliderRange: ClosedRange<Double> = 0...255
    private static let defaultBrightness = 128

    @ObservedObject var viewModel: PresetEditorViewModel
    let preset: SavedPreset
    @State private var settings: EffectSettings
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PresetEditorViewModel, preset: SavedPreset) {
        self.viewModel = viewModel
        self.preset = preset
        _settings = State(initialValue: preset.settings)
    }

    private var controls: EffectControls { viewModel.data?.controls(for: preset.effectId) ?? EffectControls(parsing: "") }

    var body: some View {
        Form {
            if let error = viewModel.error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Text(preset.name).font(.title3)
            } footer: {
                if !usedIn.isEmpty {
                    Text("Used in: \(usedIn)")
                }
            }
            Section {
                sliders
                palettePicker
                brightness
            } header: {
                Text("Settings")
            } footer: {
                Text("Changes show on the lights as you adjust them. Save to keep them.")
            }
            Section {
                Button("Reset to Default") {
                    Task {
                        if await viewModel.reset(preset) { dismiss() }
                    }
                }
                .disabled(viewModel.saving)
            }
        }
        .navigationTitle("Edit Effect")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await viewModel.save(preset, settings: settings) { dismiss() }
                    }
                }
                .disabled(viewModel.saving)
            }
        }
        .onAppear {
            viewModel.error = nil
            viewModel.preview(preset, settings: settings)
        }
    }

    /// Names of the playlists that play this preset, since a change shows in all of them.
    private var usedIn: String {
        (viewModel.data?.presets.playlists ?? [])
            .filter { $0.presetIds.contains(preset.id) }
            .map(\.name)
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var sliders: some View {
        if let label = controls.speedLabel {
            slider(
                label.isEmpty ? String(localized: "Speed") : label,
                value: Binding(
                    get: { Double(settings.speed ?? controls.defaults.speed ?? 0) },
                    set: { settings.speed = Int($0) }
                )
            )
        }
        if let label = controls.intensityLabel {
            slider(
                label.isEmpty ? String(localized: "Intensity") : label,
                value: Binding(
                    get: { Double(settings.intensity ?? controls.defaults.intensity ?? 0) },
                    set: { settings.intensity = Int($0) }
                )
            )
        }
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary)
            }
            Slider(value: value, in: Self.sliderRange, step: 1) { editing in
                if !editing { viewModel.preview(preset, settings: settings) }
            }
        }
    }

    @ViewBuilder
    private var palettePicker: some View {
        let palettes = viewModel.data?.palettes ?? []
        if controls.usesPalette && !palettes.isEmpty {
            Picker("Palette", selection: Binding(
                get: { settings.palette ?? controls.defaults.palette ?? 0 },
                set: { palette in
                    settings.palette = palette
                    viewModel.preview(preset, settings: settings)
                }
            )) {
                ForEach(Array(palettes.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
        }
    }

    @ViewBuilder
    private var brightness: some View {
        Toggle(isOn: Binding(
            get: { settings.brightness != nil },
            set: { on in
                settings.brightness = on ? Self.defaultBrightness : nil
                viewModel.preview(preset, settings: settings)
            }
        )) {
            VStack(alignment: .leading) {
                Text("Set brightness")
                Text("Off keeps the brightness the lights already have.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if settings.brightness != nil {
            slider(
                String(localized: "Brightness"),
                value: Binding(
                    get: { Double(settings.brightness ?? Self.defaultBrightness) },
                    set: { settings.brightness = max(Int($0), 1) }
                )
            )
        }
    }
}
