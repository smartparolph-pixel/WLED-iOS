import Foundation
import Testing
@testable import WLED

struct TimezoneTests {

    // 2026-01-01T00:00:00Z
    private let from: Int64 = 1_767_225_600

    private func matchFor(_ id: String) throws -> WledTimezoneSetting {
        let zone = try #require(TimeZone(identifier: id))
        return WledTimezones.match(fromEpochSeconds: from) { seconds in
            zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
    }

    @Test func tableMatchesFirmwareOrder() {
        #expect(WledTimezones.all.count == 25)
        #expect(WledTimezones.all.map(\.index) == Array(0..<25))
    }

    @Test func civilDays() {
        #expect(WledTimezones.daysFromCivil(year: 1970, month: 1, day: 1) == 0)
        #expect(WledTimezones.daysFromCivil(year: 2000, month: 3, day: 1) == 11_017)
        #expect(WledTimezones.daysFromCivil(year: 2026, month: 1, day: 1) == 20_454)
    }

    @Test func centralEuropeSwitchesAtTheRightInstant() {
        let cet = WledTimezones.all[2]
        // Last Sunday of March 2026 is the 29th; the switch happens at 01:00 UTC.
        let toSummer: Int64 = 1_774_746_000
        #expect(WledTimezones.offsetSecondsAt(cet, toSummer - 1) == 3_600)
        #expect(WledTimezones.offsetSecondsAt(cet, toSummer) == 7_200)
        // Last Sunday of October 2026 is the 25th, again at 01:00 UTC.
        let toWinter: Int64 = 1_792_890_000
        #expect(WledTimezones.offsetSecondsAt(cet, toWinter - 1) == 7_200)
        #expect(WledTimezones.offsetSecondsAt(cet, toWinter) == 3_600)
    }

    @Test(arguments: [
        ("Europe/London", 1), ("Europe/Lisbon", 1), ("Europe/Berlin", 2), ("Europe/Athens", 3),
        ("America/New_York", 4), ("America/Toronto", 4), ("America/Chicago", 5), ("America/Denver", 6),
        ("America/Phoenix", 7), ("America/Los_Angeles", 8), ("Asia/Manila", 9), ("Asia/Tokyo", 10),
        ("Australia/Sydney", 11), ("Pacific/Auckland", 12), ("Asia/Kolkata", 14), ("Australia/Adelaide", 17),
        ("Pacific/Honolulu", 18), ("America/Anchorage", 20), ("Asia/Karachi", 22)
    ])
    func zonesWithMatchingRules(id: String, index: Int) throws {
        #expect(try matchFor(id) == WledTimezoneSetting(index: index, offsetSeconds: 0, exact: true))
    }

    @Test func fixedOffsetZoneWithoutNamedEntryUsesNearestPlusOffset() throws {
        #expect(try matchFor("Asia/Kathmandu") == WledTimezoneSetting(index: 14, offsetSeconds: 900, exact: true))
        #expect(try matchFor("Asia/Dubai") == WledTimezoneSetting(index: 22, offsetSeconds: -3_600, exact: true))
    }

    @Test func unsupportedDaylightSavingRulesAreFlagged() throws {
        let chile = try matchFor("America/Santiago")
        #expect(!chile.exact)
        #expect(chile.index == 0)
    }

    @Test func catalogDropsNonGeographicIdsAndSortsByOffset() {
        let now = Date(timeIntervalSince1970: 1_768_478_400)
        let options = TimezoneCatalog.options(
            identifiers: ["Asia/Manila", "America/New_York", "Etc/GMT+5", "Europe/Berlin", "GMT",
                          "America/Argentina/Buenos_Aires"],
            now: now,
            locale: Locale(identifier: "en_US")
        )
        #expect(options.map(\.id) == ["America/New_York", "America/Argentina/Buenos_Aires", "Europe/Berlin", "Asia/Manila"])
        #expect(options[1].city == "Buenos Aires")
        #expect(options[1].region == "America")
        #expect(TimezoneCatalog.filter(options, query: "manila").map(\.id) == ["Asia/Manila"])
        #expect(TimezoneCatalog.filter(options, query: "UTC+08").map(\.id) == ["Asia/Manila"])
    }

    @Test func formatsOffsets() {
        #expect(TimezonePayloads.formatOffset(20_700) == "UTC+05:45")
        #expect(TimezonePayloads.formatOffset(-12_600) == "UTC−03:30")
        #expect(TimezonePayloads.formatOffset(0) == "UTC+00:00")
    }

    @Test func configJSONEnablesNtpAndOnlyTouchesTimezone() throws {
        let setting = WledTimezoneSetting(index: 14, offsetSeconds: 900, exact: true)
        let data = try TimezonePayloads.configJSON(setting, pin: "1234")
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.sorted() == ["if", "pin"])
        #expect(object["pin"] as? String == "1234")
        let ntp = try #require((object["if"] as? [String: Any])?["ntp"] as? [String: Any])
        #expect(ntp["en"] as? Bool == true)
        #expect(ntp["tz"] as? Int == 14)
        #expect(ntp["offset"] as? Int == 900)
    }

    @Test func provisioningPayloadCarriesTimezone() throws {
        let data = try ProvisioningPayloads.wifiConfigJSON(
            ssid: "Home",
            password: "secret123",
            timezone: WledTimezoneSetting(index: 9, offsetSeconds: 0, exact: true)
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.sorted() == ["if", "nw"])
        let ntp = try #require((object["if"] as? [String: Any])?["ntp"] as? [String: Any])
        #expect(ntp["tz"] as? Int == 9)
    }
}
