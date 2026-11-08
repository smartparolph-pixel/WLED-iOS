import Foundation

/// Rebuilds a damaged presets.json from the entries that are still intact.
///
/// WLED writes presets.json in place, one entry at a time, and two writes at once (e.g. a preset saved
/// from the JSON API while a playlist is still being written) can leave stray or cut-off text in it. The
/// firmware still finds most presets by searching for `"id":`, but the file is no longer valid JSON, so
/// WLED's web page ("issue loading your presets") and the app cannot read it.
///
/// This scans the file for `"id":{...}` entries, keeps every one that parses, and drops the rest. When an
/// id appears twice, the first one is kept, as that is the one the firmware loads.
enum PresetsFileRepair {
    struct Result {
        /// The entries kept, by id, in file order.
        let ids: [String]
        let presets: [String: Any]
        /// Damaged or repeated parts left out.
        let dropped: Int

        /// Presets and playlists kept, not counting the empty entry "0".
        var kept: Int { ids.filter { $0 != "0" }.count }

        /// The repaired file, always valid JSON with whole numbers.
        func json() throws -> Data {
            try JSONSerialization.data(withJSONObject: PresetsFileRepair.wholeNumbers(presets), options: [.sortedKeys])
        }
    }

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let open = UInt8(ascii: "{")
    private static let close = UInt8(ascii: "}")
    private static let colon = UInt8(ascii: ":")

    /// A JSON number value written with a zero fraction, e.g. `:80.0` or `[1.0,`. WLED never writes these,
    /// and ignores a decimal effect, speed or palette; an earlier Android repair wrote them.
    private static let decimalWhole = try? NSRegularExpression(pattern: #"[:\[,]\s*-?\d+\.0+\s*(?=[,\]}])"#)

    /// Why the file cannot be used as is, or nil if it parses and the firmware can read its numbers.
    static func problem(_ data: Data) -> String? {
        do {
            guard try JSONSerialization.jsonObject(with: data) is [String: Any] else {
                return "Not a JSON object"
            }
            let text = String(decoding: data, as: UTF8.self)
            let range = NSRange(text.startIndex..., in: text)
            if decimalWhole?.firstMatch(in: text, range: range) != nil {
                return "Numbers saved as decimals (e.g. 80.0)"
            }
            return nil
        } catch {
            return (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
        }
    }

    static func repair(_ data: Data) -> Result {
        let bytes = [UInt8](data)
        var ids = ["0"]
        var presets: [String: Any] = ["0": [String: Any]()]
        var dropped = 0
        var position = 0
        while let found = nextEntry(bytes, from: position) {
            let id = found.0
            let valueStart = found.1
            let valueEnd = objectEnd(bytes, from: valueStart)
            let value = valueEnd.flatMap { end in
                (try? JSONSerialization.jsonObject(with: Data(bytes[valueStart...end]))) as? [String: Any]
            }
            if let value, let number = Int(id), number <= PresetPackPlanner.maxPresetId,
               id == "0" || presets[id] == nil {
                if presets[id] == nil { ids.append(id) }
                presets[id] = value
            } else {
                dropped += 1
            }
            if value != nil, let valueEnd {
                position = valueEnd + 1
            } else {
                position = valueStart + 1
            }
        }
        return Result(ids: ids, presets: presets, dropped: dropped)
    }

    /// The next `"digits"` key followed by `:` and `{`: the id and the index of the `{`.
    private static func nextEntry(_ bytes: [UInt8], from start: Int) -> (String, Int)? {
        var index = start
        while index < bytes.count {
            if bytes[index] == quote, let found = entry(bytes, at: index) { return found }
            index += 1
        }
        return nil
    }

    private static func entry(_ bytes: [UInt8], at quoteIndex: Int) -> (String, Int)? {
        var index = quoteIndex + 1
        var digits = ""
        while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9"), digits.count < 3 {
            digits.append(Character(UnicodeScalar(bytes[index])))
            index += 1
        }
        guard !digits.isEmpty, index < bytes.count, bytes[index] == quote else { return nil }
        index = skipSpaces(bytes, from: index + 1)
        guard index < bytes.count, bytes[index] == colon else { return nil }
        index = skipSpaces(bytes, from: index + 1)
        guard index < bytes.count, bytes[index] == open else { return nil }
        return (digits, index)
    }

    private static func skipSpaces(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        return index
    }

    /// Index of the `}` closing the object that opens at `start`, or nil if the data ends first.
    private static func objectEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<bytes.count {
            let byte = bytes[index]
            if escaped {
                escaped = false
            } else if inString && byte == backslash {
                escaped = true
            } else if byte == quote {
                inString.toggle()
            } else if !inString && byte == open {
                depth += 1
            } else if !inString && byte == close {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    /// Copies parsed JSON, turning whole-valued decimals back into integers.
    static func wholeNumbers(_ value: Any) -> Any {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            if double.rounded() == double, abs(double) < 1e15 { return Int(double) }
            return number
        }
        if let object = value as? [String: Any] { return object.mapValues { wholeNumbers($0) } }
        if let list = value as? [Any] { return list.map { wholeNumbers($0) } }
        return value
    }
}
