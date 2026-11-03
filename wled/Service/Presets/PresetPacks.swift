import Foundation

/// A preset that runs one firmware effect with that effect's own defaults (speed, intensity, palette).
struct EffectPreset: Equatable {
    let name: String
    /// The effect's name exactly as the firmware lists it in `/json/eff`.
    let effect: String
    /// Overrides the effect's default speed, when that default does not suit a playlist.
    var speed: Int?
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
    /// Kept exactly as defined: not editable in the app, and put back if changed on the device.
    var locked = false
}

enum PresetPacks {
    private static let defaultSeconds = 20
    private static let defaultFade = 1
    private static let slowSeconds = 60
    private static let slowFade = 3

    /// Speeds that differ from the effect's default. Sunrise's speed is its length in minutes (60 by
    /// default), which looks dark for most of a 60 s playlist slot; 1 makes it rise within the slot.
    private static let speeds = ["Sunrise": 1]

    /// A pack whose presets are named after their effects, so an effect used by several playlists is saved
    /// once. The playlist name starts with `icon`, which is also its quick-load button.
    private static func pack(
        _ icon: String,
        _ name: String,
        _ effects: [String],
        seconds: Int = defaultSeconds,
        fade: Int = defaultFade
    ) -> PresetPack {
        PresetPack(
            presets: effects.map { EffectPreset(name: $0, effect: $0, speed: speeds[$0]) },
            playlist: PlaylistSpec(name: "\(icon) \(name)", quickLoad: icon, secondsPerPreset: seconds, fadeSeconds: fade)
        )
    }

    // Effect names are WLED 0.15.3's; ids in PresetPacksTests.

    static let twinkleTonight = pack(
        "✨", "Twinkle Tonight", ["Twinklefox", "Fairy", "Fairytwinkle", "Glitter", "Sparkle"], seconds: slowSeconds
    )
    static let skyFullOfSparks = pack(
        "🎆", "Sky Full of Sparks", ["Fireworks 1D", "Fireworks Starburst", "Fireworks", "Popcorn", "Sparkle+"]
    )
    static let chillMode = pack(
        "🌊", "Chill Mode", ["Pacifica", "Lake", "Noise Pal", "Flow", "Aurora"], seconds: slowSeconds, fade: slowFade
    )
    static let rainbowRush = pack(
        "🌈", "Rainbow Rush", ["Rainbow", "Colorwaves", "Pride 2015", "Theater Rainbow", "Chase Rainbow"]
    )
    static let northernGlow = pack(
        "🌌", "Northern Glow", ["Aurora", "Phased Noise", "Twinkleup", "Perlin Move", "Plasma"]
    )
    static let flameOn = pack(
        "🔥", "Flame On", ["Candle", "Candle Multi", "Fire 2012", "Fire Flicker"]
    )
    /// A party mix that needs no microphone (WLED's sound-reactive effects stay dark without one).
    static let beatDrop = pack(
        "🎵", "Beat Drop", ["Strobe Rainbow", "Bpm", "Ripple Rainbow", "Chase Flash Rnd", "Dynamic"]
    )
    static let cometChasers = pack(
        "☄️", "Comet Chasers", ["Meteor", "Lighthouse", "Sinelon Rainbow", "Multi Comet", "Juggle"]
    )
    static let riseAndShine = pack(
        "🌅", "Rise & Shine", ["Sunrise", "Blends", "Breathe", "Fade", "Heartbeat"], seconds: slowSeconds, fade: slowFade
    )
    static let spookySwitch = pack(
        "🎃", "Spooky Switch", ["Halloween Eyes", "Lightning", "Strobe Mega", "Washing Machine", "Dancing Shadows"]
    )

    private static let themed = [
        twinkleTonight, skyFullOfSparks, chillMode, rainbowRush, northernGlow,
        flameOn, beatDrop, cometChasers, riseAndShine, spookySwitch
    ]

    /// Every effect of the other playlists in a new random order each loop. It cannot be edited.
    static let random: PresetPack = {
        var seen = Set<String>()
        let presets = themed.flatMap(\.presets).filter { seen.insert($0.name).inserted }
        return PresetPack(
            presets: presets,
            playlist: PlaylistSpec(
                name: "🎲 Random", quickLoad: "🎲", secondsPerPreset: defaultSeconds, fadeSeconds: defaultFade,
                shuffle: true
            ),
            locked: true
        )
    }()

    static let all = themed + [random]

    /// The built-in pack whose playlist has this name, if any.
    static func builtIn(named name: String) -> PresetPack? { all.first { $0.playlist.name == name } }

    /// The app's speed override for a preset named after an effect, if any.
    static func speed(forPreset name: String) -> Int? { speeds[name] }

    /// The default playlist: started after Set Up New Device and when playlists are first added.
    static let playsAfterSetup = skyFullOfSparks
}

/// What to do for one preset of a pack.
enum PresetStep: Equatable {
    /// A preset with this name is already on the device; it is used as is.
    case reuse(name: String, id: Int)
    /// Save at `id`: a new preset, or one put back to its defaults.
    case create(name: String, id: Int, effectId: Int, speed: Int? = nil)
    /// The device's firmware has no effect with this name.
    case missingEffect(name: String)
    /// All 250 preset slots are taken.
    case noFreeSlot(name: String)

    var name: String {
        switch self {
        case .reuse(let name, _), .create(let name, _, _, _), .missingEffect(let name), .noFreeSlot(let name):
            return name
        }
    }

    var presetId: Int? {
        switch self {
        case .reuse(_, let id), .create(_, let id, _, _): return id
        case .missingEffect, .noFreeSlot: return nil
        }
    }
}

/// What to do for the playlist.
enum PlaylistStep: Equatable {
    /// Already on the device (possibly edited by the user, which is kept); nothing to save.
    case play(id: Int)
    /// Save at `id` (new, reset to default, or a locked playlist that was changed), which also starts it.
    case save(id: Int, presetIds: [Int])
    /// None of the presets could be added, or no free slot is left.
    case skip
}

extension PlaylistStep {
    /// The playlist's preset id once the plan is carried out, or nil if it is skipped.
    var playlistId: Int? {
        switch self {
        case .play(let id), .save(let id, _): return id
        case .skip: return nil
        }
    }
}

struct PackPlan: Equatable {
    let presets: [PresetStep]
    let playlist: PlaylistStep

    var created: [PresetStep] { presets.filter { if case .create = $0 { return true } else { return false } } }
    var reused: [PresetStep] { presets.filter { if case .reuse = $0 { return true } else { return false } } }
    var unavailable: [PresetStep] { presets.filter { $0.presetId == nil } }
}

/// Decides what to add to a device, so a pack can be installed any number of times without making
/// duplicates. Matching is by name: a preset or playlist with the same name is reused, not added again,
/// so the user's edits to it are kept. Only a locked playlist is put back if it changed.
enum PresetPackPlanner {
    static let maxPresetId = 250

    /// Plans several packs from one read of `/presets.json`: each pack sees what the packs before it will
    /// save, so shared effects (e.g. Aurora) are saved once and ids never collide.
    static func planAll(_ packs: [PresetPack], presets: [String: Any], effects: [String]) -> [(pack: PresetPack, plan: PackPlan)] {
        var device = presets
        return packs.map { pack in
            let packPlan = Self.plan(pack, presets: device, effects: effects)
            for case .create(let name, let id, _, let speed) in packPlan.presets {
                var seg: [String: Any] = [:]
                if let speed { seg["sx"] = speed }
                device["\(id)"] = ["n": name, "seg": seg] as [String: Any]
            }
            if case .save(let id, let presetIds) = packPlan.playlist {
                device["\(id)"] = ["n": pack.playlist.name, "playlist": ["ps": presetIds]] as [String: Any]
            }
            return (pack, packPlan)
        }
    }

    /// - Parameters:
    ///   - presets: The device's `/presets.json`.
    ///   - effects: The device's `/json/eff`: effect names, index = effect id.
    static func plan(_ pack: PresetPack, presets: [String: Any], effects: [String]) -> PackPlan {
        plan(pack, presets: presets, effects: effects, reset: false)
    }

    /// "Reset to default": saves the pack's presets and playlist again as defined, at the ids they have
    /// now (or new ones if missing), undoing the user's edits.
    static func reset(_ pack: PresetPack, presets: [String: Any], effects: [String]) -> PackPlan {
        plan(pack, presets: presets, effects: effects, reset: true)
    }

    private static func plan(_ pack: PresetPack, presets: [String: Any], effects: [String], reset: Bool) -> PackPlan {
        let existing = existingPresets(presets)
        var taken = Set(existing.keys)
        func nextFree() -> Int? {
            guard let id = (1...maxPresetId).first(where: { !taken.contains($0) }) else { return nil }
            taken.insert(id)
            return id
        }

        let steps: [PresetStep] = pack.presets.map { preset in
            let current = existing.first { $0.value.name == preset.name }
            let effectId = effects.firstIndex(of: preset.effect)
            // A preset the app saved before its speed override existed has no speed: give it the override.
            let outdated = current != nil && preset.speed != nil && current?.value.speed == nil
            if let current, !reset, !(outdated && effectId != nil) {
                return .reuse(name: preset.name, id: current.key)
            }
            guard let effectId else { return .missingEffect(name: preset.name) }
            guard let id = current?.key ?? nextFree() else { return .noFreeSlot(name: preset.name) }
            return .create(name: preset.name, id: id, effectId: effectId, speed: preset.speed)
        }

        let presetIds = steps.compactMap(\.presetId)
        let current = existing.first { $0.value.name == pack.playlist.name }
        let enforce = reset || pack.locked
        let playlist: PlaylistStep
        if presetIds.isEmpty {
            playlist = .skip
        } else if let current, let saved = current.value.playlistPresets, !enforce || saved == presetIds {
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
        let speed: Int?
    }

    private static func existingPresets(_ presets: [String: Any]) -> [Int: Existing] {
        var result: [Int: Existing] = [:]
        for (key, value) in presets {
            guard let id = Int(key), (1...maxPresetId).contains(id),
                  let preset = value as? [String: Any], !preset.isEmpty else { continue }
            let name = (preset["n"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Preset \(id)"
            let playlist = (preset["playlist"] as? [String: Any])?["ps"] as? [Any]
            let speed = ((preset["seg"] as? [String: Any])?["sx"] as? NSNumber)?.intValue
            result[id] = Existing(
                name: name, playlistPresets: playlist?.compactMap { ($0 as? NSNumber)?.intValue }, speed: speed
            )
        }
        return result
    }
}

/// Bodies for `POST /json/state`. Note the device applies each one to the lights as it saves it.
enum PresetPackPayloads {
    private static let tenthsPerSecond = 10

    /// Saves a preset that turns the light on and runs the effect with its default settings (the firmware
    /// applies `fxdef` before `sx`, so a speed override wins).
    static func presetJSON(id: Int, name: String, effectId: Int, speed: Int? = nil) throws -> Data {
        var seg: [String: Any] = ["fx": effectId, "fxdef": true]
        if let speed { seg["sx"] = speed }
        return try json(["psave": id, "n": name, "o": true, "on": true, "seg": seg])
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
