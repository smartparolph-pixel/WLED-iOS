import Foundation
import Security

/// A lantern's own WiFi, the one it opens when the home WiFi isn't there.
struct LanternWifiCredentials: Codable, Equatable, Hashable {
    let ssid: String
    let password: String
}

enum LanternWifiStatus: Equatable {
    /// The lantern couldn't be read.
    case unknown
    /// Still WLED's shared `WLED-AP` / `wled1234`.
    case shared
    /// Its own name and the password this phone has saved.
    case secured
    /// Changed, but this phone doesn't have the password (another phone set it, or the app was reinstalled).
    case notOnThisPhone
}

/// Rules for giving each lantern its own WiFi name and password instead of WLED's shared `WLED-AP` /
/// `wled1234`, set with WLED's normal config API (`ap.ssid`, `ap.psk`); no firmware change.
///
/// - The name shows the end of the MAC so lanterns are easy to tell apart; it is only a label.
/// - The password is random and never derived from the MAC (the lantern's WiFi broadcasts its MAC).
/// - WLED never returns the password (`/json/cfg` only gives its length), so the app keeps it.
enum LanternWifi {
    static let ssidPrefix = "Parol-"
    static let passwordLength = 8
    static let defaultSsid = "WLED-AP"
    static let defaultPassword = "wled1234"
    /// Easy to read and type: no 0/o, 1/l/i.
    static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
    private static let macCharacters = 4

    /// e.g. "Parol-E4F5" for MAC a0b1c2d3e4f5.
    static func ssid(forMac mac: String) -> String {
        let hex = mac.filter { $0.isLetter || $0.isNumber }.uppercased()
        return ssidPrefix + String(hex.suffix(macCharacters))
    }

    static func newPassword() -> String {
        var generator = SystemRandomNumberGenerator()
        return newPassword(using: &generator)
    }

    static func newPassword<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<passwordLength).map { _ in alphabet.randomElement(using: &generator) ?? "a" })
    }

    static func newCredentials(mac: String) -> LanternWifiCredentials {
        LanternWifiCredentials(ssid: ssid(forMac: mac), password: newPassword())
    }

    /// `ap` for `POST /json/cfg`. WLED leaves the rest of its WiFi settings as they are.
    static func apConfig(_ credentials: LanternWifiCredentials) -> [String: Any] {
        ["ssid": credentials.ssid, "psk": credentials.password]
    }

    /// Body for `POST /json/cfg` that sets the lantern's own WiFi; `pin` if it has a settings PIN.
    static func configJSON(_ credentials: LanternWifiCredentials, pin: String? = nil) throws -> Data {
        var payload: [String: Any] = ["ap": apConfig(credentials)]
        if let pin, !pin.isEmpty { payload["pin"] = pin }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// The lantern's own WiFi name and password length from its `/json/cfg`.
    static func fromConfig(_ cfg: [String: Any]) -> (ssid: String?, passwordLength: Int?) {
        let ap = cfg["ap"] as? [String: Any]
        return (ap?["ssid"] as? String, (ap?["pskl"] as? NSNumber)?.intValue)
    }

    static func status(ssid: String?, passwordLength: Int?, saved: LanternWifiCredentials?) -> LanternWifiStatus {
        guard let ssid else { return .unknown }
        // Our passwords are as long as the default one, so the name tells them apart.
        if ssid == defaultSsid { return .shared }
        if let saved, saved.ssid == ssid, passwordLength == saved.password.count { return .secured }
        return .notOnThisPhone
    }

    /// WPA2 needs 8 to 63 characters, or the lantern's WiFi doesn't start.
    static func isValidPassword(_ password: String) -> Bool {
        (passwordLength...63).contains(password.count)
    }
}

/// Each lantern's own WiFi, by MAC, in the Keychain: this device only, not synced or restored elsewhere.
@MainActor
final class LanternWifiStore: ObservableObject {
    static let shared = LanternWifiStore()

    private static let service = "lantern-wifi"

    /// Saved credentials by MAC (lowercase, no separators).
    @Published private(set) var all: [String: LanternWifiCredentials] = [:]

    private init() {
        all = Self.readAll()
    }

    func credentials(forMac mac: String) -> LanternWifiCredentials? {
        all[Self.key(mac)]
    }

    func save(_ credentials: LanternWifiCredentials, forMac mac: String) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let account = Self.key(mac)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) == errSecSuccess {
            all[account] = credentials
        }
    }

    func remove(mac: String) {
        let account = Self.key(mac)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        all[account] = nil
    }

    private static func key(_ mac: String) -> String {
        mac.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func readAll() -> [String: LanternWifiCredentials] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [:] }
        var saved: [String: LanternWifiCredentials] = [:]
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let credentials = try? JSONDecoder().decode(LanternWifiCredentials.self, from: data) else { continue }
            saved[account] = credentials
        }
        return saved
    }
}
