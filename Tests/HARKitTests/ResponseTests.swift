import HARKit
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// HAR 1.2 `response`, `content` and `cookies` (response side).
@Suite("Response")
struct ResponseTests {
    private func response(status: Int = 200, headers: [HAR.Header] = [], body: Data = Data()) -> HAR.Response {
        HAR.Response(status: status, statusText: "OK", httpVersion: "HTTP/1.1", headers: headers, body: body)
    }

    @Test func hasAllRequiredFields() throws {
        // Given
        let response = response(headers: [header("Content-Type", "text/plain")], body: Data("hi".utf8))

        // When
        let json = try encodedJSON(response)

        // Then
        #expect(
            json.keys == [
                "status", "statusText", "httpVersion", "cookies", "headers", "content", "redirectURL", "headersSize",
                "bodySize",
            ])
        #expect(json["status"] == .number(200))
        #expect(json["redirectURL"] == .string(""))
        #expect(json["headersSize"] == .number(-1))
        #expect(json["bodySize"] == .number(2))
        #expect(
            json["content"] == .object(["size": .number(2), "mimeType": .string("text/plain"), "text": .string("hi")]))
    }

    @Test func textBodyIsWrittenAsText() {
        // Given
        let body = Data(#"{"ok":true,"name":"zoë"}"#.utf8)

        // When
        let content = HAR.Content(body: body, mimeType: "application/json; charset=utf-8")

        // Then
        #expect(
            content
                == HAR.Content(
                    size: 25, mimeType: "application/json; charset=utf-8", text: #"{"ok":true,"name":"zoë"}"#))
    }

    @Test func binaryBodyIsBase64() throws {
        // Given: the bytes of the specification's `content` example, whose encoded text is quoted there.
        let body = Data(#"<html><head></head><body/></html>\n"#.utf8)

        // When
        let content = HAR.Content(body: body, mimeType: "application/octet-stream")

        // Then
        #expect(content.text == "PGh0bWw+PGhlYWQ+PC9oZWFkPjxib2R5Lz48L2h0bWw+XG4=")
        #expect(content.encoding == "base64")
        #expect(content.size == body.count)
        #expect(try encodedJSON(content).keys == ["size", "mimeType", "text", "encoding"])
    }

    @Test(arguments: [
        ("image/png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        ("text/plain", Data([0xC3, 0x28])),
        ("text/html; charset=iso-8859-1", Data("café".utf8)),
        ("", Data("plain".utf8)),
    ])
    func bodyThatIsNotUTF8TextIsBase64(mimeType: String, body: Data) throws {
        // When
        let content = HAR.Content(body: body, mimeType: mimeType)

        // Then: decoding the base64 gives the exact bytes back.
        #expect(content.encoding == "base64")
        #expect(Data(base64Encoded: try #require(content.text)) == body)
    }

    @Test func missingContentTypeGivesAnEmptyMimeType() {
        // Given
        let response = response(body: Data([1, 2, 3]))

        // Then: no MIME type is invented.
        #expect(response.content.mimeType == "")
    }

    @Test func emptyBodyHasNoText() throws {
        // Given
        let response = response(status: 204, headers: [header("Content-Type", "text/plain")])

        // Then
        #expect(response.content == HAR.Content(size: 0, mimeType: "text/plain"))
        #expect(response.bodySize == 0)
        #expect(try encodedJSON(response.content).keys == ["size", "mimeType"])
    }

    @Test func compressedTransferSizeIsNotAvailable() {
        // Given: the body passed in is already decoded, so the bytes on the wire are unknown.
        let gzip = response(headers: [header("Content-Encoding", "gzip")], body: Data("hello".utf8))
        let identity = response(headers: [header("content-encoding", "identity")], body: Data("hello".utf8))

        // Then
        #expect(gzip.bodySize == -1)
        #expect(gzip.content.size == 5)
        #expect(gzip.content.compression == nil)
        #expect(identity.bodySize == 5)
    }

    @Test func redirectURLComesFromTheLocationHeader() {
        // Given
        let redirect = response(status: 301, headers: [header("location", "/new?x=1")])

        // Then
        #expect(redirect.redirectURL == "/new?x=1")
    }

    @Test func setCookieAttributesAreParsed() throws {
        // Given
        let headers = [
            header(
                "Set-Cookie",
                "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/docs; Domain=example.com; Secure; HttpOnly"),
            header("set-cookie", "theme=dark; Max-Age=3600; SameSite=Lax"),
        ]

        // When
        let response = response(headers: headers)
        let json = try encodedJSON(response)

        // Then: Max-Age is not converted (that needs a clock); absent flags are known to be false.
        #expect(
            response.cookies == [
                HAR.Cookie(
                    name: "id", value: "a3fWa", path: "/docs", domain: "example.com",
                    expires: Date(timeIntervalSince1970: 1_445_412_480), httpOnly: true, secure: true),
                HAR.Cookie(name: "theme", value: "dark", httpOnly: false, secure: false),
            ])
        #expect(json["cookies"]?[0]?["expires"] == .string("2015-10-21T07:28:00.000Z"))
    }

    @Test(arguments: [
        ("Wed, 21 Oct 2015 07:28:00 GMT", 1_445_412_480.0),
        ("Wednesday, 21-Oct-15 07:28:00 GMT", 1_445_412_480.0),
        ("Wed Oct 21 07:28:00 2015", 1_445_412_480.0),
        ("21 oct 2015 7:28:00", 1_445_412_480.0),
        ("Thu, 01 Jan 1970 00:00:00 GMT", 0.0),
        ("Thu, 01-Jan-70 00:00:00 GMT", 0.0),
        ("Tue, 01-Jan-69 00:00:00 GMT", 3_124_224_000.0),
    ])
    func setCookieExpiresFollowsRFC6265DateParsing(expires: String, seconds: Double) {
        // Given
        let response = response(headers: [header("Set-Cookie", "a=b; expires=\(expires)")])

        // Then
        #expect(response.cookies.first?.expires == Date(timeIntervalSince1970: seconds))
    }

    @Test(arguments: [
        "soon", "Wed, 32 Oct 2015 07:28:00 GMT", "Wed, 21 Foo 2015 07:28:00 GMT", "21 Oct 1500 07:28:00", "",
    ])
    func unparseableExpiresIsOmitted(expires: String) {
        // Given
        let response = response(headers: [header("Set-Cookie", "a=b; Expires=\(expires)")])

        // Then
        #expect(response.cookies == [HAR.Cookie(name: "a", value: "b", httpOnly: false, secure: false)])
    }

    @Test func setCookieValuesJoinedWithCommasAreSplit() {
        // Given: HTTP stacks such as Foundation join repeated Set-Cookie headers with ", ".
        let joined = "a=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/, b=2, c=x,y; HttpOnly"

        // When
        let response = response(headers: [header("Set-Cookie", joined)])

        // Then
        #expect(response.cookies.map(\.name) == ["a", "b", "c"])
        #expect(response.cookies.map(\.value) == ["1", "2", "x,y"])
        #expect(response.cookies[0].path == "/")
        #expect(response.cookies[2].httpOnly == true)
    }

    @Test func setCookieWithoutNameValuePairIsIgnored() {
        // Given: RFC 6265 §5.2 ignores a set-cookie-string with no `=` or an empty name and value.
        let response = response(headers: [header("Set-Cookie", "; Path=/"), header("Set-Cookie", "")])

        // Then
        #expect(response.cookies.isEmpty)
    }

    @Test func cookieOptionalFieldsAreOmittedWhenUnknown() throws {
        #expect(
            try encodedJSON(HAR.Cookie(name: "a", value: "b"))
                == .object(["name": .string("a"), "value": .string("b")]))
    }
}
