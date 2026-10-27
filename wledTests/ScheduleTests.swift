import Foundation
import Testing
@testable import WLED

struct ScheduleTests {

    private let evening = Schedule(trigger: .time, hour: 18, minute: 30, presetId: 250, days: 0x7F, enabled: true)
    private let sunset = Schedule(trigger: .sunset, hour: 0, minute: -15, presetId: 249, days: 0x1F, enabled: true)

    private func parse(_ json: String) throws -> [Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])
    }

    private var english: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    @Test func decodesCurrentFormat() throws {
        let json = """
        [{"en":1,"hour":18,"min":30,"macro":250,"dow":127,"start":{"mon":1,"day":1},"end":{"mon":12,"day":31}},
         {"en":0,"hour":254,"min":-15,"macro":249,"dow":31,"start":{"mon":3,"day":5},"end":{"mon":10,"day":20}},
         {"en":1,"hour":255,"min":10,"macro":3,"dow":96}]
        """
        let schedules = ScheduleCodec.decode(try parse(json), currentFormat: true)
        #expect(schedules.count == 3)
        #expect(schedules[0] == evening)
        #expect(schedules[1].trigger == .sunset)
        #expect(schedules[1].minute == -15)
        #expect(!schedules[1].enabled)
        #expect(schedules[1].startMonth == 3)
        #expect(schedules[1].endDay == 20)
        #expect(schedules[2].trigger == .sunrise)
    }

    @Test func decodesLegacyFormatAndSkipsEmptySlots() throws {
        // As serialized by WLED 0.15: used time slots, then sunrise and sunset (both hour 255) always.
        let json = """
        [{"en":1,"hour":18,"min":30,"macro":250,"dow":127,"start":{"mon":1,"day":1},"end":{"mon":12,"day":31}},
         {"en":0,"hour":255,"min":0,"macro":0,"dow":127},
         {"en":1,"hour":255,"min":-15,"macro":249,"dow":31}]
        """
        #expect(ScheduleCodec.decode(try parse(json), currentFormat: false) == [evening, sunset])
    }

    @Test func encodesLegacyFormatAsAllTenSlots() throws {
        let encoded = ScheduleCodec.encode([sunset, evening], currentFormat: false)
        #expect(encoded.count == 10)
        #expect(encoded[0]["hour"] as? Int == 18)
        // Unused time slots are written empty so the device forgets deleted schedules.
        for slot in 1...7 { #expect(encoded[slot]["macro"] as? Int == 0) }
        #expect(encoded[8]["hour"] as? Int == 255)
        #expect(encoded[8]["macro"] as? Int == 0)
        #expect(encoded[9]["hour"] as? Int == 255)
        #expect(encoded[9]["macro"] as? Int == 249)
        #expect(encoded[9]["start"] == nil)
    }

    @Test func encodesCurrentFormatAndRoundTrips() throws {
        let encoded = ScheduleCodec.encode([evening, sunset], currentFormat: true)
        #expect(encoded.count == 2)
        #expect(encoded[1]["hour"] as? Int == 254)
        let data = try JSONSerialization.data(withJSONObject: encoded)
        let decoded = ScheduleCodec.decode(try #require(try JSONSerialization.jsonObject(with: data) as? [Any]), currentFormat: true)
        #expect(decoded == [evening, sunset])
    }

    @Test func legacyRoundTrip() throws {
        let data = try JSONSerialization.data(withJSONObject: ScheduleCodec.encode([evening, sunset], currentFormat: false))
        let decoded = ScheduleCodec.decode(try #require(try JSONSerialization.jsonObject(with: data) as? [Any]), currentFormat: false)
        #expect(decoded == [evening, sunset])
    }

    @Test func formatDependsOnBuild() {
        #expect(!ScheduleCodec.isCurrentFormat(buildId: 2_412_100))
        #expect(!ScheduleCodec.isCurrentFormat(buildId: nil))
        #expect(ScheduleCodec.isCurrentFormat(buildId: 2_605_010))
    }

    @Test func limits() {
        let eightTimes = Array(repeating: evening, count: 8)
        #expect(!ScheduleLimits.legacy.canAdd(eightTimes, .time))
        #expect(ScheduleLimits.legacy.canAdd(eightTimes, .sunrise))
        #expect(!ScheduleLimits.legacy.canAdd([sunset], .sunset))
        #expect(ScheduleLimits.current(isEsp8266: false).canAdd(Array(repeating: sunset, count: 63), .sunset))
        #expect(!ScheduleLimits.current(isEsp8266: true).canAdd(Array(repeating: evening, count: 16), .time))
    }

    @Test func presetNamesAndFreeSlots() throws {
        let json = #"{"0":{},"1":{"n":"Christmas","on":true},"250":{"n":"Schedule: On","on":true},"7":{"on":true}}"#
        let presets = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let names = SchedulePresets.names(presets)
        #expect(names == [1: "Christmas", 250: "Schedule: On", 7: "Preset 7"])
        #expect(SchedulePresets.find(names, name: SchedulePresets.onName) == 250)
        #expect(SchedulePresets.find(names, name: SchedulePresets.offName) == nil)
        #expect(SchedulePresets.freeSlot(names) == 249)
        let body = try #require(String(data: try SchedulePresets.saveJSON(id: 249, name: "Schedule: Off", on: false), encoding: .utf8))
        #expect(body == #"{"n":"Schedule: Off","o":true,"on":false,"psave":249}"#)
    }

    @Test func configPayload() throws {
        let data = try SchedulePayloads.configJSON(
            timers: ScheduleCodec.encode([evening], currentFormat: true),
            ntp: ["en": true],
            pin: "1234"
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.sorted() == ["if", "pin", "timers"])
        let ins = try #require((object["timers"] as? [String: Any])?["ins"] as? [[String: Any]])
        #expect(ins.count == 1)
    }

    @Test func dayTexts() {
        #expect(ScheduleDays.names(0x3F, calendar: english) == "Monday, Tuesday, Wednesday, Thursday, Friday, Saturday")
        #expect(ScheduleDays.names(0x41, calendar: english) == "Sunday, Monday")
        #expect(ScheduleDays.summary(0) == "")
        #expect(ScheduleDays.displayOrder.map { ScheduleDays.letter($0, calendar: english) } == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(ScheduleDays.toggle(0x7F, 6) == 0x3F)
        #expect(ScheduleDays.isSelected(0x40, 6))
    }
}
