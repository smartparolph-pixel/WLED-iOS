import Foundation
import Testing
@testable import WLED

struct PresetPacksTests {

    /// Every effect the packs use, with its id in WLED 0.15.3 (FX.h). All are 1D effects that need no
    /// microphone, so they animate on a single LED strip.
    private static let wled0153: [String: Int] = [
        "Twinklefox": 80, "Fairy": 49, "Fairytwinkle": 51, "Glitter": 87, "Sparkle": 20,
        "Fireworks 1D": 90, "Fireworks Starburst": 89, "Fireworks": 42, "Popcorn": 95, "Sparkle+": 22,
        "Pacifica": 101, "Lake": 75, "Noise Pal": 107, "Flow": 110, "Aurora": 38,
        "Rainbow": 9, "Colorwaves": 67, "Pride 2015": 63, "Theater Rainbow": 14, "Chase Rainbow": 30,
        "Phased Noise": 109, "Twinkleup": 106, "Perlin Move": 147, "Plasma": 97,
        "Candle": 88, "Candle Multi": 102, "Fire 2012": 66, "Fire Flicker": 45,
        "Strobe Rainbow": 24, "Bpm": 68, "Ripple Rainbow": 99, "Chase Flash Rnd": 32, "Dynamic": 7,
        "Meteor": 76, "Lighthouse": 41, "Sinelon Rainbow": 94, "Multi Comet": 59, "Juggle": 64,
        "Sunrise": 104, "Blends": 115, "Breathe": 2, "Fade": 12, "Heartbeat": 100,
        "Halloween Eyes": 82, "Lightning": 57, "Strobe Mega": 25, "Washing Machine": 113,
        "Dancing Shadows": 112
    ]

    /// `/json/eff` as WLED 0.15.3 returns it: index = effect id.
    private let effects: [String] = {
        var names = (0..<190).map { "Effect \($0)" }
        for (name, id) in PresetPacksTests.wled0153 { names[id] = name }
        return names
    }()

    private let pack = PresetPacks.twinkleTonight

    private func parse(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func emptyDeviceGetsLowestFreeIdsAndFirmwareEffectIds() throws {
        let plan = PresetPackPlanner.plan(pack, presets: try parse(#"{"0":{}}"#), effects: effects)
        #expect(plan.presets == [
            .create(name: "Twinklefox", id: 1, effectId: 80),
            .create(name: "Fairy", id: 2, effectId: 49),
            .create(name: "Fairytwinkle", id: 3, effectId: 51),
            .create(name: "Glitter", id: 4, effectId: 87),
            .create(name: "Sparkle", id: 5, effectId: 20)
        ])
        #expect(plan.playlist == .save(id: 6, presetIds: [1, 2, 3, 4, 5]))
    }

    @Test func skipsTakenSlotsIncludingSchedulePresets() throws {
        let presets = try parse(#"{"1":{"n":"Mine"},"3":{"n":"Also mine"},"250":{"n":"Schedule: Off"}}"#)
        let plan = PresetPackPlanner.plan(pack, presets: presets, effects: effects)
        #expect(plan.created.compactMap(\.presetId) == [2, 4, 5, 6, 7])
        #expect(plan.playlist == .save(id: 8, presetIds: [2, 4, 5, 6, 7]))
    }

    @Test func runningTwiceAddsNothingAndOnlyPlays() throws {
        let presets = try parse(#"""
        {"1":{"n":"Twinklefox"},"2":{"n":"Fairy"},"3":{"n":"Fairytwinkle"},"4":{"n":"Glitter"},"5":{"n":"Sparkle"},
         "6":{"n":"✨ Twinkle Tonight","playlist":{"ps":[1,2,3,4,5]}}}
        """#)
        let plan = PresetPackPlanner.plan(pack, presets: presets, effects: effects)
        #expect(plan.created.isEmpty)
        #expect(plan.reused.count == 5)
        #expect(plan.playlist == .play(id: 6))
    }

    @Test func movedPresetUpdatesThePlaylistInPlace() throws {
        let presets = try parse(#"""
        {"1":{"n":"Twinklefox"},"3":{"n":"Fairytwinkle"},"4":{"n":"Glitter"},"9":{"n":"Sparkle"},
         "6":{"n":"✨ Twinkle Tonight","playlist":{"ps":[1,2,3,4,5]}}}
        """#)
        let plan = PresetPackPlanner.plan(pack, presets: presets, effects: effects)
        #expect(plan.created == [.create(name: "Fairy", id: 2, effectId: 49)])
        #expect(plan.playlist == .save(id: 6, presetIds: [1, 2, 3, 4, 9]))
    }

    @Test func missingEffectIsLeftOutOfThePlaylist() throws {
        var older = effects
        older[87] = "RSVD"
        let plan = PresetPackPlanner.plan(pack, presets: [:], effects: older)
        #expect(plan.unavailable == [.missingEffect(name: "Glitter")])
        #expect(plan.playlist == .save(id: 5, presetIds: [1, 2, 3, 4]))
    }

    @Test func fullDeviceSkipsThePlaylist() {
        var full: [String: Any] = [:]
        for id in 1...250 { full["\(id)"] = ["n": "P\(id)"] }
        let plan = PresetPackPlanner.plan(pack, presets: full, effects: effects)
        #expect(plan.unavailable.count == 5)
        #expect(plan.playlist == .skip)
    }

    @Test func presetPayloadRunsTheEffectWithItsDefaults() throws {
        let data = try PresetPackPayloads.presetJSON(id: 1, name: "Twinklefox", effectId: 80)
        #expect(String(data: data, encoding: .utf8) ==
            #"{"n":"Twinklefox","o":true,"on":true,"psave":1,"seg":{"fx":80,"fxdef":true}}"#)
    }

    @Test func playlistPayloadUsesTenthsOfSecondsAndLoopsForever() throws {
        let data = try PresetPackPayloads.playlistJSON(pack.playlist, id: 6, presetIds: [1, 2, 3, 4, 5])
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["psave"] as? Int == 6)
        #expect(body["n"] as? String == "✨ Twinkle Tonight")
        #expect(body["ql"] as? String == "✨")
        #expect(body["on"] as? Bool == true)
        let playlist = try #require(body["playlist"] as? [String: Any])
        #expect(playlist["ps"] as? [Int] == [1, 2, 3, 4, 5])
        #expect(playlist["dur"] as? [Int] == Array(repeating: 600, count: 5))
        #expect(playlist["transition"] as? [Int] == Array(repeating: 10, count: 5))
        #expect(playlist["repeat"] as? Int == 0)
        #expect(playlist["r"] as? Bool == false)
    }

    @Test func namesFitTheFirmwareLimit() {
        // WLED keeps 32 bytes of a preset name; quick-load labels are at most 2 characters.
        for pack in PresetPacks.all {
            for name in pack.presets.map(\.name) + [pack.playlist.name] {
                #expect(name.utf8.count <= 32, "\(name)")
            }
            #expect((pack.playlist.quickLoad ?? "").count <= 2)
        }
    }

    @Test func everyPackEffectIsAWled0153StripEffect() {
        for preset in PresetPacks.all.flatMap(\.presets) {
            #expect(Self.wled0153[preset.effect] != nil, "\(preset.effect)")
            #expect(preset.name == preset.effect)
        }
    }

    @Test func tenPlaylistsEachStartingWithItsIcon() throws {
        #expect(PresetPacks.all.count == 10)
        #expect(Set(PresetPacks.all.map(\.playlist.name)).count == 10)
        for pack in PresetPacks.all {
            let icon = try #require(pack.playlist.quickLoad)
            #expect(pack.playlist.name.hasPrefix("\(icon) "), "\(pack.playlist.name)")
        }
        #expect(PresetPacks.playsAfterSetup.playlist.name == "✨ Twinkle Tonight")
    }

    @Test func slowPlaylistsPlayLonger() {
        #expect(PresetPacks.twinkleTonight.playlist.secondsPerPreset == 60)
        for pack in [PresetPacks.chillMode, PresetPacks.riseAndShine] {
            #expect(pack.playlist.secondsPerPreset == 60)
            #expect(pack.playlist.fadeSeconds == 3)
        }
        #expect(PresetPacks.skyFullOfSparks.playlist.secondsPerPreset == 20)
        #expect(PresetPacks.skyFullOfSparks.playlist.fadeSeconds == 1)
    }

    @Test func effectSharedBetweenPlaylistsIsSavedOnce() throws {
        // Chill Mode already added "Aurora" as preset 5; Northern Glow reuses it.
        let plan = PresetPackPlanner.plan(PresetPacks.northernGlow, presets: try parse(#"{"5":{"n":"Aurora"}}"#), effects: effects)
        #expect(plan.reused == [.reuse(name: "Aurora", id: 5)])
        #expect(plan.created.count == 4)
    }

    @Test func summaryOfAddAll() {
        let done = PackInstallResult.done(playlistName: "", created: [], unavailable: [], verified: true)
        let outcomes = PresetPacks.all.map { PackOutcome(pack: $0, result: $0 == PresetPacks.flameOn ? .unreachable : done) }
        let text = PackOutcome.summary(outcomes)
        #expect(text.contains("9"))
        #expect(text.contains("✨ Twinkle Tonight"))
        #expect(text.contains("🔥 Flame On"))
    }
}
