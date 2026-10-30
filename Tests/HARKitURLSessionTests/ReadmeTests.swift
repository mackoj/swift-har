import Foundation
import HARKitURLSession
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The README's "From URLSession" snippet. URLSession task metrics cannot be created in a test, so
/// this keeps the snippet compiling and checks the pieces it relies on.
@Suite("README examples (URLSession)")
struct URLSessionReadmeTests {
    /// Call from `urlSession(_:task:didFinishCollecting:)` with the body you received.
    func harEntry(task: URLSessionTask, body: Data, metrics: URLSessionTaskMetrics) throws -> HAR.Entry? {
        guard let sent = task.currentRequest ?? task.originalRequest,
            let received = task.response as? HTTPURLResponse,
            let transaction = metrics.transactionMetrics.last,
            let timings = HAR.Timings(transaction)
        else { return nil }
        let httpVersion = transaction.networkProtocolName ?? ""
        return HAR.Entry(
            startedDateTime: transaction.fetchStartDate ?? metrics.taskInterval.start,
            request: try HAR.Request(sent, httpVersion: httpVersion),
            response: HAR.Response(received, body: body, httpVersion: httpVersion),
            timings: timings
        )
    }

    @Test func convertedRequestAndResponseMakeAnEntry() throws {
        // Given
        let url = try #require(URL(string: "https://api.example.com/pets"))
        let sent = URLRequest(url: url)
        let received = try #require(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Encoding": "gzip"]))

        // When
        let entry = HAR.Entry(
            startedDateTime: Date(timeIntervalSince1970: 0),
            request: try HAR.Request(sent, httpVersion: "h2"),
            response: HAR.Response(received, body: Data("[]".utf8), httpVersion: "h2"),
            timings: try HAR.Timings(send: 0, wait: 0, receive: 0))

        // Then: the documented URLSession details.
        #expect(entry.request.httpVersion == "h2")
        #expect(entry.response.statusText == "")
        #expect(entry.response.bodySize == -1)
        #expect(entry.response.content.size == 2)
    }
}
