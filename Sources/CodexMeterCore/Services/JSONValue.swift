import Foundation

/// Tiny JSON walker that tolerates extra fields and mixed casings.
enum JSONValue {
    static func object(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    static func array(_ any: Any?) -> [Any]? {
        any as? [Any]
    }

    static func value(_ object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key] {
                return value
            }
        }
        let lowered = Dictionary(uniqueKeysWithValues: object.map { ($0.key.lowercased(), $0.value) })
        for key in keys {
            if let value = lowered[key.lowercased()] {
                return value
            }
            let compact = key.replacingOccurrences(of: "_", with: "").lowercased()
            if let match = lowered.first(where: { $0.key.replacingOccurrences(of: "_", with: "") == compact }) {
                return match.value
            }
        }
        return nil
    }

    static func string(_ object: [String: Any], keys: [String]) -> String? {
        guard let raw = value(object, keys: keys), !(raw is NSNull) else { return nil }
        if let string = raw as? String { return string }
        return String(describing: raw)
    }

    static func bool(_ object: [String: Any], keys: [String]) -> Bool? {
        guard let raw = value(object, keys: keys), !(raw is NSNull) else { return nil }
        if let bool = raw as? Bool { return bool }
        if let number = raw as? NSNumber { return number.boolValue }
        if let string = raw as? String {
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    static func double(_ object: [String: Any], keys: [String]) -> Double? {
        guard let raw = value(object, keys: keys), !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String, let value = Double(string) { return value }
        return nil
    }

    static func int(_ object: [String: Any], keys: [String]) -> Int? {
        guard let raw = value(object, keys: keys), !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, let value = Int(string) { return value }
        if let double = raw as? Double { return Int(double) }
        return nil
    }

    static func date(fromUnix raw: Any?) -> Date? {
        guard let raw, !(raw is NSNull) else { return nil }
        let value: Double
        if let number = raw as? NSNumber {
            value = number.doubleValue
        } else if let int = raw as? Int {
            value = Double(int)
        } else if let double = raw as? Double {
            value = double
        } else if let string = raw as? String, let parsed = Double(string) {
            value = parsed
        } else {
            return nil
        }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        if value > 1_000_000_000 {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }
}
