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
        if let string = fastString(secondsSince1970: seconds, milliseconds: fraction) { return string }
        let whole = Date.ISO8601FormatStyle().format(Date(timeIntervalSince1970: seconds))
        let digits = String(fraction)
        return "\(whole.dropLast()).\(String(repeating: "0", count: 3 - digits.count))\(digits)Z"
    }

    /// The years the fast paths handle: four digits, and well after the Julian to Gregorian switch, so
    /// the proleptic Gregorian arithmetic here agrees with `Date.ISO8601FormatStyle`. Other dates go
    /// through the format style.
    private static let fastYears = 1900...9999

    /// `2009-04-16T12:07:23.596Z` written byte by byte: creating and running an `ISO8601FormatStyle`
    /// per date was most of the cost of the dates in a log.
    private static func fastString(secondsSince1970 seconds: Double, milliseconds: Int) -> String? {
        guard seconds >= -2_208_988_800, seconds < 253_402_300_800 else { return nil }  // 1900 to 9999
        let whole = Int(seconds)
        let days = whole >= 0 ? whole / 86_400 : (whole - 86_399) / 86_400
        let secondOfDay = whole - days * 86_400
        let (year, month, day) = civilDate(daysSince1970: days)
        guard fastYears.contains(year) else { return nil }
        return String(unsafeUninitializedCapacity: 24) { buffer in
            func put(_ value: Int, digits: Int, at offset: Int) {
                var value = value
                for index in stride(from: offset + digits - 1, through: offset, by: -1) {
                    buffer[index] = UInt8(ascii: "0") + UInt8(value % 10)
                    value /= 10
                }
            }
            put(year, digits: 4, at: 0)
            buffer[4] = UInt8(ascii: "-")
            put(month, digits: 2, at: 5)
            buffer[7] = UInt8(ascii: "-")
            put(day, digits: 2, at: 8)
            buffer[10] = UInt8(ascii: "T")
            put(secondOfDay / 3_600, digits: 2, at: 11)
            buffer[13] = UInt8(ascii: ":")
            put(secondOfDay / 60 % 60, digits: 2, at: 14)
            buffer[16] = UInt8(ascii: ":")
            put(secondOfDay % 60, digits: 2, at: 17)
            buffer[19] = UInt8(ascii: ".")
            put(milliseconds, digits: 3, at: 20)
            buffer[23] = UInt8(ascii: "Z")
            return 24
        }
    }

    /// Parses `2009-04-16T12:07:23Z`, the shape HAR writers use once fractional seconds are removed,
    /// without an `ISO8601FormatStyle`; `nil` for anything else, which the format style then reads.
    private static func fastDate(_ text: Substring) -> Date? {
        var utf8 = text.utf8[...]
        guard utf8.count == 20 else { return nil }
        func number(_ digits: Int, then separator: UInt8?) -> Int? {
            var value = 0
            for _ in 0..<digits {
                guard let byte = utf8.popFirst(), (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else {
                    return nil
                }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            if let separator {
                guard utf8.popFirst() == separator else { return nil }
            }
            return value
        }
        guard let year = number(4, then: UInt8(ascii: "-")), fastYears.contains(year),
            let month = number(2, then: UInt8(ascii: "-")), (1...12).contains(month),
            let day = number(2, then: UInt8(ascii: "T")), (1...daysIn(month: month, year: year)).contains(day),
            let hour = number(2, then: UInt8(ascii: ":")), hour <= 23,
            let minute = number(2, then: UInt8(ascii: ":")), minute <= 59,
            let second = number(2, then: UInt8(ascii: "Z")), second <= 59
        else { return nil }
        let seconds = daysSince1970(year: year, month: month, day: day) * 86_400 + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: Double(seconds))
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
        guard let date = fastDate(text) ?? (try? Date(String(text), strategy: Date.ISO8601FormatStyle())) else {
            return nil
        }
        return date.addingTimeInterval(fraction)
    }
}

/// Days in a month of the proleptic Gregorian calendar.
func daysIn(month: Int, year: Int) -> Int {
    switch month {
    case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}

/// Days from 1970-01-01 to a proleptic Gregorian date (Howard Hinnant's `days_from_civil`), so no
/// `Calendar` is needed.
func daysSince1970(year: Int, month: Int, day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}

/// The proleptic Gregorian date of a day counted from 1970-01-01 (Howard Hinnant's
/// `civil_from_days`), the inverse of `daysSince1970(year:month:day:)`.
func civilDate(daysSince1970 days: Int) -> (year: Int, month: Int, day: Int) {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
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
