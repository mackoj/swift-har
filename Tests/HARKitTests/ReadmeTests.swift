import HARKit
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Keeps the README snippets compiling and truthful.
@Suite("README examples")
struct ReadmeTests {
    private func readmeEntry() throws -> HAR.Entry {
        let requestStart = Date()  // when you sent the request

        let request = HAR.Request(
            method: "POST",
            url: URL(string: "https://api.example.com/pets?limit=10#top")!,
            httpVersion: "HTTP/1.1",
            headers: [
                HAR.Header(name: "Content-Type", value: "application/json"),
                HAR.Header(name: "Cookie", value: "session=abc123"),
            ],
            body: Data(#"{"name":"Rex"}"#.utf8)
        )
        let response = HAR.Response(
            status: 201,
            statusText: "Created",
            httpVersion: "HTTP/1.1",
            headers: [
                HAR.Header(name: "Content-Type", value: "application/json"),
                HAR.Header(name: "Set-Cookie", value: "theme=dark; Path=/; HttpOnly"),
            ],
            body: Data(#"{"id":42}"#.utf8)
        )
        let timings = try HAR.Timings(dns: -1, connect: -1, send: 1.2, wait: 85.4, receive: 3.1)

        return HAR.Entry(startedDateTime: requestStart, request: request, response: response, timings: timings)
    }

    @Test func buildingAnEntryDerivesTheDocumentedFields() throws {
        // When
        let entry = try readmeEntry()

        // Then: the derived-fields table.
        #expect(entry.request.url == "https://api.example.com/pets?limit=10")
        #expect(entry.request.queryString == [HAR.QueryParameter(name: "limit", value: "10")])
        #expect(entry.request.cookies == [HAR.Cookie(name: "session", value: "abc123")])
        #expect(entry.request.postData?.payload == .text(#"{"name":"Rex"}"#))
        #expect(entry.request.bodySize == 14)
        #expect(entry.response.content.text == #"{"id":42}"#)
        #expect(entry.response.cookies.first?.httpOnly == true)
        #expect(entry.response.redirectURL == "")
        #expect(entry.response.bodySize == 9)
        #expect(entry.request.headersSize == -1 && entry.response.headersSize == -1)
        #expect(abs(entry.time - 89.7) < 1e-9)
    }

    @Test func writingAndReadingTheFile() throws {
        // Given
        let entry = try readmeEntry()

        // When
        let log = HAR.Log(creator: HAR.Creator(name: "MyApp", version: "1.0"), entries: [entry])
        let data = try HAR.Archive(log: log).jsonData(prettyPrinted: true)
        let archive = try HAR.Archive(json: data)

        // Then
        var lines: [String] = []
        for entry in archive.log.entries {
            lines.append("\(entry.request.method) \(entry.request.url) \(entry.response.status)")
        }
        #expect(lines == ["POST https://api.example.com/pets?limit=10 201"])
    }

    @Test func missingDataExamples() throws {
        // When
        let unmeasured = try HAR.Timings(send: 0, wait: 0, receive: 0, comment: "Timings were not measured")
        let failed = HAR.Response(
            status: 0, statusText: "", httpVersion: "",
            content: HAR.Content(size: 0, mimeType: ""),
            comment: "The request timed out"
        )

        // Then
        #expect(unmeasured.send == 0)
        #expect(failed.bodySize == -1 && failed.headersSize == -1)
    }
}
