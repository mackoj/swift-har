import HARKit
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// HAR 1.2 `log`, `creator`, `browser`, `pages`, `pageTimings` and `entries`, and the JSON file itself.
@Suite("Archive and log")
struct ArchiveTests {
    @Test func minimalLogHasOnlyTheRequiredFields() throws {
        // Given
        let log = HAR.Log(creator: HAR.Creator(name: "MyApp", version: "2.1"), entries: [])

        // When
        let json = try encodedJSON(HAR.Archive(log: log))

        // Then
        #expect(json.keys == ["log"])
        #expect(json["log"]?.keys == ["version", "creator", "entries"])
        #expect(json["log"]?["version"] == .string("1.2"))
        #expect(json["log"]?["creator"] == .object(["name": .string("MyApp"), "version": .string("2.1")]))
        #expect(json["log"]?["entries"] == .array([]))
    }

    @Test func optionalLogFieldsAreWrittenWhenGiven() throws {
        // Given
        let page = HAR.Page(startedDateTime: exampleDate, id: "page_0", title: "Test Page")
        let log = HAR.Log(
            creator: HAR.Creator(name: "MyApp", version: "2.1", comment: "nightly"),
            browser: HAR.Creator(name: "Firefox", version: "3.6"),
            pages: [page],
            entries: [],
            comment: "exported for a bug report"
        )

        // When
        let json = try encodedJSON(log)

        // Then
        #expect(json.keys == ["version", "creator", "browser", "pages", "entries", "comment"])
        #expect(json["creator"]?["comment"] == .string("nightly"))
        #expect(json["browser"] == .object(["name": .string("Firefox"), "version": .string("3.6")]))
        #expect(json["comment"] == .string("exported for a bug report"))
    }

    @Test func pageTimingsThatAreNotKnownAreOmitted() throws {
        // Given: HAR 1.2 `pageTimings` fields default to -1 (not available) and are optional.
        let page = HAR.Page(startedDateTime: exampleDate, id: "page_0", title: "Test Page")
        let measured = HAR.Page(
            startedDateTime: exampleDate, id: "page_1", title: "",
            pageTimings: HAR.PageTimings(onContentLoad: 1720, onLoad: 2500))

        // When
        let json = try encodedJSON(page)
        let measuredJSON = try encodedJSON(measured)

        // Then
        #expect(json.keys == ["startedDateTime", "id", "title", "pageTimings"])
        #expect(json["startedDateTime"] == .string("2009-04-16T12:07:23.596Z"))
        #expect(json["pageTimings"] == .object([:]))
        #expect(measuredJSON["pageTimings"] == .object(["onContentLoad": .number(1720), "onLoad": .number(2500)]))
    }

    @Test func entryHasEveryRequiredFieldAndNoOptionalOnes() throws {
        // Given
        let entry = try makeEntry()

        // When
        let json = try encodedJSON(entry)

        // Then: HAR 1.2 `entries` requires startedDateTime, time, request, response, cache and timings.
        #expect(json.keys == ["startedDateTime", "time", "request", "response", "cache", "timings"])
        #expect(json["startedDateTime"] == .string("2009-04-16T12:07:23.596Z"))
        #expect(json["time"] == .number(70))
        #expect(json["cache"] == .object([:]))
    }

    @Test func entryOptionalFieldsAreWrittenWhenGiven() throws {
        // Given
        var entry = try makeEntry()
        entry.pageref = "page_0"
        entry.serverIPAddress = "10.0.0.1"
        entry.connection = "52492"
        entry.comment = "retried once"

        // When
        let json = try encodedJSON(entry)

        // Then
        #expect(json["pageref"] == .string("page_0"))
        #expect(json["serverIPAddress"] == .string("10.0.0.1"))
        #expect(json["connection"] == .string("52492"))
        #expect(json["comment"] == .string("retried once"))
    }

    @Test(arguments: [
        (1_239_883_643.596, "2009-04-16T12:07:23.596Z"),
        (1_239_883_643.0, "2009-04-16T12:07:23.000Z"),
        (1_239_883_643.0004, "2009-04-16T12:07:23.000Z"),
        (1_239_883_643.9996, "2009-04-16T12:07:24.000Z"),
        (0, "1970-01-01T00:00:00.000Z"),
        (-0.5, "1969-12-31T23:59:59.500Z"),
    ])
    func datesAreISO8601WithMilliseconds(seconds: Double, expected: String) throws {
        // Given
        let entry = try makeEntry(startedDateTime: Date(timeIntervalSince1970: seconds))

        // When
        let json = try encodedJSON(entry)

        // Then: rounded to the nearest millisecond, in UTC.
        #expect(json["startedDateTime"] == .string(expected))
    }

    @Test func entriesAreSortedByStartTimeKeepingTheOrderOfTies() throws {
        // Given: HAR 1.2 `entries` prefers export sorted by startedDateTime, oldest first.
        let late = try makeEntry(startedDateTime: exampleDate.addingTimeInterval(5))
        var firstTie = try makeEntry()
        firstTie.comment = "first"
        var secondTie = try makeEntry()
        secondTie.comment = "second"

        // When
        let log = HAR.Log(creator: HAR.Creator(name: "a", version: "1"), entries: [late, firstTie, secondTie])

        // Then
        #expect(log.entries == [firstTie, secondTie, late])
    }

    @Test func jsonDataDecodesBackToTheSameArchive() throws {
        // Given
        let request = HAR.Request(
            method: "POST", url: URL(string: "https://example.com/p?q=1#top")!, httpVersion: "HTTP/2",
            headers: [header("Content-Type", "application/json"), header("Cookie", "a=1")],
            body: Data(#"{"é":1}"#.utf8))
        let response = HAR.Response(
            status: 201, statusText: "Created", httpVersion: "HTTP/2",
            headers: [header("Content-Type", "image/png"), header("Set-Cookie", "b=2; Path=/; Secure")],
            body: Data([0x89, 0x50, 0x4E, 0x47]))
        // HAR dates have millisecond precision, so the round trip uses a date that is exact at that precision.
        let started = Date(timeIntervalSince1970: 1_239_883_643.5)
        var entry = try makeEntry(request: request, response: response, startedDateTime: started)
        entry.pageref = "page_0"
        entry.cache = HAR.Cache(beforeRequest: .noEntry)
        let archive = HAR.Archive(
            log: HAR.Log(
                creator: HAR.Creator(name: "MyApp", version: "2.1"),
                pages: [HAR.Page(startedDateTime: started, id: "page_0", title: "Home")],
                entries: [entry]))

        // When
        let compact = try HAR.Archive(json: archive.jsonData())
        let pretty = try HAR.Archive(json: archive.jsonData(prettyPrinted: true))

        // Then
        #expect(compact == archive)
        #expect(pretty == archive)
    }

    @Test func jsonDataIsUTF8WithUnescapedSlashes() throws {
        // Given: HAR files must be UTF-8.
        let request = HAR.Request(method: "GET", url: URL(string: "https://example.com/caf%C3%A9")!, httpVersion: "")
        var entry = try makeEntry(request: request)
        entry.comment = "café ☕️"
        let archive = HAR.Archive(log: HAR.Log(creator: HAR.Creator(name: "a", version: "1"), entries: [entry]))

        // When
        let text = try #require(String(validating: try archive.jsonData(), as: UTF8.self))

        // Then
        #expect(text.contains("café ☕️"))
        #expect(text.contains(#""url":"https://example.com/caf%C3%A9""#))
    }

    @Test func decodingIgnoresAByteOrderMark() throws {
        // Given: HAR 1.2 requires readers to support and ignore a BOM.
        let json = #"{"log":{"version":"1.2","creator":{"name":"x","version":"1"},"entries":[]}}"#
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)

        // When
        let archive = try HAR.Archive(json: data)

        // Then
        #expect(archive.log.creator.name == "x")
        #expect(archive.log.entries.isEmpty)
    }

    @Test func decodesAnArchiveWrittenByAnotherTool() throws {
        // Given: values in the specification's own examples (a +01:00 offset, a `time` that does not
        // match the timings, `cache` with `null`), a custom field and a `-1` required timing that
        // other writers produce.
        let json = """
            {"log": {"version": "1.2", "creator": {"name": "Firebug", "version": "1.6"},
              "_custom": {"x": 1},
              "pages": [{"startedDateTime": "2009-04-16T12:07:25.123+01:00", "id": "page_0", "title": "Test Page",
                         "pageTimings": {"onContentLoad": 1720, "onLoad": 2500}}],
              "entries": [{
                "pageref": "page_0", "startedDateTime": "2009-04-16T12:07:23Z", "time": 999,
                "request": {"method": "GET", "url": "http://www.example.com/path/?param=value", "httpVersion": "HTTP/1.1",
                            "cookies": [], "headers": [], "queryString": [{"name": "param", "value": "value"}],
                            "headersSize": 150, "bodySize": 0},
                "response": {"status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1", "cookies": [],
                             "headers": [], "content": {"size": 33, "compression": 0, "mimeType": "text/html; charset=utf-8",
                             "text": "\\n"}, "redirectURL": "", "headersSize": 160, "bodySize": 850, "_error": "none"},
                "cache": {"beforeRequest": null},
                "timings": {"blocked": 0, "dns": -1, "connect": 15, "send": 20, "wait": 38, "receive": -1, "ssl": -1}
              }]}}
            """

        // When
        let archive = try HAR.Archive(json: Data(json.utf8))

        // Then
        let entry = try #require(archive.log.entries.first)
        let pageStart = try #require(archive.log.pages?.first?.startedDateTime)
        #expect(abs(pageStart.timeIntervalSince1970 - 1_239_880_045.123) < 0.000_5)
        #expect(entry.startedDateTime == Date(timeIntervalSince1970: 1_239_883_643))
        #expect(entry.cache.beforeRequest == .noEntry)
        #expect(entry.cache.afterRequest == nil)
        #expect(entry.timings.receive == -1)
        #expect(entry.time == 73)
        #expect(entry.response.content.compression == 0)
        #expect(entry.request.queryString == [HAR.QueryParameter(name: "param", value: "value")])
    }

    @Test func rejectsADocumentWithoutTheRequiredFields() {
        // Given: `entries` is required in HAR 1.2 `log`.
        let json = #"{"log":{"version":"1.2","creator":{"name":"x","version":"1"}}}"#

        // Then
        #expect(throws: DecodingError.self) { try HAR.Archive(json: Data(json.utf8)) }
    }

    @Test func rejectsAMalformedDate() {
        // Given
        let json = #"{"startedDateTime":"yesterday","id":"p","title":"","pageTimings":{}}"#

        // Then
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HAR.Page.self, from: Data(json.utf8)) }
    }
}
