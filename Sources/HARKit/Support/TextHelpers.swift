#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension [HAR.Header] {
    /// The value of the first header with this name, compared case-insensitively (RFC 9110 §5.1).
    func value(named name: String) -> String? {
        let name = name.lowercased()
        return first { $0.name.lowercased() == name }?.value
    }

    func values(named name: String) -> [String] {
        let name = name.lowercased()
        return filter { $0.name.lowercased() == name }.map(\.value)
    }
}

extension StringProtocol where SubSequence == Substring {
    /// Trims spaces and horizontal tabs (HTTP optional whitespace, RFC 9110 §5.6.3).
    var trimmingOWS: Substring {
        let isOWS: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        guard let start = firstIndex(where: { !isOWS($0) }), let end = lastIndex(where: { !isOWS($0) }) else {
            return ""
        }
        return self[start...end]
    }
}

/// Percent-decoding (RFC 3986 §2.1), written here because FoundationEssentials has no
/// `removingPercentEncoding`.
///
/// A malformed escape (`%zz`, a trailing `%`) or a result that is not UTF-8 leaves the whole
/// string as written, so nothing is lost or replaced with U+FFFD.
func percentDecoded<S: StringProtocol>(_ string: S, plusAsSpace: Bool = false) -> String {
    var bytes: [UInt8] = []
    var input = Array(string.utf8)[...]
    while let byte = input.popFirst() {
        if byte == UInt8(ascii: "%") {
            guard input.count >= 2, let high = hexValue(input[input.startIndex]),
                let low = hexValue(input[input.startIndex + 1])
            else { return String(string) }
            bytes.append(high << 4 | low)
            input = input.dropFirst(2)
        } else if plusAsSpace && byte == UInt8(ascii: "+") {
            bytes.append(UInt8(ascii: " "))
        } else {
            bytes.append(byte)
        }
    }
    return utf8String(bytes) ?? String(string)
}

/// The bytes as a string if they are valid UTF-8, `nil` otherwise.
///
/// `String(validating:as:)` would do, but it needs macOS 15 / iOS 18: decoding replaces invalid
/// sequences with U+FFFD, so the bytes are valid exactly when they survive the round trip.
func utf8String<Bytes: Collection<UInt8>>(_ bytes: Bytes) -> String? {
    let string = String(decoding: bytes, as: UTF8.self)
    return string.utf8.elementsEqual(bytes) ? string : nil
}

private func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
    default: nil
    }
}

/// Splits `a=1&b&c=` into name/value pairs, skipping empty segments; a pair without `=` has an
/// empty value.
func nameValuePairs<S: StringProtocol>(_ string: S, plusAsSpace: Bool) -> [(name: String, value: String)] {
    string.split(separator: "&").map { pair in
        let name = pair.prefix { $0 != "=" }
        let value = pair.dropFirst(name.count + 1)
        return (percentDecoded(name, plusAsSpace: plusAsSpace), percentDecoded(value, plusAsSpace: plusAsSpace))
    }
}

/// A parsed `Content-Type` value: what decides whether a body can be written as text.
struct MediaType {
    /// `type/subtype`, lowercased.
    let essence: String
    let charset: String?

    init(_ value: String) {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        essence = String(parts.first?.trimmingOWS ?? "").lowercased()
        charset =
            parts.dropFirst().lazy.compactMap { parameter -> String? in
                let pair = parameter.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, pair[0].trimmingOWS.lowercased() == "charset" else { return nil }
                var value = pair[1].trimmingOWS
                if value.count >= 2, value.first == "\"", value.last == "\"" { value = value.dropFirst().dropLast() }
                return value.lowercased()
            }.first
    }

    static let formURLEncoded = "application/x-www-form-urlencoded"

    private static let textualApplicationTypes: Set<String> = [
        "application/json", "application/xml", "application/javascript", "application/ecmascript",
        "application/x-javascript", "application/graphql", "application/x-ndjson", "application/yaml",
        "application/x-yaml", "application/sql", formURLEncoded,
    ]

    /// Media types whose bodies are text, so HAR 1.2 `text` can hold them without an `encoding`.
    var isTextual: Bool {
        essence.hasPrefix("text/") || essence.hasSuffix("+json") || essence.hasSuffix("+xml")
            || Self.textualApplicationTypes.contains(essence)
    }

    /// The bytes are UTF-8 as far as the header says: no charset, or a UTF-8 compatible one.
    var allowsUTF8: Bool {
        charset.map { ["utf-8", "utf8", "us-ascii", "ascii"].contains($0) } ?? true
    }

    /// The body as text when the media type is textual and the bytes are valid UTF-8.
    func text(of body: Data) -> String? {
        guard isTextual, allowsUTF8 else { return nil }
        return utf8String(body)
    }
}
