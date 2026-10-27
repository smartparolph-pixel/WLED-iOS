import Foundation

enum ScheduleTrigger: CaseIterable, Equatable {
    case time, sunrise, sunset
}

/// One entry of WLED's "Time-controlled presets" (`timers.ins` in cfg.json). The same list is shown
/// under Config → Time & Macros on the device, so nothing is stored in the app.
struct Schedule: Equatable {
    var trigger: ScheduleTrigger
    /// 0...23 for `.time` (24 means every hour). Unused for sunrise/sunset.
    var hour: Int
    /// 0...59 for `.time`, otherwise the offset in minutes from sunrise/sunset.
    var minute: Int
    /// Preset applied when the schedule fires. 0 means none.
    var presetId: Int
    /// Bit mask, bit 0 = Monday ... bit 6 = Sunday (WLED's `dow`).
    var days: Int
    var enabled: Bool
    var startMonth = 1
    var startDay = 1
    var endMonth = 12
    var endDay = 31

    static let allDays = 0x7F
}

/// How many schedules a device can hold.
struct ScheduleLimits: Equatable {
    let maxTotal: Int
    let maxTime: Int
    let maxSun: Int
    let maxOffsetMinutes: Int

    func canAdd(_ schedules: [Schedule], _ trigger: ScheduleTrigger) -> Bool {
        if schedules.count >= maxTotal { return false }
        let sameKind = schedules.filter { $0.trigger == trigger }.count
        return sameKind < (trigger == .time ? maxTime : maxSun)
    }

    /// WLED 0.14/0.15: 8 time slots, then one sunrise and one sunset slot.
    static let legacy = ScheduleLimits(maxTotal: 10, maxTime: 8, maxSun: 1, maxOffsetMinutes: 59)

    /// WLED 16.x: a free list of WLED_MAX_TIMERS entries (16 on ESP8266, 64 otherwise).
    static func current(isEsp8266: Bool) -> ScheduleLimits {
        let max = isEsp8266 ? 16 : 64
        return ScheduleLimits(maxTotal: max, maxTime: max, maxSun: max, maxOffsetMinutes: 120)
    }
}

/// Reads and writes `timers.ins` in both firmware formats.
///
/// Legacy firmware (before build `currentFormatBuild`) keeps 10 fixed slots and only overwrites the
/// slots present in the JSON, so a shorter list would leave deleted schedules behind. It is therefore
/// always written as exactly 10 entries. Sunrise and sunset both use hour 255 there, told apart by
/// position. Newer firmware clears the list on every write and uses 255 / 254.
enum ScheduleCodec {
    static let currentFormatBuild = 2_605_010
    private static let hourSunrise = 255
    private static let hourSunset = 254
    private static let legacyTimeSlots = 8

    static func isCurrentFormat(buildId: Int64?) -> Bool {
        (buildId ?? 0) >= Int64(currentFormatBuild)
    }

    static func decode(_ ins: [Any], currentFormat: Bool) -> [Schedule] {
        var legacySunSeen = 0
        return ins.compactMap { item -> Schedule? in
            guard let timer = item as? [String: Any] else { return nil }
            let hour = int(timer["hour"])
            let trigger: ScheduleTrigger
            if hour == hourSunset && currentFormat {
                trigger = .sunset
            } else if hour != hourSunrise {
                trigger = .time
            } else if currentFormat {
                trigger = .sunrise
            } else {
                legacySunSeen += 1
                trigger = legacySunSeen == 1 ? .sunrise : .sunset
            }
            return schedule(from: timer, trigger: trigger, hour: hour)
        }
    }

    private static func schedule(from timer: [String: Any], trigger: ScheduleTrigger, hour: Int) -> Schedule? {
        let preset = int(timer["macro"])
        let minute = int(timer["min"])
        let isEmptySlot = preset == 0 && (trigger != .time || (hour == 0 && minute == 0))
        if isEmptySlot { return nil }
        let start = timer["start"] as? [String: Any]
        let end = timer["end"] as? [String: Any]
        return Schedule(
            trigger: trigger,
            hour: trigger == .time ? hour : 0,
            minute: minute,
            presetId: preset,
            days: int(timer["dow"], default: Schedule.allDays) & Schedule.allDays,
            enabled: int(timer["en"]) != 0,
            startMonth: clamp(int(start?["mon"], default: 1), max: 12, default: 1),
            startDay: clamp(int(start?["day"], default: 1), max: 31, default: 1),
            endMonth: clamp(int(end?["mon"], default: 12), max: 12, default: 12),
            endDay: clamp(int(end?["day"], default: 31), max: 31, default: 31)
        )
    }

    /// Callers must respect `ScheduleLimits` first; legacy slots that do not fit are dropped.
    static func encode(_ schedules: [Schedule], currentFormat: Bool) -> [[String: Any]] {
        if currentFormat {
            return schedules.map { entry($0, withDates: true, legacy: false) }
        }
        let time = Array(schedules.filter { $0.trigger == .time }.prefix(legacyTimeSlots))
        let padding = Array(repeating: emptySlot(hour: 0, withDates: true), count: legacyTimeSlots - time.count)
        let sunrise = schedules.first { $0.trigger == .sunrise }
        let sunset = schedules.first { $0.trigger == .sunset }
        return time.map { entry($0, withDates: true, legacy: true) } + padding + [
            sunrise.map { entry($0, withDates: false, legacy: true) } ?? emptySlot(hour: hourSunrise, withDates: false),
            sunset.map { entry($0, withDates: false, legacy: true) } ?? emptySlot(hour: hourSunrise, withDates: false)
        ]
    }

    private static func entry(_ schedule: Schedule, withDates: Bool, legacy: Bool) -> [String: Any] {
        let hour: Int
        switch schedule.trigger {
        case .time: hour = schedule.hour
        case .sunrise: hour = hourSunrise
        case .sunset: hour = legacy ? hourSunrise : hourSunset
        }
        var map: [String: Any] = [
            "en": schedule.enabled ? 1 : 0,
            "hour": hour,
            "min": schedule.minute,
            "macro": schedule.presetId,
            "dow": schedule.days
        ]
        if withDates {
            map["start"] = ["mon": schedule.startMonth, "day": schedule.startDay]
            map["end"] = ["mon": schedule.endMonth, "day": schedule.endDay]
        }
        return map
    }

    private static func emptySlot(hour: Int, withDates: Bool) -> [String: Any] {
        var map: [String: Any] = ["en": 0, "hour": hour, "min": 0, "macro": 0, "dow": Schedule.allDays]
        if withDates {
            map["start"] = ["mon": 1, "day": 1]
            map["end"] = ["mon": 12, "day": 31]
        }
        return map
    }

    private static func int(_ value: Any?, default fallback: Int = 0) -> Int {
        (value as? NSNumber)?.intValue ?? fallback
    }

    private static func clamp(_ value: Int, max: Int, default fallback: Int) -> Int {
        (1...max).contains(value) ? value : fallback
    }
}

/// The two command-only presets used by "Turn Device On/Off" schedules.
enum SchedulePresets {
    static let onName = "Schedule: On"
    static let offName = "Schedule: Off"
    private static let maxPresetId = 250

    /// Preset id to name, from `/presets.json`. Unnamed presets get "Preset N".
    static func names(_ presets: [String: Any]) -> [Int: String] {
        var result: [Int: String] = [:]
        for (key, value) in presets {
            guard let id = Int(key), (1...maxPresetId).contains(id),
                  let preset = value as? [String: Any], !preset.isEmpty else { continue }
            let name = (preset["n"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            result[id] = name ?? "Preset \(id)"
        }
        return result
    }

    static func find(_ presets: [Int: String], name: String) -> Int? {
        presets.first { $0.value == name }?.key
    }

    /// Highest unused preset slot, so the presets stay out of the way of the user's own.
    static func freeSlot(_ presets: [Int: String]) -> Int? {
        stride(from: maxPresetId, through: 1, by: -1).first { presets[$0] == nil }
    }

    /// Body for `POST /json/state` that saves a preset containing only `{"on": on}`.
    static func saveJSON(id: Int, name: String, on: Bool) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["psave": id, "n": name, "on": on, "o": true] as [String: Any],
            options: [.sortedKeys]
        )
    }
}

/// Body for `POST /json/cfg` that replaces the schedule list and optionally fixes time settings.
enum SchedulePayloads {
    static func configJSON(timers: [[String: Any]], ntp: [String: Any] = [:], pin: String? = nil) throws -> Data {
        var payload: [String: Any] = ["timers": ["ins": timers]]
        if !ntp.isEmpty { payload["if"] = ["ntp": ntp] }
        if let pin, !pin.isEmpty { payload["pin"] = pin }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

/// Day circles and the text under them, e.g. "Every day" or "Every Monday, Tuesday".
enum ScheduleDays {
    /// WLED day bits in the order shown: Sunday first, like the reference design.
    static let displayOrder = [6, 0, 1, 2, 3, 4, 5]

    static func isSelected(_ days: Int, _ bit: Int) -> Bool {
        days & (1 << bit) != 0
    }

    static func toggle(_ days: Int, _ bit: Int) -> Int {
        days ^ (1 << bit)
    }

    /// Full localized day name for WLED day `bit` (0 = Monday).
    static func name(_ bit: Int, calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[symbolIndex(bit)]
    }

    /// Single-letter label for the day circles.
    static func letter(_ bit: Int, calendar: Calendar = .current) -> String {
        calendar.veryShortWeekdaySymbols[symbolIndex(bit)]
    }

    /// Selected day names, Sunday first, comma separated.
    static func names(_ days: Int, calendar: Calendar = .current) -> String {
        displayOrder.filter { isSelected(days, $0) }.map { name($0, calendar: calendar) }.joined(separator: ", ")
    }

    /// "Every day", "Every Monday, Tuesday", or empty when no day is selected.
    static func summary(_ days: Int, calendar: Calendar = .current) -> String {
        switch days & Schedule.allDays {
        case Schedule.allDays: return String(localized: "Every day")
        case 0: return ""
        default: return String(localized: "Every \(names(days, calendar: calendar))")
        }
    }

    // Calendar symbols start with Sunday; WLED bits start with Monday.
    private static func symbolIndex(_ bit: Int) -> Int {
        (bit + 1) % 7
    }
}
