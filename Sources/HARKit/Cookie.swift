#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension HAR {
    /// A cookie sent with the request or set by the response (HAR 1.2 `cookies`).
    ///
    /// Fields that are not known are `nil` and omitted. Request cookies only have a name and a
    /// value; for cookies from `Set-Cookie`, `httpOnly` and `secure` are `false` when the attribute
    /// is absent.
    public struct Cookie: Codable, Hashable, Sendable {
        public var name: String
        public var value: String
        public var path: String?
        public var domain: String?
        public var expires: Date?
        public var httpOnly: Bool?
        /// Whether the cookie is only sent over TLS.
        public var secure: Bool?
        public var comment: String?

        public init(
            name: String, value: String, path: String? = nil, domain: String? = nil, expires: Date? = nil,
            httpOnly: Bool? = nil, secure: Bool? = nil, comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.path = path
            self.domain = domain
            self.expires = expires
            self.httpOnly = httpOnly
            self.secure = secure
            self.comment = comment
        }

        private enum CodingKeys: String, CodingKey {
            case name, value, path, domain, expires, httpOnly, secure, comment
        }

        /// Decodes leniently: an `expires` that is `null` or not an ISO 8601 date is dropped.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            value = try container.decode(String.self, forKey: .value)
            path = try container.decodeIfPresent(String.self, forKey: .path)
            domain = try container.decodeIfPresent(String.self, forKey: .domain)
            expires = try container.decodeIfPresent(String.self, forKey: .expires).flatMap(ISO8601.date(from:))
            httpOnly = try container.decodeIfPresent(Bool.self, forKey: .httpOnly)
            secure = try container.decodeIfPresent(Bool.self, forKey: .secure)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(path, forKey: .path)
            try container.encodeIfPresent(domain, forKey: .domain)
            if let expires { try container.encodeDate(expires, forKey: .expires) }
            try container.encodeIfPresent(httpOnly, forKey: .httpOnly)
            try container.encodeIfPresent(secure, forKey: .secure)
            try container.encodeIfPresent(comment, forKey: .comment)
        }
    }
}

extension HAR.Cookie {
    /// The cookies of a `Cookie` request header (`a=1; b=2`). A pair without `=` is a cookie with an
    /// empty name, as browsers treat it (RFC 6265bis §5.6).
    static func parseCookieHeader(_ value: String) -> [HAR.Cookie] {
        value.split(separator: ";").compactMap { pair in
            let pair = pair.trimmingOWS
            guard !pair.isEmpty else { return nil }
            guard let equals = pair.firstIndex(of: "=") else { return HAR.Cookie(name: "", value: String(pair)) }
            return HAR.Cookie(
                name: String(pair[..<equals].trimmingOWS), value: String(pair[pair.index(after: equals)...].trimmingOWS)
            )
        }
    }

    /// The cookies of a `Set-Cookie` header value, following RFC 6265 §5.2. A value holding several
    /// cookies joined with commas is split first.
    static func parseSetCookieHeader(_ value: String) -> [HAR.Cookie] {
        splitJoinedSetCookie(value).compactMap(parseSetCookieString)
    }

    private static func parseSetCookieString(_ string: Substring) -> HAR.Cookie? {
        var parts = string.split(separator: ";", omittingEmptySubsequences: false)[...]
        guard let nameValue = parts.popFirst(), let equals = nameValue.firstIndex(of: "=") else { return nil }
        let name = nameValue[..<equals].trimmingOWS
        let value = nameValue[nameValue.index(after: equals)...].trimmingOWS
        guard !name.isEmpty || !value.isEmpty else { return nil }
        var cookie = HAR.Cookie(name: String(name), value: String(value), httpOnly: false, secure: false)
        for attribute in parts {
            let attributeName = attribute.prefix { $0 != "=" }
            let attributeValue = String(attribute.dropFirst(attributeName.count + 1).trimmingOWS)
            switch attributeName.trimmingOWS.lowercased() {
            case "expires": cookie.expires = cookieDate(attributeValue) ?? cookie.expires
            case "domain" where !attributeValue.isEmpty: cookie.domain = attributeValue
            case "path" where !attributeValue.isEmpty: cookie.path = attributeValue
            case "secure": cookie.secure = true
            case "httponly": cookie.httpOnly = true
            default: break
            }
        }
        return cookie
    }

    /// Splits `a=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT, b=2` into its cookies: a comma starts a
    /// new cookie only when what follows looks like `name=`, which a date or a value never does.
    private static func splitJoinedSetCookie(_ value: String) -> [Substring] {
        var cookies: [Substring] = []
        var start = value.startIndex
        var index = value.startIndex
        while let comma = value[index...].firstIndex(of: ",") {
            let rest = value[value.index(after: comma)...].trimmingOWS
            let token = rest.prefix { !"=;, \t".contains($0) }
            if !token.isEmpty, rest.dropFirst(token.count).first == "=" {
                cookies.append(value[start..<comma])
                start = value.index(after: comma)
            }
            index = value.index(after: comma)
        }
        cookies.append(value[start...])
        return cookies
    }
}

/// Parses a cookie date with the algorithm of RFC 6265 §5.1.1, which accepts the IMF-fixdate,
/// RFC 850 and asctime formats servers send.
func cookieDate(_ string: String) -> Date? {
    func isDelimiter(_ byte: UInt8) -> Bool {
        byte == 0x09 || (0x20...0x2F).contains(byte) || (0x3B...0x40).contains(byte)
            || (0x5B...0x60).contains(byte) || (0x7B...0x7E).contains(byte)
    }
    func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
    /// `min*maxDIGIT ( non-digit *OCTET )`: the leading number, or nil.
    func leadingNumber(_ token: ArraySlice<UInt8>, _ min: Int, _ max: Int) -> (Int, ArraySlice<UInt8>)? {
        let digits = token.prefix(while: isDigit)
        guard (min...max).contains(digits.count) else { return nil }
        return (digits.reduce(0) { $0 * 10 + Int($1 - 0x30) }, token[digits.endIndex...])
    }

    let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    var time: (hour: Int, minute: Int, second: Int)?
    var day: Int?
    var month: Int?
    var year: Int?
    for token in Array(string.utf8).split(whereSeparator: isDelimiter) {
        if time == nil, let (hour, rest) = leadingNumber(token, 1, 2), rest.first == UInt8(ascii: ":"),
            let (minute, rest) = leadingNumber(rest.dropFirst(), 1, 2), rest.first == UInt8(ascii: ":"),
            let (second, _) = leadingNumber(rest.dropFirst(), 1, 2)
        {
            time = (hour, minute, second)
        } else if day == nil, let (value, _) = leadingNumber(token, 1, 2) {
            day = value
        } else if month == nil, token.count >= 3,
            let index = months.firstIndex(of: String(decoding: token.prefix(3), as: UTF8.self).lowercased())
        {
            month = index + 1
        } else if year == nil, let (value, _) = leadingNumber(token, 2, 4) {
            year = value
        }
    }
    guard let time, let day, let month, var year else { return nil }
    if (70...99).contains(year) { year += 1900 } else if (0...69).contains(year) { year += 2000 }
    let isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let daysInMonth = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    guard (1...daysInMonth).contains(day), year >= 1601, time.hour <= 23, time.minute <= 59, time.second <= 59
    else { return nil }
    let seconds =
        daysSince1970(year: year, month: month, day: day) * 86_400 + time.hour * 3_600 + time.minute * 60
        + time.second
    return Date(timeIntervalSince1970: Double(seconds))
}

/// Days from 1970-01-01 to a proleptic Gregorian date (Howard Hinnant's `days_from_civil`), so no
/// `Calendar` is needed.
private func daysSince1970(year: Int, month: Int, day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}
