import Foundation

/// Defaults for first-time setup of a WLED device over its own access point.
/// Factory-flashed products can override the prefix/password through `ProvisioningRequest`.
enum ProvisioningDefaults {
    /// Stock WLED AP SSID.
    static let apSsidPrefix = "WLED-AP"
    /// Stock WLED AP WPA2 passphrase.
    static let apPassword = "wled1234"
    /// Stock WLED AP address (also the captive portal address).
    static let apHost = "4.3.2.1"

    static let httpTimeout: TimeInterval = 10
    /// How many times to retry `GET /json/info` while the phone finishes associating with the AP.
    static let infoRetries = 6
    static let infoRetryDelay: Duration = .seconds(1)
    /// Time given to WLED to persist cfg.json before we ask it to reboot.
    static let configWriteGrace: Duration = .seconds(2)
    /// Time given to the device to boot and the phone to rejoin its normal WiFi.
    static let rebootSettle: Duration = .seconds(5)
    static let deviceReappearTimeout: Duration = .seconds(90)
    /// Brightness limiter for the lanterns' 5 V 3 A (15 W) power supply, set during setup: 2000 mA leaves
    /// headroom below the supply's rating. WLED dims all LEDs to stay under it.
    static let powerLimitMilliamps = 2000
}

struct ProvisioningRequest {
    /// SSID of the user's home router.
    var homeSsid: String
    /// Password of the user's home router. Empty for an open network.
    var homePassword: String
    var apSsidPrefix: String = ProvisioningDefaults.apSsidPrefix
    /// Nil means the setup AP is open (no passphrase).
    var apPassword: String? = ProvisioningDefaults.apPassword
    /// Sent along with the credentials so the device shows local time right away. Nil leaves it unchanged.
    var timezone: WledTimezoneSetting?
}

enum ProvisioningProgress: Equatable {
    case joiningSetupNetwork
    case sendingCredentials
    case rebootingDevice
    case waitingForDevice
}

enum ProvisioningError: LocalizedError, Equatable {
    case setupNetworkDeclined
    case setupNetworkUnavailable
    case notAWledDevice
    case credentialsRejected(Int)
    case deviceDidNotReappear
    case unknown

    var errorDescription: String? {
        switch self {
        case .setupNetworkDeclined:
            return String(localized: "You declined to connect to the device's setup network.")
        case .setupNetworkUnavailable:
            return String(localized: "Could not connect to the device's setup network. Make sure it is powered on and close to your phone.")
        case .notAWledDevice:
            return String(localized: "The setup network did not respond like a WLED device.")
        case .credentialsRejected:
            return String(localized: "The device did not accept the WiFi details.")
        case .deviceDidNotReappear:
            return String(localized: "The device did not show up on your WiFi. Check the name and password, then try again.")
        case .unknown:
            return String(localized: "Something went wrong. Please try again.")
        }
    }
}

/// Pure helpers, free of networking so they are trivial to unit test.
enum ProvisioningPayloads {

    /// Body for `POST /json/cfg`.
    ///
    /// Only `nw.ins[0]` is sent. WLED's `deserializeConfig` leaves every field that is absent from
    /// the JSON untouched, so unlike posting the whole /settings/wifi HTML form this cannot reset
    /// AP behaviour, static IP, mDNS name, etc. `timezone` adds `if.ntp`, which is equally partial.
    static func wifiConfigJSON(
        ssid: String,
        password: String,
        timezone: WledTimezoneSetting? = nil,
        led: [String: Any]? = nil
    ) throws -> Data {
        var payload: [String: Any] = [
            "nw": ["ins": [["ssid": ssid, "psk": password]]]
        ]
        if let timezone {
            payload["if"] = ["ntp": TimezonePayloads.ntpConfig(timezone)]
        }
        if let led {
            payload["hw"] = ["led": led]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// `hw.led` for `POST /json/cfg` that sets the brightness limiter to `limit` mA, built from the
    /// device's current `/json/cfg`.
    ///
    /// WLED 0.15 enforces the limit per LED output (`hw.led.ins[].maxpwr`); `hw.led.maxpwr` is only the
    /// total shown on the settings page. Its settings page splits the total across outputs by LED count,
    /// and so does this. Sending `ins` makes the firmware rebuild every output from the list, so each one
    /// is sent back whole, with only `maxpwr` changed.
    ///
    /// - Returns: nil if the config has no LED outputs, so nothing is changed.
    static func powerLimitConfig(_ cfg: [String: Any], limit: Int = ProvisioningDefaults.powerLimitMilliamps) -> [String: Any]? {
        let led = (cfg["hw"] as? [String: Any])?["led"] as? [String: Any]
        let outputs = (led?["ins"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let lengths = outputs.map { ($0["len"] as? NSNumber)?.intValue ?? 0 }
        let total = lengths.reduce(0, +)
        guard !outputs.isEmpty, total > 0 else { return nil }
        var left = limit
        var ins: [[String: Any]] = []
        for (index, output) in outputs.enumerated() {
            let share = index == outputs.count - 1 ? left : limit * lengths[index] / total
            left -= share
            var copy = output
            copy["maxpwr"] = share
            ins.append(copy)
        }
        return ["maxpwr": limit, "ins": ins]
    }

    /// Body for `POST /json/state` that makes WLED reboot.
    static let rebootJSON = Data(#"{"rb":true}"#.utf8)

    /// mDNS and `/json/info` both give "aabbccddeeff"; be lenient about case and separators.
    static func normalizeMac(_ mac: String?) -> String {
        (mac ?? "").replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    static func sameMac(_ a: String?, _ b: String?) -> Bool {
        let na = normalizeMac(a)
        return !na.isEmpty && na == normalizeMac(b)
    }
}
