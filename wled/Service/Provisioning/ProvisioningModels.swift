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
    static func wifiConfigJSON(ssid: String, password: String, timezone: WledTimezoneSetting? = nil) throws -> Data {
        var payload: [String: Any] = [
            "nw": ["ins": [["ssid": ssid, "psk": password]]]
        ]
        if let timezone {
            payload["if"] = ["ntp": TimezonePayloads.ntpConfig(timezone)]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
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
