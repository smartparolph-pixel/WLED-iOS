import Foundation

/// Effect settings a preset can override; nil keeps the effect's default (or, for brightness, the current).
struct EffectSettings: Equatable {
    var speed: Int?
    var intensity: Int?
    var palette: Int?
    var brightness: Int?

    var isDefault: Bool { speed == nil && intensity == nil && palette == nil && brightness == nil }
}

/// A preset that is not a playlist. `effectId` is set when it is a single-effect preset the app can edit
/// (saved as an API call, like the app's own); nil for presets saved from WLED's web page with full state.
struct SavedPreset: Equatable, Identifiable {
    let id: Int
    let name: String
    let effectId: Int?
    let settings: EffectSettings

    var editable: Bool { effectId != nil }
}

/// A playlist on the device. Every entry uses `seconds` and `fadeSeconds` when saved from the app.
struct SavedPlaylist: Equatable, Identifiable {
    let id: Int
    var name: String
    var quickLoad: String?
    var presetIds: [Int]
    var seconds: Int
    var fadeSeconds: Int
    var shuffle: Bool

    /// The built-in pack this playlist comes from, or nil for the user's own.
    var pack: PresetPack? { PresetPacks.builtIn(named: name) }
}

/// The device's presets.json, split into presets and playlists, each sorted by id.
struct DevicePresets: Equatable {
    private static let tenths = 10

    let presets: [SavedPreset]
    let playlists: [SavedPlaylist]

    func preset(_ id: Int) -> SavedPreset? { presets.first { $0.id == id } }

    /// Playlists that are not built in, i.e. made by the user in the app or on WLED's web page.
    var custom: [SavedPlaylist] { playlists.filter { $0.pack == nil } }

    /// Lowest id not used by any preset or playlist, or nil if all are taken.
    func freeId() -> Int? {
        let taken = Set(presets.map(\.id) + playlists.map(\.id))
        return (1...PresetPackPlanner.maxPresetId).first { !taken.contains($0) }
    }

    init(presets: [SavedPreset], playlists: [SavedPlaylist]) {
        self.presets = presets
        self.playlists = playlists
    }

    init(parsing json: [String: Any]) {
        var presets: [SavedPreset] = []
        var playlists: [SavedPlaylist] = []
        for (key, value) in json {
            guard let id = Int(key), (1...PresetPackPlanner.maxPresetId).contains(id),
                  let entry = value as? [String: Any], !entry.isEmpty else { continue }
            let name = (entry["n"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Preset \(id)"
            if let playlist = entry["playlist"] as? [String: Any] {
                playlists.append(Self.playlist(id: id, name: name, quickLoad: entry["ql"] as? String, playlist))
            } else {
                let seg = entry["seg"] as? [String: Any]
                let settings = EffectSettings(
                    speed: Self.int(seg?["sx"]),
                    intensity: Self.int(seg?["ix"]),
                    palette: Self.int(seg?["pal"]),
                    brightness: Self.int(entry["bri"])
                )
                presets.append(SavedPreset(id: id, name: name, effectId: Self.int(seg?["fx"]), settings: settings))
            }
        }
        self.presets = presets.sorted { $0.id < $1.id }
        self.playlists = playlists.sorted { $0.id < $1.id }
    }

    private static func playlist(id: Int, name: String, quickLoad: String?, _ playlist: [String: Any]) -> SavedPlaylist {
        let shuffle: Bool
        if let flag = playlist["r"] as? Bool {
            shuffle = flag
        } else {
            shuffle = (int(playlist["r"]) ?? 0) != 0
        }
        return SavedPlaylist(
            id: id,
            name: name,
            quickLoad: quickLoad,
            presetIds: (playlist["ps"] as? [Any] ?? []).compactMap { int($0) },
            seconds: (first(playlist["dur"]) ?? 0) / tenths,
            fadeSeconds: (first(playlist["transition"]) ?? 0) / tenths,
            shuffle: shuffle
        )
    }

    /// A playlist's `dur` and `transition` are a list, or one number for every entry.
    private static func first(_ value: Any?) -> Int? {
        if let list = value as? [Any] { return list.first.flatMap { int($0) } }
        return int(value)
    }

    private static func int(_ value: Any?) -> Int? {
        // JSONSerialization gives NSNumber; a Bool is an NSNumber too, so rule it out.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.intValue
    }
}

/// What an effect offers, from `/json/fxdata` (the part after `@` of the effect's firmware data, e.g.
/// `Time [min],Width;;!;;sx=60`): which sliders it uses, their labels, and its defaults.
/// A nil label means the effect has no such slider; "" means the standard label.
struct EffectControls: Equatable {
    private static let sliderDefault = 128

    let speedLabel: String?
    let intensityLabel: String?
    let usesPalette: Bool
    let defaults: EffectSettings

    init(speedLabel: String?, intensityLabel: String?, usesPalette: Bool, defaults: EffectSettings) {
        self.speedLabel = speedLabel
        self.intensityLabel = intensityLabel
        self.usesPalette = usesPalette
        self.defaults = defaults
    }

    init(parsing data: String) {
        guard !data.isEmpty else {
            // No metadata: the web page shows speed, intensity and palette.
            self.init(
                speedLabel: "", intensityLabel: "", usesPalette: true,
                defaults: EffectSettings(speed: Self.sliderDefault, intensity: Self.sliderDefault, palette: 0)
            )
            return
        }
        let sections = data.components(separatedBy: ";")
        let sliders = sections[0].components(separatedBy: ",")
        let palette = sections.count > 2 ? sections[2].components(separatedBy: ",")[0] : ""
        var defaults: [String: Int] = [:]
        if sections.count > 4 {
            for pair in sections[4].components(separatedBy: ",") {
                let parts = pair.components(separatedBy: "=")
                if parts.count == 2, let value = Int(parts[1]) { defaults[parts[0]] = value }
            }
        }
        self.init(
            speedLabel: Self.label(sliders.count > 0 ? sliders[0] : nil),
            intensityLabel: Self.label(sliders.count > 1 ? sliders[1] : nil),
            usesPalette: !palette.isEmpty && Int(palette) == nil,
            defaults: EffectSettings(
                speed: defaults["sx"] ?? Self.sliderDefault,
                intensity: defaults["ix"] ?? Self.sliderDefault,
                palette: defaults["pal"] ?? 0
            )
        )
    }

    private static func label(_ slider: String?) -> String? {
        switch slider {
        case nil, "": return nil
        case "!": return ""
        default: return slider
        }
    }
}

/// Bodies for `POST /json/state` used by the editor. Saving applies the preset or playlist to the lights.
enum PresetEditorPayloads {
    /// Saves a single-effect preset; settings left nil use the effect's defaults.
    static func presetJSON(id: Int, name: String, effectId: Int, settings: EffectSettings) throws -> Data {
        var body = state(effectId: effectId, settings: settings)
        body["psave"] = id
        body["n"] = name
        body["o"] = true
        return try json(body)
    }

    /// Shows the effect with these settings on the lights without saving anything.
    static func previewJSON(effectId: Int, settings: EffectSettings) throws -> Data {
        try json(state(effectId: effectId, settings: settings))
    }

    /// Saves the playlist; the device starts playing it.
    static func playlistJSON(_ playlist: SavedPlaylist) throws -> Data {
        let spec = PlaylistSpec(
            name: playlist.name,
            quickLoad: playlist.quickLoad,
            secondsPerPreset: playlist.seconds,
            fadeSeconds: playlist.fadeSeconds,
            shuffle: playlist.shuffle
        )
        return try PresetPackPayloads.playlistJSON(spec, id: playlist.id, presetIds: playlist.presetIds)
    }

    static func deleteJSON(id: Int) throws -> Data { try json(["pdel": id]) }

    private static func state(effectId: Int, settings: EffectSettings) -> [String: Any] {
        var seg: [String: Any] = ["fx": effectId, "fxdef": true]
        if let speed = settings.speed { seg["sx"] = speed }
        if let intensity = settings.intensity { seg["ix"] = intensity }
        if let palette = settings.palette { seg["pal"] = palette }
        var body: [String: Any] = ["on": true, "seg": seg]
        if let brightness = settings.brightness { body["bri"] = brightness }
        return body
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
