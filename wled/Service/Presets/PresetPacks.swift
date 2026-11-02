import Foundation

/// A preset that runs one firmware effect with that effect's own defaults (speed, intensity, palette).
struct EffectPreset: Equatable {
    let name: String
    /// The effect's name exactly as the firmware lists it in `/json/eff`.
    let effect: String
}

/// A playlist that plays the pack's presets in order.
struct PlaylistSpec: Equatable {
    let name: String
    /// Quick-load label for the WLED web page's shortcut buttons, at most 2 characters.
    var quickLoad: String?
    let secondsPerPreset: Int
    let fadeSeconds: Int
    /// Loop forever; otherwise play once.
    var loop = true
    var shuffle = false
}

/// Presets plus the playlist that plays them. To ship another set, add a pack to `PresetPacks.all`; the
/// installer, the button on the Edit Device screen and the step after device setup all pick it up.
struct PresetPack: Equatable {
    let presets: [EffectPreset]
    let playlist: PlaylistSpec
}

enum PresetPacks {
    static let twinkleTonight = PresetPack(
        presets: [
            EffectPreset(name: "Twinklefox", effect: "Twinklefox"),
            EffectPreset(name: "Fairy", effect: "Fairy"),
            EffectPreset(name: "Fairytwinkle", effect: "Fairytwinkle"),
            EffectPreset(name: "Glitter", effect: "Glitter"),
            EffectPreset(name: "Sparkle", effect: "Sparkle")
        ],
        playlist: PlaylistSpec(name: "✨ Twinkle Tonight", quickLoad: "✨", secondsPerPreset: 60, fadeSeconds: 1)
    )

    static let all = [twinkleTonight]
}

/// What to do for one preset of a pack.
enum PresetStep: Equatable {
    /// A preset with this name is already on the device; it is used as is.
    case reuse(name: String, id: Int)
    case create(name: String, id: Int, effectId: Int)
    /// The device's firmware has no effect with this name.
    case missingEffect(name: String)
    /// All 250 preset slots are taken.
    case noFreeSlot(name: String)

    var name: String {
        switch self {
        case .reuse(let name, _), .create(let name, _, _), .missingEffect(let name), .noFreeSlot(let name): return name
        }
    }

    var presetId: Int? {
        switch self {
        case .reuse(_, let id), .create(_, let id, _): return id
        case .missingEffect, .noFreeSlot: return nil
        }
    }
}

/// What to do for the playlist.
enum PlaylistStep: Equatable {
    /// Already on the device with exactly these presets: only start it.
    case play(id: Int)
    /// Save at `id` (new, or replacing a same-named playlist whose presets changed), which also starts it.
    case save(id: Int, presetIds: [Int])
    /// None of the presets could be added, or no free slot is left.
    case skip
}

struct PackPlan: Equatable {
    let presets: [PresetStep]
    let playlist: PlaylistStep

    var created: [PresetStep] { presets.filter { if case .create = $0 { return true } else { return false } } }
    var reused: [PresetStep] { presets.filter { if case .reuse = $0 { return true } else { return false } } }
    var unavailable: [PresetStep] { presets.filter { $0.presetId == nil } }
}

/// Decides what to add to a device, so a pack can be installed any number of times without making
/// duplicates. Matching is by name: a preset or playlist with the same name is reused, not added again.
enum PresetPackPlanner {
    static let maxPresetId = 250

    /// - Parameters:
    ///   - presets: The device's `/presets.json`.
    ///   - effects: The device's `/json/eff`: effect names, index = effect id.
    static func plan(_ pack: PresetPack, presets: [String: Any], effects: [String]) -> PackPlan {
        let existing = existingPresets(presets)
        var taken = Set(existing.keys)
        func nextFree() -> Int? {
            guard let id = (1...maxPresetId).first(where: { !taken.contains($0) }) else { return nil }
            taken.insert(id)
            return id
        }

        let steps: [PresetStep] = pack.presets.map { preset in
            if let id = existing.first(where: { $0.value.name == preset.name })?.key {
                return .reuse(name: preset.name, id: id)
            }
            guard let effectId = effects.firstIndex(of: preset.effect) else { return .missingEffect(name: preset.name) }
            guard let id = nextFree() else { return .noFreeSlot(name: preset.name) }
            return .create(name: preset.name, id: id, effectId: effectId)
        }

        let presetIds = steps.compactMap(\.presetId)
        let current = existing.first { $0.value.name == pack.playlist.name }
        let playlist: PlaylistStep
        if presetIds.isEmpty {
            playlist = .skip
        } else if let current, current.value.playlistPresets == presetIds {
            playlist = .play(id: current.key)
        } else if let current {
            playlist = .save(id: current.key, presetIds: presetIds)
        } else if let id = nextFree() {
            playlist = .save(id: id, presetIds: presetIds)
        } else {
            playlist = .skip
        }
        return PackPlan(presets: steps, playlist: playlist)
    }

    private struct Existing {
        let name: String
        let playlistPresets: [Int]?
    }

    private static func existingPresets(_ presets: [String: Any]) -> [Int: Existing] {
        var result: [Int: Existing] = [:]
        for (key, value) in presets {
            guard let id = Int(key), (1...maxPresetId).contains(id),
                  let preset = value as? [String: Any], !preset.isEmpty else { continue }
            let name = (preset["n"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Preset \(id)"
            let playlist = (preset["playlist"] as? [String: Any])?["ps"] as? [Any]
            result[id] = Existing(name: name, playlistPresets: playlist?.compactMap { ($0 as? NSNumber)?.intValue })
        }
        return result
    }
}

/// Bodies for `POST /json/state`. Note the device applies each one to the lights as it saves it.
enum PresetPackPayloads {
    private static let tenthsPerSecond = 10

    /// Saves a preset that turns the light on and runs the effect with the effect's default settings.
    static func presetJSON(id: Int, name: String, effectId: Int) throws -> Data {
        try json([
            "psave": id, "n": name, "o": true, "on": true,
            "seg": ["fx": effectId, "fxdef": true] as [String: Any]
        ])
    }

    /// Saves the playlist; the device starts playing it right away.
    static func playlistJSON(_ spec: PlaylistSpec, id: Int, presetIds: [Int]) throws -> Data {
        var body: [String: Any] = [
            "psave": id, "n": spec.name, "o": true, "on": true,
            "playlist": [
                "ps": presetIds,
                "dur": Array(repeating: spec.secondsPerPreset * tenthsPerSecond, count: presetIds.count),
                "transition": Array(repeating: spec.fadeSeconds * tenthsPerSecond, count: presetIds.count),
                // 0 repeats forever; 1 plays the list once.
                "repeat": spec.loop ? 0 : 1,
                "end": 0,
                "r": spec.shuffle
            ] as [String: Any]
        ]
        if let quickLoad = spec.quickLoad { body["ql"] = quickLoad }
        return try json(body)
    }

    /// Starts an existing preset or playlist.
    static func playJSON(id: Int) throws -> Data { try json(["ps": id]) }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
