import HARKit
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// HAR 1.2 `timings`.
@Suite("Timings")
struct TimingsTests {
    @Test func requiredPhasesOnlyAreWrittenWhenNothingElseWasMeasured() throws {
        // Given
        let timings = try HAR.Timings(send: 0, wait: 0, receive: 0)

        // Then: blocked, dns, connect and ssl may be omitted by tools that cannot provide them.
        #expect(try encodedJSON(timings) == .object(["send": .number(0), "wait": .number(0), "receive": .number(0)]))
    }

    @Test func allPhasesAreWrittenWhenGiven() throws {
        // Given: the specification's example, with -1 meaning "does not apply".
        let timings = try HAR.Timings(
            blocked: 0, dns: -1, connect: 15, send: 20, wait: 38, receive: 12, ssl: -1, comment: "reused DNS")

        // Then
        #expect(
            try encodedJSON(timings)
                == .object([
                    "blocked": .number(0), "dns": .number(-1), "connect": .number(15), "send": .number(20),
                    "wait": .number(38), "receive": .number(12), "ssl": .number(-1), "comment": .string("reused DNS"),
                ]))
    }

    @Test func entryTimeIsTheSumOfAvailableTimingsWithoutSSL() throws {
        // Given: `ssl` is already part of `connect`.
        let timings = try HAR.Timings(
            blocked: 1.5, dns: -1, connect: 30, send: 0.25, wait: 100, receive: 10, ssl: 20)
        var entry = try makeEntry()

        // When
        entry.timings = timings

        // Then
        #expect(entry.time == 141.75)
        #expect(try encodedJSON(entry)["time"] == .number(141.75))
    }

    @Test(arguments: [
        (-1.0, 0.0, 0.0, "send"),
        (0.0, -0.001, 0.0, "wait"),
        (0.0, 0.0, Double.nan, "receive"),
        (Double.infinity, 0.0, 0.0, "send"),
    ])
    func requiredPhasesMustBeNonNegative(send: Double, wait: Double, receive: Double, phase: String) {
        #expect(throws: HAR.TimingsError.invalidValue(phase: phase)) {
            try HAR.Timings(send: send, wait: wait, receive: receive)
        }
    }

    @Test func optionalPhasesMustBeMinusOneOrNonNegative() {
        #expect(throws: HAR.TimingsError.invalidValue(phase: "dns")) {
            try HAR.Timings(dns: -2, send: 0, wait: 0, receive: 0)
        }
        #expect(throws: HAR.TimingsError.invalidValue(phase: "blocked")) {
            try HAR.Timings(blocked: -.infinity, send: 0, wait: 0, receive: 0)
        }
    }

    @Test func sslMustBeIncludedInConnect() throws {
        #expect(throws: HAR.TimingsError.sslNotIncludedInConnect) {
            try HAR.Timings(connect: 10, send: 0, wait: 0, receive: 0, ssl: 11)
        }
        #expect(throws: HAR.TimingsError.sslNotIncludedInConnect) {
            try HAR.Timings(send: 0, wait: 0, receive: 0, ssl: 5)
        }
        #expect(throws: HAR.TimingsError.sslNotIncludedInConnect) {
            try HAR.Timings(connect: -1, send: 0, wait: 0, receive: 0, ssl: 5)
        }
        #expect(try HAR.Timings(connect: -1, send: 0, wait: 0, receive: 0, ssl: -1).ssl == -1)
        #expect(try HAR.Timings(connect: 10, send: 0, wait: 0, receive: 0, ssl: 10).ssl == 10)
    }

    @Test func decodingDoesNotValidate() throws {
        // Given: archives from other tools are read as they are.
        let json = #"{"send":-1,"wait":-1,"receive":-1,"ssl":9}"#

        // When
        let timings = try JSONDecoder().decode(HAR.Timings.self, from: Data(json.utf8))

        // Then
        #expect(timings.send == -1)
        #expect(timings.ssl == 9)
    }
}

/// HAR 1.2 `cache`, `beforeRequest` and `afterRequest`.
@Suite("Cache")
struct CacheTests {
    @Test func unknownStatesAreOmitted() throws {
        // Given: "No cache information are available" is `{}` in the specification's example 1.
        #expect(try encodedJSON(HAR.Cache()) == .object([:]))
    }

    @Test func noEntryIsNull() throws {
        // Given: the specification's example 3.
        let cache = HAR.Cache(beforeRequest: .noEntry, afterRequest: .noEntry)

        // Then
        #expect(try encodedJSON(cache) == .object(["beforeRequest": .null, "afterRequest": .null]))
        #expect(try roundTripped(cache) == cache)
    }

    @Test func entryStatesAreObjects() throws {
        // Given: the specification's example 4, whose dates are not ISO 8601, so they stay strings.
        let stored = HAR.CacheEntry(
            expires: "2009-04-16T15:50:36", lastAccess: "2009-16-02T15:50:34", eTag: "", hitCount: 0)
        let cache = HAR.Cache(beforeRequest: .noEntry, afterRequest: .entry(stored), comment: "stored")

        // When
        let json = try encodedJSON(cache)

        // Then
        #expect(json["beforeRequest"] == .null)
        #expect(
            json["afterRequest"]
                == .object([
                    "expires": .string("2009-04-16T15:50:36"), "lastAccess": .string("2009-16-02T15:50:34"),
                    "eTag": .string(""), "hitCount": .number(0),
                ]))
        #expect(json["comment"] == .string("stored"))
        #expect(try roundTripped(cache) == cache)
    }

    @Test func absentAndNullDecodeDifferently() throws {
        // Given: the specification's example 2.
        let json = #"{"afterRequest":null}"#

        // When
        let cache = try JSONDecoder().decode(HAR.Cache.self, from: Data(json.utf8))

        // Then
        #expect(cache.beforeRequest == nil)
        #expect(cache.afterRequest == .noEntry)
    }
}
