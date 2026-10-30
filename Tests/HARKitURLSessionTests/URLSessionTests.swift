import Foundation
@testable import HARKitURLSession
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("URLRequest")
struct URLRequestTests {
    @Test func convertsMethodURLHeadersAndBody() throws {
        // Given
        var urlRequest = URLRequest(url: try #require(URL(string: "https://example.com/pets?limit=2#list")))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("session=abc", forHTTPHeaderField: "Cookie")
        urlRequest.setValue("1", forHTTPHeaderField: "X-Attempt")
        urlRequest.httpBody = Data(#"{"name":"Rex"}"#.utf8)

        // When
        let request = try HAR.Request(urlRequest, httpVersion: "HTTP/1.1")

        // Then: headers are sorted by name, since URLRequest does not keep their order.
        #expect(request.method == "POST")
        #expect(request.url == "https://example.com/pets?limit=2")
        #expect(request.httpVersion == "HTTP/1.1")
        #expect(request.headers.map(\.name) == ["Content-Type", "Cookie", "X-Attempt"])
        #expect(request.queryString == [HAR.QueryParameter(name: "limit", value: "2")])
        #expect(request.cookies == [HAR.Cookie(name: "session", value: "abc")])
        #expect(request.postData?.payload == .text(#"{"name":"Rex"}"#))
        #expect(request.bodySize == 14)
    }

    @Test func methodDefaultsToGET() throws {
        // Given: URLRequest sends GET when no method is set.
        let urlRequest = URLRequest(url: try #require(URL(string: "https://example.com/")))

        // When
        let request = try HAR.Request(urlRequest, httpVersion: "")

        // Then
        #expect(request.method == "GET")
        #expect(request.bodySize == 0)
        #expect(request.postData == nil)
    }

    @Test func streamedBodyHasUnknownSize() throws {
        // Given: a body stream cannot be read without consuming it.
        var urlRequest = URLRequest(url: try #require(URL(string: "https://example.com/upload")))
        urlRequest.httpMethod = "PUT"
        urlRequest.httpBodyStream = InputStream(data: Data("abc".utf8))

        // When
        let request = try HAR.Request(urlRequest, httpVersion: "")

        // Then
        #expect(request.bodySize == -1)
        #expect(request.postData == nil)
    }

    @Test func requestWithoutURLCannotBeConverted() throws {
        // Given
        var urlRequest = URLRequest(url: try #require(URL(string: "https://example.com/")))
        urlRequest.url = nil

        // Then
        #expect(throws: HAR.URLRequestError.missingURL) { try HAR.Request(urlRequest, httpVersion: "") }
    }
}

@Suite("HTTPURLResponse")
struct HTTPURLResponseTests {
    @Test func convertsStatusHeadersAndBody() throws {
        // Given
        let url = try #require(URL(string: "https://example.com/pets"))
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url, statusCode: 201, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "Location": "/pets/42", "ETag": "\"v1\""]))

        // When
        let response = HAR.Response(httpResponse, body: Data(#"{"id":42}"#.utf8), httpVersion: "HTTP/1.1")

        // Then: HTTPURLResponse has no reason phrase, so statusText is empty rather than made up.
        // (swift-corelibs-foundation rewrites the case of header names, so they are compared lowercased.)
        #expect(response.status == 201)
        #expect(response.statusText == "")
        #expect(response.httpVersion == "HTTP/1.1")
        #expect(response.headers.map { $0.name.lowercased() } == ["content-type", "etag", "location"])
        #expect(response.redirectURL == "/pets/42")
        #expect(response.content == HAR.Content(size: 9, mimeType: "application/json", text: #"{"id":42}"#))
        #expect(response.bodySize == 9)
    }

    @Test func joinedSetCookieHeadersStillGiveEveryCookie() throws {
        // Given: Foundation joins repeated Set-Cookie headers with ", ".
        let url = try #require(URL(string: "https://example.com/"))
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Set-Cookie": "a=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT, b=2; Secure"]))

        // When
        let response = HAR.Response(httpResponse, body: Data(), httpVersion: "")

        // Then
        #expect(response.cookies.map(\.name) == ["a", "b"])
        #expect(response.cookies[1].secure == true)
    }
}

/// The mapping from URLSession transaction dates to HAR 1.2 `timings`.
@Suite("Transaction metrics")
struct TransactionMetricsTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ milliseconds: Double) -> Date { start.addingTimeInterval(milliseconds / 1000) }

    @Test func newConnectionHasEveryPhase() throws {
        // When
        let timings = try #require(
            HAR.Timings(
                fetchStart: at(0), domainLookupStart: at(2), domainLookupEnd: at(10), connectStart: at(10),
                connectEnd: at(50), secureConnectionStart: at(20), secureConnectionEnd: at(50), requestStart: at(51),
                requestEnd: at(53), responseStart: at(153), responseEnd: at(160)))

        // Then: blocked runs until the first network phase, and ssl stays inside connect.
        #expect(timings.blocked == 2)
        #expect(timings.dns == 8)
        #expect(timings.connect == 40)
        #expect(timings.ssl == 30)
        #expect(timings.send == 2)
        #expect(timings.wait == 100)
        #expect(timings.receive == 7)
    }

    @Test func reusedConnectionMarksSetupPhasesAsNotApplicable() throws {
        // When
        let timings = try #require(
            HAR.Timings(
                fetchStart: at(0), domainLookupStart: nil, domainLookupEnd: nil, connectStart: nil, connectEnd: nil,
                secureConnectionStart: nil, secureConnectionEnd: nil, requestStart: at(1), requestEnd: at(2),
                responseStart: at(30), responseEnd: at(31)))

        // Then
        #expect(timings.dns == -1)
        #expect(timings.connect == -1)
        #expect(timings.ssl == -1)
        #expect(timings.blocked == 1)
    }

    @Test func missingFetchStartLeavesBlockedOut() throws {
        // When
        let timings = try #require(
            HAR.Timings(
                fetchStart: nil, domainLookupStart: nil, domainLookupEnd: nil, connectStart: nil, connectEnd: nil,
                secureConnectionStart: nil, secureConnectionEnd: nil, requestStart: at(1), requestEnd: at(2),
                responseStart: at(30), responseEnd: at(31)))

        // Then
        #expect(timings.blocked == nil)
    }

    @Test func transactionWithoutRequestAndResponseDatesHasNoTimings() {
        // Given: for example a response served from the local cache.
        let timings = HAR.Timings(
            fetchStart: at(0), domainLookupStart: nil, domainLookupEnd: nil, connectStart: nil, connectEnd: nil,
            secureConnectionStart: nil, secureConnectionEnd: nil, requestStart: nil, requestEnd: nil,
            responseStart: nil, responseEnd: at(1))

        // Then
        #expect(timings == nil)
    }

    @Test func responseBeforeTheRequestEndedHasNoTimings() {
        // Given: a server that answers before the upload finishes would give a negative wait.
        let timings = HAR.Timings(
            fetchStart: at(0), domainLookupStart: nil, domainLookupEnd: nil, connectStart: nil, connectEnd: nil,
            secureConnectionStart: nil, secureConnectionEnd: nil, requestStart: at(1), requestEnd: at(50),
            responseStart: at(10), responseEnd: at(60))

        // Then: no phase is adjusted to make it fit.
        #expect(timings == nil)
    }
}
