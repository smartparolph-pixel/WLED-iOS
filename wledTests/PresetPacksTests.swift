import Foundation
import Testing
@testable import WLED

struct PresetPacksTests {

    /// Effect names as WLED 0.15.3 lists them: index = effect id.
    private let effects: [String] = {
        var names = (0..<120).map { "Effect \($0)" }
        names[20] = "Sparkle"
        names[49] = "Fairy"
        names[51] = "Fairytwinkle"
        names[80] = "Twinklefox"
        names[87] = "Glitter"
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
}
