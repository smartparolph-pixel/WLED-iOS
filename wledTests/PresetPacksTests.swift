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

    @Test func deletedPresetIsRecreatedButTheUsersPlaylistIsKept() throws {
        let presets = try parse(#"""
        {"1":{"n":"Twinklefox"},"3":{"n":"Fairytwinkle"},"4":{"n":"Glitter"},"9":{"n":"Sparkle"},
         "6":{"n":"✨ Twinkle Tonight","playlist":{"ps":[9,1]}}}
        """#)
        let plan = PresetPackPlanner.plan(pack, presets: presets, effects: effects)
        #expect(plan.created == [.create(name: "Fairy", id: 2, effectId: 49)])
        #expect(plan.playlist == .play(id: 6))
    }

    @Test func resetSavesThePackAgainAtTheSameIds() throws {
        let presets = try parse(#"""
        {"1":{"n":"Twinklefox","seg":{"fx":80,"sx":10}},"2":{"n":"Fairy"},"3":{"n":"Fairytwinkle"},
         "4":{"n":"Glitter"},"5":{"n":"Sparkle"},"6":{"n":"✨ Twinkle Tonight","playlist":{"ps":[5,1]}}}
        """#)
        let plan = PresetPackPlanner.reset(pack, presets: presets, effects: effects)
        #expect(plan.created.compactMap(\.presetId) == [1, 2, 3, 4, 5])
        #expect(plan.playlist == .save(id: 6, presetIds: [1, 2, 3, 4, 5]))
    }

    @Test func lockedRandomPlaylistIsPutBackWhenChanged() {
        var device: [String: Any] = [:]
        var ids: [Int] = []
        for (index, preset) in PresetPacks.random.presets.enumerated() {
            var seg: [String: Any] = [:]
            if let speed = preset.speed { seg["sx"] = speed }
            device["\(index + 1)"] = ["n": preset.name, "seg": seg] as [String: Any]
            ids.append(index + 1)
        }
        device["60"] = ["n": "🎲 Random", "playlist": ["ps": [1, 2]]] as [String: Any]
        #expect(PresetPackPlanner.plan(PresetPacks.random, presets: device, effects: effects).playlist
            == .save(id: 60, presetIds: ids))
        device["60"] = ["n": "🎲 Random", "playlist": ["ps": ids]] as [String: Any]
        #expect(PresetPackPlanner.plan(PresetPacks.random, presets: device, effects: effects).playlist == .play(id: 60))
    }

    @Test func randomShufflesEveryEffectForever() {
        let random = PresetPacks.random
        #expect(random.locked)
        #expect(random.presets.count == 48)
        #expect(random.playlist == PlaylistSpec(
            name: "🎲 Random", quickLoad: "🎲", secondsPerPreset: 20, fadeSeconds: 1, loop: true, shuffle: true
        ))
        #expect(PresetPacks.all.filter { $0 != random }.allSatisfy { !$0.locked })
    }

    @Test func sunriseGetsAOneMinuteSpeedAndOldCopiesAreUpdated() throws {
        #expect(PresetPacks.riseAndShine.presets.first == EffectPreset(name: "Sunrise", effect: "Sunrise", speed: 1))
        let data = try PresetPackPayloads.presetJSON(id: 7, name: "Sunrise", effectId: 104, speed: 1)
        #expect(String(data: data, encoding: .utf8) ==
            #"{"n":"Sunrise","o":true,"on":true,"psave":7,"seg":{"fx":104,"fxdef":true,"sx":1}}"#)

        // Saved by an earlier version without a speed: overwritten in place. Edited by the user: kept.
        let old = PresetPackPlanner.plan(
            PresetPacks.riseAndShine, presets: try parse(#"{"7":{"n":"Sunrise","seg":{"fx":104}}}"#), effects: effects
        )
        #expect(old.presets.first == .create(name: "Sunrise", id: 7, effectId: 104, speed: 1))
        let edited = PresetPackPlanner.plan(
            PresetPacks.riseAndShine, presets: try parse(#"{"7":{"n":"Sunrise","seg":{"sx":5}}}"#), effects: effects
        )
        #expect(edited.presets.first == .reuse(name: "Sunrise", id: 7))
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

    @Test func elevenPlaylistsEachStartingWithItsIcon() throws {
        #expect(PresetPacks.all.count == 11)
        #expect(Set(PresetPacks.all.map(\.playlist.name)).count == 11)
        for pack in PresetPacks.all {
            let icon = try #require(pack.playlist.quickLoad)
            #expect(pack.playlist.name.hasPrefix("\(icon) "), "\(pack.playlist.name)")
        }
        #expect(PresetPacks.playsAfterSetup.playlist.name == "🎆 Sky Full of Sparks")
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

    @Test func planAllSavesEverythingOnceFromOneRead() {
        let plans = PresetPackPlanner.planAll(PresetPacks.all, presets: [:], effects: effects)
        // 48 distinct effects (Aurora is shared) plus 11 playlists, on ids 1...59 without gaps or clashes.
        let created = plans.flatMap { $0.plan.created.compactMap(\.presetId) }
        let playlists = plans.compactMap { $0.plan.playlist.playlistId }
        #expect(created.count == 48)
        #expect((created + playlists).sorted() == Array(1...59))
        let aurora = plans.flatMap(\.plan.presets).filter { $0.name == "Aurora" }
        #expect(aurora.filter { if case .create = $0 { return true } else { return false } }.count == 1)
        // Reused by Northern Glow and Random.
        #expect(aurora.filter { if case .reuse = $0 { return true } else { return false } }.count == 2)
    }

    @Test func planAllOnAFullyPreparedDeviceChangesNothing() {
        // Simulate the device after the first run, then plan again: nothing is created or saved.
        var device: [String: Any] = [:]
        for (pack, plan) in PresetPackPlanner.planAll(PresetPacks.all, presets: [:], effects: effects) {
            for case .create(let name, let id, _, let speed) in plan.presets {
                var seg: [String: Any] = [:]
                if let speed { seg["sx"] = speed }
                device["\(id)"] = ["n": name, "seg": seg] as [String: Any]
            }
            if case .save(let id, let presetIds) = plan.playlist {
                device["\(id)"] = ["n": pack.playlist.name, "playlist": ["ps": presetIds]] as [String: Any]
            }
        }
        let again = PresetPackPlanner.planAll(PresetPacks.all, presets: device, effects: effects)
        #expect(again.allSatisfy { pair in
            guard pair.plan.created.isEmpty, case .play = pair.plan.playlist else { return false }
            return true
        })
        #expect(Set(again.compactMap { $0.plan.playlist.playlistId }).count == 11)
    }

    // MARK: - Editor

    @Test func devicePresetsSplitPresetsAndPlaylists() throws {
        let device = DevicePresets(parsing: try parse(#"""
        {"0":{},
         "1":{"n":"Twinklefox","on":true,"seg":{"fx":80,"fxdef":true}},
         "2":{"n":"Sunrise","on":true,"bri":90,"seg":{"fx":104,"fxdef":true,"sx":1,"ix":40,"pal":5}},
         "3":{"n":"From the web page","on":true,"seg":[{"id":0,"fx":9}]},
         "6":{"n":"✨ Twinkle Tonight","ql":"✨","on":true,
              "playlist":{"ps":[1,2],"dur":[600,600],"transition":[10,10],"repeat":0,"end":0,"r":0}},
         "7":{"n":"Mine","playlist":{"ps":[2],"dur":150,"transition":30,"r":1}}}
        """#))
        #expect(device.presets.map(\.id) == [1, 2, 3])
        #expect(device.preset(2) == SavedPreset(
            id: 2, name: "Sunrise", effectId: 104,
            settings: EffectSettings(speed: 1, intensity: 40, palette: 5, brightness: 90)
        ))
        #expect(device.preset(3)?.editable == false)
        #expect(device.playlists[0] == SavedPlaylist(
            id: 6, name: "✨ Twinkle Tonight", quickLoad: "✨", presetIds: [1, 2], seconds: 60, fadeSeconds: 1, shuffle: false
        ))
        #expect(device.playlists[1] == SavedPlaylist(
            id: 7, name: "Mine", quickLoad: nil, presetIds: [2], seconds: 15, fadeSeconds: 3, shuffle: true
        ))
        #expect(device.custom.map(\.name) == ["Mine"])
        #expect(device.freeId() == 4)
    }

    @Test func effectControlsFollowTheFirmwareMetadata() {
        let sunrise = EffectControls(parsing: "Time [min],Width;;!;;sx=60")
        #expect(sunrise.speedLabel == "Time [min]")
        #expect(sunrise.intensityLabel == "Width")
        #expect(sunrise.usesPalette)
        #expect(sunrise.defaults.speed == 60)
        let fade = EffectControls(parsing: "!;!,!;!;01")
        #expect(fade.speedLabel == "")
        #expect(fade.intensityLabel == nil)
        #expect(!EffectControls(parsing: "!,!;!,!;;1").usesPalette)
        #expect(EffectControls(parsing: "").intensityLabel == "")
    }

    @Test func editorPayloads() throws {
        let save = try PresetEditorPayloads.presetJSON(
            id: 2, name: "Sunrise", effectId: 104, settings: EffectSettings(speed: 3, brightness: 80)
        )
        #expect(String(data: save, encoding: .utf8) ==
            #"{"bri":80,"n":"Sunrise","o":true,"on":true,"psave":2,"seg":{"fx":104,"fxdef":true,"sx":3}}"#)
        let preview = try PresetEditorPayloads.previewJSON(effectId: 104, settings: EffectSettings(palette: 4))
        #expect(String(data: preview, encoding: .utf8) == #"{"on":true,"seg":{"fx":104,"fxdef":true,"pal":4}}"#)
        let playlist = try PresetEditorPayloads.playlistJSON(SavedPlaylist(
            id: 7, name: "Mine", quickLoad: nil, presetIds: [2, 1], seconds: 15, fadeSeconds: 2, shuffle: true
        ))
        let body = try #require(try JSONSerialization.jsonObject(with: playlist) as? [String: Any])
        #expect(body["psave"] as? Int == 7)
        #expect(body["ql"] == nil)
        let list = try #require(body["playlist"] as? [String: Any])
        #expect(list["dur"] as? [Int] == [150, 150])
        #expect(list["transition"] as? [Int] == [20, 20])
        #expect(list["r"] as? Bool == true)
        #expect(String(data: try PresetEditorPayloads.deleteJSON(id: 7), encoding: .utf8) == #"{"pdel":7}"#)
    }

    // MARK: - Repair

    private static let goodFile = #"{"0":{},"1":{"n":"Twinklefox","on":true,"seg":{"fx":80,"fxdef":true}},"6":{"n":"✨ Twinkle Tonight","playlist":{"ps":[1]}}}"#

    @Test func validFileIsKeptAsIs() {
        let data = Data(Self.goodFile.utf8)
        #expect(PresetsFileRepair.problem(data) == nil)
        let result = PresetsFileRepair.repair(data)
        #expect(result.ids == ["0", "1", "6"])
        #expect(result.kept == 2)
        #expect(result.dropped == 0)
    }

    @Test func leftoverTextAfterTheLastEntryIsDropped() throws {
        let data = Data((Self.goodFile + #"ard":true}}}"#).utf8)
        #expect(PresetsFileRepair.problem(data) != nil)
        let result = PresetsFileRepair.repair(data)
        #expect(result.ids == ["0", "1", "6"])
        #expect(PresetsFileRepair.problem(try result.json()) == nil)
    }

    @Test func cutOffEntryInTheMiddleIsDroppedAndTheRestKept() {
        let text = #"{"0":{},"1":{"n":"Twinklefox","seg":{"fx":80,"fxd ,"2":{"n":"Fairy","seg":{"fx":49}},"3":{"n":"Glitter"}}"#
        let result = PresetsFileRepair.repair(Data(text.utf8))
        #expect(result.ids == ["0", "2", "3"])
        #expect(result.dropped == 1)
    }

    @Test func repeatedIdKeepsTheFirstLikeTheFirmware() {
        let result = PresetsFileRepair.repair(Data(#"{"0":{},"5":{"n":"First"},"5":{"n":"Second"}}"#.utf8))
        #expect((result.presets["5"] as? [String: Any])?["n"] as? String == "First")
        #expect(result.dropped == 1)
    }

    @Test func bracesInsideNamesDoNotConfuseTheScan() {
        let result = PresetsFileRepair.repair(Data(#"{"0":{},"7":{"n":"My {fun} \"preset\"","seg":{"fx":9}}}"#.utf8))
        #expect((result.presets["7"] as? [String: Any])?["n"] as? String == "My {fun} \"preset\"")
    }
}
