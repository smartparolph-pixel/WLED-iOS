import Foundation

/// Firmware versions Sinag may offer to install on Parol lanterns. Only versions tested with the app go
/// here: a version that isn't listed is never offered, however new it is (WLED 16 changes the ESP32 platform
/// and bootloader, colours and effects, and hasn't been tested with Sinag's playlists, power limit, schedules
/// and Parol WiFi).
///
/// To approve a version after testing it on a spare lantern, add its release tag (e.g. "v16.0.1").
enum ApprovedFirmware {
    static let versions = ["v0.15.3"]

    /// The newest approved version that is newer than `current` (the lantern's own version, e.g. "0.15.3"),
    /// or nil when there is none. Pre-releases and versions that can't be compared are never offered.
    static func update(for current: String?, approved: [String] = versions) -> String? {
        guard let current, let installed = parse(current) else { return nil }
        let newer = approved
            .compactMap { tag in parse(tag).map { (tag, $0) } }
            .filter { compare($0.1, installed) > 0 }
        return newer.max { compare($0.1, $1.1) < 0 }?.0
    }

    static func isApproved(_ tag: String, approved: [String] = versions) -> Bool {
        guard let version = parse(tag) else { return false }
        return approved.contains { parse($0) == version }
    }

    /// "v0.15.3" or "0.15.3" → [0, 15, 3]; nil for anything else, including "-b1" pre-releases.
    private static func parse(_ version: String) -> [Int]? {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        var numbers: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.last == 0 { numbers.removeLast() }
        return text.isEmpty ? nil : numbers
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for index in 0..<max(lhs.count, rhs.count) {
            let difference = (index < lhs.count ? lhs[index] : 0) - (index < rhs.count ? rhs[index] : 0)
            if difference != 0 { return difference }
        }
        return 0
    }
}
