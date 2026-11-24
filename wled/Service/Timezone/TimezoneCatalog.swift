import Foundation

/// One row of the timezone picker.
struct TimezoneOption: Identifiable, Equatable {
    let id: String
    let city: String
    let region: String
    let displayName: String
    let offsetSeconds: Int

    var offsetLabel: String { TimezonePayloads.formatOffset(offsetSeconds) }
}

/// Builds the picker list from the phone's own copy of the IANA tz database (eggert/tz), so the app
/// never ships or updates timezone data itself.
enum TimezoneCatalog {
    private static let regions: Set<String> = [
        "Africa", "America", "Antarctica", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific"
    ]

    /// Non-geographic identifiers (GMT, Etc/..., US/...) are dropped.
    static func options(
        identifiers: [String] = TimeZone.knownTimeZoneIdentifiers,
        now: Date = Date(),
        locale: Locale = .current
    ) -> [TimezoneOption] {
        identifiers
            .compactMap { id -> TimezoneOption? in
                let parts = id.split(separator: "/")
                guard parts.count > 1,
                      let region = parts.first.map(String.init), regions.contains(region),
                      let city = parts.last.map({ $0.replacingOccurrences(of: "_", with: " ") }),
                      let zone = TimeZone(identifier: id) else { return nil }
                let style: NSTimeZone.NameStyle = zone.isDaylightSavingTime(for: now) ? .daylightSaving : .standard
                return TimezoneOption(
                    id: id,
                    city: city,
                    region: region,
                    displayName: zone.localizedName(for: style, locale: locale) ?? id,
                    offsetSeconds: zone.secondsFromGMT(for: now)
                )
            }
            .sorted { ($0.offsetSeconds, $0.city) < ($1.offsetSeconds, $1.city) }
    }

    /// Case-insensitive match on city, zone identifier, zone name or "UTC+hh:mm".
    static func filter(_ options: [TimezoneOption], query: String) -> [TimezoneOption] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return options }
        return options.filter { option in
            [option.city, option.id, option.displayName, option.offsetLabel]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    /// What to send to the device for zone `identifier`, comparing rules over the year from `now`.
    static func setting(for identifier: String, now: Date = Date()) -> WledTimezoneSetting {
        let zone = TimeZone(identifier: identifier) ?? .gmt
        return WledTimezones.match(fromEpochSeconds: Int64(now.timeIntervalSince1970)) { seconds in
            zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
    }
}

/// JSON bodies for `POST /json/cfg`.
enum TimezonePayloads {

    /// `if.ntp` object. Turns NTP on, since WLED ships with it off and the zone is useless without it.
    static func ntpConfig(_ setting: WledTimezoneSetting) -> [String: Any] {
        ["en": true, "tz": setting.index, "offset": setting.offsetSeconds]
    }

    /// - Parameter pin: Settings PIN, if the device has one. WLED answers 401 to config changes without it.
    static func configJSON(_ setting: WledTimezoneSetting, pin: String? = nil) throws -> Data {
        var payload: [String: Any] = ["if": ["ntp": ntpConfig(setting)]]
        if let pin, !pin.isEmpty { payload["pin"] = pin }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// "UTC+05:45", "UTC−03:00", "UTC+00:00".
    static func formatOffset(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return String(format: "UTC%@%02ld:%02ld", seconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
    }
}
