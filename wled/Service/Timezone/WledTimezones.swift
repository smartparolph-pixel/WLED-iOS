import Foundation

/// One daylight-saving transition rule, in the format of the Arduino Timezone library that WLED
/// uses (`TimeChangeRule` in wled00/ntp.cpp).
struct WledTimeChangeRule: Equatable {
    /// `WledTimezones.last` or 1...4 for First...Fourth.
    let week: Int
    /// 1 = Sunday ... 7 = Saturday.
    let dayOfWeek: Int
    /// 1 = January ... 12 = December.
    let month: Int
    /// Local hour at which the change happens.
    let hour: Int
    /// UTC offset in effect after the change.
    let offsetMinutes: Int
}

/// One entry of WLED's built-in timezone dropdown. `index` is the value stored as `if.ntp.tz`.
struct WledTimezone {
    let index: Int
    let label: String
    let dst: WledTimeChangeRule
    let std: WledTimeChangeRule
}

/// What to send to the device for a given IANA zone.
struct WledTimezoneSetting: Equatable {
    /// Value for `if.ntp.tz`.
    let index: Int
    /// Value for `if.ntp.offset`, added on top of the zone's own offset.
    let offsetSeconds: Int
    /// False when no built-in zone follows the same daylight-saving rules: the device shows the
    /// right time now but will not change its clock automatically.
    let exact: Bool
}

/// WLED firmware only knows the 25 zones below. This maps any IANA zone (from the phone's own copy
/// of the tz database) onto the closest built-in zone plus a fixed UTC offset.
enum WledTimezones {
    static let last = 0
    /// `utcOffsetSecs` is limited to this range by the WLED settings page.
    static let maxOffsetSeconds = 65_500

    private static let secondsPerDay: Int64 = 86_400
    private static let sampleDays = 366
    private static let sampleHourUTC: Int64 = 12

    private static func rule(_ week: Int, _ month: Int, _ hour: Int, _ offsetMinutes: Int) -> WledTimeChangeRule {
        WledTimeChangeRule(week: week, dayOfWeek: 1, month: month, hour: hour, offsetMinutes: offsetMinutes)
    }

    private static func fixed(_ offsetMinutes: Int) -> WledTimeChangeRule {
        rule(last, 3, 1, offsetMinutes)
    }

    private static func zone(_ index: Int, _ label: String, fixedOffset minutes: Int) -> WledTimezone {
        WledTimezone(index: index, label: label, dst: fixed(minutes), std: fixed(minutes))
    }

    /// Copied from TZ_TABLE in wled00/ntp.cpp and the labels in settings_time.htm. Order matters.
    static let all: [WledTimezone] = [
        zone(0, "GMT(UTC)", fixedOffset: 0),
        WledTimezone(index: 1, label: "GMT/BST", dst: rule(last, 3, 1, 60), std: rule(last, 10, 2, 0)),
        WledTimezone(index: 2, label: "CET/CEST", dst: rule(last, 3, 2, 120), std: rule(last, 10, 3, 60)),
        WledTimezone(index: 3, label: "EET/EEST", dst: rule(last, 3, 3, 180), std: rule(last, 10, 4, 120)),
        WledTimezone(index: 4, label: "US-EST/EDT", dst: rule(2, 3, 2, -240), std: rule(1, 11, 2, -300)),
        WledTimezone(index: 5, label: "US-CST/CDT", dst: rule(2, 3, 2, -300), std: rule(1, 11, 2, -360)),
        WledTimezone(index: 6, label: "US-MST/MDT", dst: rule(2, 3, 2, -360), std: rule(1, 11, 2, -420)),
        zone(7, "US-AZ", fixedOffset: -420),
        WledTimezone(index: 8, label: "US-PST/PDT", dst: rule(2, 3, 2, -420), std: rule(1, 11, 2, -480)),
        zone(9, "CST (AWST, PHST)", fixedOffset: 480),
        zone(10, "JST (KST)", fixedOffset: 540),
        WledTimezone(index: 11, label: "AEST/AEDT", dst: rule(1, 10, 2, 660), std: rule(1, 4, 3, 600)),
        WledTimezone(index: 12, label: "NZST/NZDT", dst: rule(last, 9, 2, 780), std: rule(1, 4, 3, 720)),
        zone(13, "North Korea", fixedOffset: 510),
        zone(14, "IST (India)", fixedOffset: 330),
        zone(15, "CA-Saskatchewan", fixedOffset: -360),
        zone(16, "ACST", fixedOffset: 570),
        WledTimezone(index: 17, label: "ACST/ACDT", dst: rule(1, 10, 2, 630), std: rule(1, 4, 3, 570)),
        zone(18, "HST (Hawaii)", fixedOffset: -600),
        zone(19, "NOVT (Novosibirsk)", fixedOffset: 420),
        WledTimezone(index: 20, label: "AKST/AKDT (Anchorage)", dst: rule(2, 3, 2, -480), std: rule(1, 11, 2, -540)),
        zone(21, "MX-CST", fixedOffset: -360),
        zone(22, "PKT (Pakistan)", fixedOffset: 300),
        zone(23, "BRT (Brasília)", fixedOffset: -180),
        zone(24, "AWST (Perth)", fixedOffset: 480)
    ]

    /// Picks the built-in zone whose daylight-saving behaviour matches `zoneOffsetSecondsAt` over the
    /// coming year, preferring an exact match with no extra offset.
    ///
    /// - Parameters:
    ///   - fromEpochSeconds: Start of the year that is compared.
    ///   - zoneOffsetSecondsAt: UTC offset of the target zone at a given UTC instant (epoch seconds).
    static func match(fromEpochSeconds: Int64, zoneOffsetSecondsAt: (Int64) -> Int) -> WledTimezoneSetting {
        let firstSample = floorDiv(fromEpochSeconds, secondsPerDay) * secondsPerDay + sampleHourUTC * 3_600
        let samples = (0..<sampleDays).map { firstSample + Int64($0) * secondsPerDay }
        let zoneOffsets = samples.map(zoneOffsetSecondsAt)

        var best: (zone: WledTimezone, diff: Int)?
        for candidate in all {
            let diffs = Set(samples.indices.map { zoneOffsets[$0] - offsetSecondsAt(candidate, samples[$0]) })
            guard diffs.count == 1, let diff = diffs.first, abs(diff) <= maxOffsetSeconds else { continue }
            if best == nil || abs(diff) < abs(best?.diff ?? 0) {
                best = (candidate, diff)
            }
        }
        guard let best else {
            return WledTimezoneSetting(index: 0, offsetSeconds: zoneOffsets[0], exact: false)
        }
        return WledTimezoneSetting(index: best.zone.index, offsetSeconds: best.diff, exact: true)
    }

    /// UTC offset WLED applies for `zone` at `epochSeconds`, mirroring Timezone::toLocal.
    static func offsetSecondsAt(_ zone: WledTimezone, _ epochSeconds: Int64) -> Int {
        (isDst(zone, epochSeconds) ? zone.dst.offsetMinutes : zone.std.offsetMinutes) * 60
    }

    private static func isDst(_ zone: WledTimezone, _ epochSeconds: Int64) -> Bool {
        if zone.dst.offsetMinutes == zone.std.offsetMinutes { return false }
        let year = civilYear(floorDiv(epochSeconds, secondsPerDay))
        let dstStartUTC = localTransition(zone.dst, year) - Int64(zone.std.offsetMinutes * 60)
        let stdStartUTC = localTransition(zone.std, year) - Int64(zone.dst.offsetMinutes * 60)
        // Northern hemisphere: DST between start and end. Southern: DST outside the winter window.
        if stdStartUTC > dstStartUTC {
            return epochSeconds >= dstStartUTC && epochSeconds < stdStartUTC
        }
        return !(epochSeconds >= stdStartUTC && epochSeconds < dstStartUTC)
    }

    /// Mirrors Timezone::toTime_t: local time of `rule` in `year`, as if it were UTC.
    private static func localTransition(_ rule: WledTimeChangeRule, _ year: Int) -> Int64 {
        var month = rule.month
        var ruleYear = year
        var week = rule.week
        if week == last {
            month += 1
            if month > 12 {
                month = 1
                ruleYear += 1
            }
            week = 1
        }
        let firstOfMonth = daysFromCivil(year: ruleYear, month: month, day: 1)
        let shift = floorMod(Int64(rule.dayOfWeek - weekday(firstOfMonth)), 7) + Int64((week - 1) * 7)
        var days = firstOfMonth + shift
        if rule.week == last { days -= 7 }
        return days * secondsPerDay + Int64(rule.hour) * 3_600
    }

    /// 1 = Sunday ... 7 = Saturday. 1970-01-01 was a Thursday.
    private static func weekday(_ epochDay: Int64) -> Int {
        Int(floorMod(epochDay + 4, 7)) + 1
    }

    // Howard Hinnant's civil-calendar algorithms (proleptic Gregorian).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let mp = Int64((month + 9) % 12)
        let doy = (153 * mp + 2) / 5 + Int64(day) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civilYear(_ epochDay: Int64) -> Int {
        let z = epochDay + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let month = mp < 10 ? mp + 3 : mp - 9
        return Int(yoe + era * 400 + (month <= 2 ? 1 : 0))
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    private static func floorMod(_ a: Int64, _ b: Int64) -> Int64 {
        a - floorDiv(a, b) * b
    }
}
