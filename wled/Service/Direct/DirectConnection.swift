import Foundation

/// Rules for the "Direct connection": the phone is on a lantern's own WiFi (no home WiFi where the lantern
/// is), and the app talks to it at `apAddress` without changing what is saved for it.
enum DirectConnection {
    /// Where the lantern answers on its own WiFi.
    static let apAddress = "4.3.2.1"
    /// The lantern gives phones on its WiFi an address in 4.3.2.x.
    static let apSubnetPrefix = "4.3.2."

    /// Whether one of the phone's IPv4 addresses is on a lantern's own WiFi.
    static func isOnLanternNetwork(addresses: [String]) -> Bool {
        addresses.contains { $0.hasPrefix(apSubnetPrefix) && $0 != apAddress }
    }

    /// The address to save when a device is seen at `newAddress`: the lantern's own address only works
    /// on its WiFi, so it never replaces the home one.
    static func addressToSave(saved: String?, newAddress: String) -> String {
        if newAddress == apAddress, let saved, !saved.isEmpty { return saved }
        return newAddress
    }

    /// Sets the lantern's clock to the phone's (UTC seconds). Without internet the lantern has no time after
    /// a power-up and its schedules don't run; WLED applies this through its normal state API.
    static func timeJSON(_ date: Date = Date()) -> String {
        "{\"time\":\(Int(date.timeIntervalSince1970))}"
    }

    static func sameMac(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let normalize = { (mac: String) in mac.lowercased().filter { $0.isLetter || $0.isNumber } }
        return !lhs.isEmpty && normalize(lhs) == normalize(rhs)
    }
}
