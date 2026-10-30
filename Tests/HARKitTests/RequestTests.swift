import HARKit
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// HAR 1.2 `request`, `headers`, `queryString`, `cookies` (request side), `postData` and `params`.
@Suite("Request")
struct RequestTests {
    private func request(
        _ url: String, method: String = "GET", headers: [HAR.Header] = [], body: Data? = nil
    ) throws -> HAR.Request {
        HAR.Request(
            method: method, url: try #require(URL(string: url)), httpVersion: "HTTP/1.1", headers: headers, body: body)
    }

    @Test func getWithoutBodyHasAllRequiredFields() throws {
        // Given
        let request = try request("https://example.com/path")

        // When
        let json = try encodedJSON(request)

        // Then: no postData, a zero-length body, and headersSize not available.
        #expect(
            json.keys == [
                "method", "url", "httpVersion", "cookies", "headers", "queryString", "headersSize", "bodySize",
            ])
        #expect(json["method"] == .string("GET"))
        #expect(json["url"] == .string("https://example.com/path"))
        #expect(json["httpVersion"] == .string("HTTP/1.1"))
        #expect(json["headersSize"] == .number(-1))
        #expect(json["bodySize"] == .number(0))
    }

    @Test func urlFragmentIsRemoved() throws {
        // Given: HAR 1.2 `request.url` is absolute and excludes fragments.
        let request = try request("https://example.com/a?b=c#section-2")

        // Then
        #expect(request.url == "https://example.com/a?b=c")
    }

    @Test func headersKeepOrderDuplicatesAndUnusualValues() throws {
        // Given
        let headers = [
            header("X-B", "2"), header("x-a", ""), header("X-B", "1"), header("Date", "Wed, 21 Oct 2015 07:28:00 GMT"),
            header("X-Colon", "a: b"), header("X-Unicode", "naïve ✓"), header("X-Space", "  padded  "),
        ]

        // When
        let request = try request("https://example.com/", headers: headers)

        // Then: exported exactly as given.
        #expect(request.headers == headers)
    }

    @Test func queryStringIsParsedFromTheURL() throws {
        // Given
        let request = try request("https://example.com/?a=1&a=2&flag&empty=&sp=a+b%20c&eq=x=y&&utf=%E2%82%AC")

        // Then: duplicates kept in order, percent-decoded, `+` left alone (only forms use it for spaces).
        #expect(
            request.queryString == [
                HAR.QueryParameter(name: "a", value: "1"),
                HAR.QueryParameter(name: "a", value: "2"),
                HAR.QueryParameter(name: "flag", value: ""),
                HAR.QueryParameter(name: "empty", value: ""),
                HAR.QueryParameter(name: "sp", value: "a+b c"),
                HAR.QueryParameter(name: "eq", value: "x=y"),
                HAR.QueryParameter(name: "utf", value: "€"),
            ])
    }

    @Test func malformedPercentEscapesAreKeptAsWritten() throws {
        // Given
        let request = try request("https://example.com/?bad=%zz&cut=%E2%82&end=%")

        // Then
        #expect(
            request.queryString == [
                HAR.QueryParameter(name: "bad", value: "%zz"),
                HAR.QueryParameter(name: "cut", value: "%E2%82"),
                HAR.QueryParameter(name: "end", value: "%"),
            ])
    }

    @Test(arguments: ["https://example.com/", "https://example.com/?", "https://example.com/?#frag"])
    func noQueryMeansNoParameters(url: String) throws {
        #expect(try request(url).queryString.isEmpty)
    }

    @Test func cookiesAreParsedFromCookieHeaders() throws {
        // Given
        let headers = [header("cookie", "a=1; b=x=y;c=\"quoted\""), header("Cookie", "d=; flag"), header("X", "e=5")]

        // When
        let request = try request("https://example.com/", headers: headers)
        let json = try encodedJSON(request)

        // Then: request cookies carry only name and value; attributes are not sent by clients.
        #expect(
            request.cookies == [
                HAR.Cookie(name: "a", value: "1"),
                HAR.Cookie(name: "b", value: "x=y"),
                HAR.Cookie(name: "c", value: "\"quoted\""),
                HAR.Cookie(name: "d", value: ""),
                HAR.Cookie(name: "", value: "flag"),
            ])
        #expect(json["cookies"]?[0] == .object(["name": .string("a"), "value": .string("1")]))
    }

    @Test func textBodyBecomesPostDataText() throws {
        // Given
        let body = Data(#"{"name":"café"}"#.utf8)

        // When
        let request = try request(
            "https://example.com/", method: "POST",
            headers: [header("Content-Type", "application/json; charset=utf-8")],
            body: body)
        let json = try encodedJSON(request)

        // Then: mimeType is the header value, bodySize counts bytes, not characters.
        #expect(
            request.postData
                == HAR.PostData(mimeType: "application/json; charset=utf-8", payload: .text(#"{"name":"café"}"#)))
        #expect(request.bodySize == 16)
        #expect(json["postData"]?.keys == ["mimeType", "text"])
    }

    @Test func formBodyBecomesParams() throws {
        // Given
        let body = Data("q=swift+har&lang=en&q=%C3%A9t%C3%A9&flag".utf8)

        // When
        let request = try request(
            "https://example.com/", method: "POST",
            headers: [header("Content-Type", "application/x-www-form-urlencoded")], body: body)
        let json = try encodedJSON(request)

        // Then: HAR 1.2 `postData.text` and `params` are mutually exclusive; form `+` means space.
        #expect(
            request.postData?.payload
                == .params([
                    HAR.PostParameter(name: "q", value: "swift har"),
                    HAR.PostParameter(name: "lang", value: "en"),
                    HAR.PostParameter(name: "q", value: "été"),
                    HAR.PostParameter(name: "flag", value: ""),
                ]))
        #expect(json["postData"]?.keys == ["mimeType", "params"])
        #expect(json["postData"]?["params"]?[0] == .object(["name": .string("q"), "value": .string("swift har")]))
    }

    @Test(arguments: [
        ("application/octet-stream", Data([0x00, 0xFF, 0x10])),
        ("text/plain", Data([0xC3, 0x28])),
        ("text/plain; charset=iso-8859-1", Data("caf\u{E9}".utf8)),
        ("application/json; charset=UTF-16", Data([0x7B, 0x00, 0x7D, 0x00])),
        ("", Data("no content type".utf8)),
        ("multipart/form-data; boundary=x", Data("--x\r\n".utf8)),
    ])
    func bodyThatIsNotTextIsLeftOutOfPostData(contentType: String, body: Data) throws {
        // Given: HAR 1.2 postData has no `encoding`, so non-text bodies cannot be represented (ADR 0004).
        let headers = contentType.isEmpty ? [] : [header("Content-Type", contentType)]

        // When
        let request = try request("https://example.com/", method: "PUT", headers: headers, body: body)

        // Then: the size is still reported.
        #expect(request.postData == nil)
        #expect(request.bodySize == body.count)
    }

    @Test func emptyBodyIsSizeZeroWithEmptyText() throws {
        // Given
        let request = try request(
            "https://example.com/", method: "POST", headers: [header("Content-Type", "text/plain")], body: Data())

        // Then
        #expect(request.bodySize == 0)
        #expect(request.postData == HAR.PostData(mimeType: "text/plain", payload: .text("")))
    }

    @Test func postDataInitializerAcceptsTextualMediaTypes() {
        // Given
        let textual = [
            "text/csv", "application/json", "application/problem+json", "application/xml", "image/svg+xml",
            "application/javascript", "application/graphql", "application/x-ndjson", "TEXT/PLAIN ; Charset=\"utf-8\"",
            "application/json; charset=us-ascii",
        ]

        // Then
        for mimeType in textual {
            #expect(HAR.PostData(body: Data("{}".utf8), mimeType: mimeType) != nil, "\(mimeType)")
        }
    }

    @Test func decodedPostDataWithBothTextAndParamsKeepsTheText() throws {
        // Given: some writers put both fields although HAR 1.2 makes them mutually exclusive.
        let json = #"{"mimeType":"application/x-www-form-urlencoded","text":"a=1","params":[{"name":"a","value":"1"}]}"#

        // When
        let postData = try JSONDecoder().decode(HAR.PostData.self, from: Data(json.utf8))

        // Then
        #expect(postData.payload == .text("a=1"))
    }

    @Test func postParameterFieldsAreOptional() throws {
        // Given
        let file = HAR.PostParameter(
            name: "upload", value: "…", fileName: "example.pdf", contentType: "application/pdf")

        // Then
        #expect(try encodedJSON(HAR.PostParameter(name: "only")) == .object(["name": .string("only")]))
        #expect(try encodedJSON(file).keys == ["name", "value", "fileName", "contentType"])
        #expect(try roundTripped(file) == file)
    }
}
