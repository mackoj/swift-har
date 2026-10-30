#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// ISO 8601 dates as HAR 1.2 writes them (`2009-04-16T12:07:23.596Z`): UTC, millisecond precision.
///
/// `Date.ISO8601FormatStyle` truncates fractional seconds, which turns `.596` into `.595` for dates
/// that are not exactly representable, so whole seconds are formatted by the style and the
/// rounded milliseconds are appended here.
enum ISO8601 {
    static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let seconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - seconds * 1000)
        let whole = Date.ISO8601FormatStyle().format(Date(timeIntervalSince1970: seconds))
        let digits = String(fraction)
        return "\(whole.dropLast()).\(String(repeating: "0", count: 3 - digits.count))\(digits)Z"
    }

    /// Parses an ISO 8601 date with any number of fractional digits and a `Z` or `±hh:mm` offset.
    static func date(from string: String) -> Date? {
        var text = Substring(string)
        var fraction = 0.0
        if let dot = text.firstIndex(of: "."), text[..<dot].contains("T") {
            let digits = text[text.index(after: dot)...].prefix(while: \.isASCIIDigit)
            guard !digits.isEmpty, let value = Double("0." + digits) else { return nil }
            fraction = value
            text = text[..<dot] + text[digits.endIndex...]
        }
        guard let date = try? Date(String(text), strategy: Date.ISO8601FormatStyle()) else { return nil }
        return date.addingTimeInterval(fraction)
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

extension KeyedEncodingContainer {
    mutating func encodeDate(_ date: Date, forKey key: Key) throws {
        try encode(ISO8601.string(from: date), forKey: key)
    }
}

extension KeyedDecodingContainer {
    func decodeDate(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        guard let date = ISO8601.date(from: string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "Not an ISO 8601 date: \(string)")
        }
        return date
    }
}
