import HARKit
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A decoded JSON value, used to assert on the exact shape the encoder writes
/// (which keys are present, `null` versus absent) without going through the HAR models.
enum JSON: Decodable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    subscript(key: String) -> JSON? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    subscript(index: Int) -> JSON? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }

    var keys: Set<String> {
        guard case .object(let object) = self else { return [] }
        return Set(object.keys)
    }
}

/// Encodes `value` with a plain `JSONEncoder` (as a caller with their own encoder would) and
/// decodes the result as ``JSON``.
func encodedJSON<T: Encodable>(_ value: T) throws -> JSON {
    try JSONDecoder().decode(JSON.self, from: JSONEncoder().encode(value))
}

/// Encodes then decodes `value`, for round-trip assertions.
func roundTripped<T: Codable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

/// 2009-04-16T12:07:23.596Z, the `startedDateTime` of the specification's `entries` example.
let exampleDate = Date(timeIntervalSince1970: 1_239_883_643.596)

func header(_ name: String, _ value: String) -> HAR.Header {
    HAR.Header(name: name, value: value)
}

func makeTimings() throws -> HAR.Timings {
    try HAR.Timings(send: 20, wait: 38, receive: 12)
}

func makeEntry(
    request: HAR.Request? = nil, response: HAR.Response? = nil, startedDateTime: Date = exampleDate
) throws -> HAR.Entry {
    HAR.Entry(
        startedDateTime: startedDateTime,
        request: request
            ?? HAR.Request(method: "GET", url: URL(string: "https://example.com/")!, httpVersion: "HTTP/1.1"),
        response: response
            ?? HAR.Response(status: 200, statusText: "OK", httpVersion: "HTTP/1.1", headers: [], body: Data()),
        timings: try makeTimings()
    )
}
