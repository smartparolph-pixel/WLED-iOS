import Foundation

/// What the lantern does when power comes back (plugged in, after a power cut): WLED's "Apply preset at boot"
/// (`def.ps` in cfg.json), "Turn LEDs on after power up" (`def.on`) and its brightness (`def.bri`).
/// Turning the lights off and on from the app is different: a playlist pauses while off and carries on.
enum PowerOn {
    static let fullBrightness = 255

    /// The preset or playlist the lantern starts at power-up; 0 means none (a static light).
    static func bootPreset(_ cfg: [String: Any]) -> Int {
        ((cfg["def"] as? [String: Any])?["ps"] as? NSNumber)?.intValue ?? 0
    }

    /// The power-on playlist to set, or nil to leave the lantern as it is: `defaultId` (🎆 Sky Full of Sparks)
    /// when none is set yet, or when the one set no longer exists (e.g. the user deleted their playlist).
    static func presetToSet(current: Int, existingIds: Set<Int>, defaultId: Int?) -> Int? {
        guard let defaultId else { return nil }
        return current == 0 || !existingIds.contains(current) ? defaultId : nil
    }

    /// Body for `POST /json/cfg`: start `presetId` at power-up with the lights on, at `brightness` if given
    /// (left unchanged otherwise). Only `def` is sent, so nothing else in the config changes.
    static func configJSON(presetId: Int, brightness: Int? = nil) throws -> Data {
        var def: [String: Any] = ["ps": presetId, "on": true]
        if let brightness { def["bri"] = brightness }
        return try JSONSerialization.data(withJSONObject: ["def": def], options: [.sortedKeys])
    }
}
