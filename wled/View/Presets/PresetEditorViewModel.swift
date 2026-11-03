import Foundation

/// Everything the preset editor shows for one device.
struct PresetEditorData {
    let presets: DevicePresets
    /// Effect names, index = effect id.
    let effects: [String]
    /// Per effect id; missing entries mean the device did not say.
    let controls: [EffectControls]
    let palettes: [String]

    func controls(for effectId: Int?) -> EffectControls {
        guard let effectId, effectId >= 0, effectId < controls.count else { return EffectControls(parsing: "") }
        return controls[effectId]
    }
}

/// A playlist being edited; `id` is nil for a new one.
struct PlaylistDraft: Equatable {
    /// Choices for "Each effect plays", in seconds.
    static let secondsChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600]
    /// Choices for "Fade between effects", in seconds.
    static let fadeChoices = Array(0...10)

    var id: Int?
    var name = ""
    var quickLoad: String?
    var presetIds: [Int] = []
    var seconds = 20
    var fadeSeconds = 1
    var shuffle = false

    /// The built-in pack it comes from; its name cannot change and it can be reset but not deleted.
    var pack: PresetPack? { id == nil ? nil : PresetPacks.builtIn(named: name) }

    init() {}

    init(_ playlist: SavedPlaylist) {
        id = playlist.id
        name = playlist.name
        quickLoad = playlist.quickLoad
        presetIds = playlist.presetIds
        seconds = max(playlist.seconds, 1)
        fadeSeconds = playlist.fadeSeconds
        shuffle = playlist.shuffle
    }
}

/// The editor behind "Edit" in Presets & Playlists: the device's playlists and single-effect presets,
/// read from presets.json and saved back one at a time through the JSON API.
@MainActor
final class PresetEditorViewModel: ObservableObject {
    enum LoadState {
        case loading
        case loaded(PresetEditorData)
        case unreadable
        case unreachable
    }

    /// WLED keeps 32 bytes of a name and plays at most 100 entries in a playlist.
    private static let maxNameBytes = 32
    private static let maxPlaylistEntries = 100
    /// Playlists are written after the device answers; give it time before reading back.
    private static let reloadDelay: Duration = .seconds(1)

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var saving = false
    @Published var error: String?

    private let installer: PresetPackInstaller

    init(address: String) {
        installer = PresetPackInstaller(address: address)
    }

    var data: PresetEditorData? {
        if case .loaded(let data) = state { return data }
        return nil
    }

    func load() async {
        state = .loading
        do {
            let effects = try JSONSerialization.jsonObject(with: try await installer.get("/json/eff")) as? [String] ?? []
            guard !effects.isEmpty else {
                state = .unreachable
                return
            }
            guard let presets = try await installer.readPresets() else {
                state = .unreadable
                return
            }
            // Optional: without them the editor still works, with standard labels and no palette names.
            let fxdata = try? await installer.get("/json/fxdata")
            let palettes = try? await installer.get("/json/pal")
            let controls = fxdata.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] } ?? []
            state = .loaded(PresetEditorData(
                presets: DevicePresets(parsing: presets),
                effects: effects,
                controls: controls.map { EffectControls(parsing: $0) },
                palettes: palettes.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] } ?? []
            ))
        } catch {
            state = .unreachable
        }
    }

    // MARK: - Playlists

    /// Saves the playlist (the device starts playing it). Returns true when done.
    func save(_ draft: PlaylistDraft) async -> Bool {
        var draft = draft
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        if let problem = problem(with: draft) {
            error = problem
            return false
        }
        guard let id = draft.id ?? data?.presets.freeId() else {
            error = String(localized: "This device has no free preset slot left.")
            return false
        }
        let playlist = SavedPlaylist(
            id: id, name: draft.name, quickLoad: draft.quickLoad, presetIds: draft.presetIds,
            seconds: draft.seconds, fadeSeconds: draft.fadeSeconds, shuffle: draft.shuffle
        )
        return await perform {
            let body = try PresetEditorPayloads.playlistJSON(playlist)
            return await self.installer.send(body)
        }
    }

    private func problem(with draft: PlaylistDraft) -> String? {
        let others = (data?.presets.playlists ?? []).filter { $0.id != draft.id }.map(\.name)
        if draft.name.isEmpty { return String(localized: "Enter a name.") }
        if draft.name.utf8.count > Self.maxNameBytes { return String(localized: "The name is too long.") }
        if others.contains(draft.name) || (draft.id == nil && PresetPacks.builtIn(named: draft.name) != nil) {
            return String(localized: "Another playlist already has this name.")
        }
        if draft.presetIds.isEmpty { return String(localized: "Add at least one effect.") }
        if draft.presetIds.count > Self.maxPlaylistEntries {
            return String(localized: "A playlist can have at most 100 effects.")
        }
        return nil
    }

    func delete(playlistId: Int) async -> Bool {
        await perform {
            let body = try PresetEditorPayloads.deleteJSON(id: playlistId)
            return await self.installer.send(body)
        }
    }

    func reset(_ pack: PresetPack) async -> Bool {
        await perform { await self.installer.reset(pack) }
    }

    // MARK: - Effects

    func save(_ preset: SavedPreset, settings: EffectSettings) async -> Bool {
        guard let effectId = preset.effectId else { return false }
        return await perform {
            let body = try PresetEditorPayloads.presetJSON(
                id: preset.id, name: preset.name, effectId: effectId, settings: settings
            )
            return await self.installer.send(body)
        }
    }

    /// Saves the effect with its default settings (or the app's, e.g. Sunrise's speed).
    func reset(_ preset: SavedPreset) async -> Bool {
        await save(preset, settings: EffectSettings(speed: PresetPacks.speed(forPreset: preset.name)))
    }

    /// Shows the effect with these settings on the lights without saving.
    func preview(_ preset: SavedPreset, settings: EffectSettings) {
        guard let effectId = preset.effectId,
              let body = try? PresetEditorPayloads.previewJSON(effectId: effectId, settings: settings) else { return }
        let installer = installer
        Task { _ = await installer.send(body) }
    }

    /// Runs a save; on success reads presets.json again.
    private func perform(_ action: @escaping () async throws -> Bool) async -> Bool {
        guard !saving else { return false }
        saving = true
        error = nil
        let ok = (try? await action()) ?? false
        saving = false
        guard ok else {
            error = String(localized: "Could not save. Check the connection to the device and try again.")
            return false
        }
        try? await Task.sleep(for: Self.reloadDelay)
        await load()
        return true
    }
}
