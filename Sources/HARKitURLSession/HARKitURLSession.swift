@_exported import HARKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HAR {
    /// Why a `URLRequest` could not be converted.
    public enum URLRequestError: Error, Hashable, Sendable {
        /// The request has no URL, and HAR 1.2 requires one.
        case missingURL
    }
}

extension HAR.Request {
    /// Creates a request from a `URLRequest`, as `HAR.Request.init(method:url:httpVersion:headers:body:)` does.
    ///
    /// Pass the request that was actually sent (`URLSessionTask.currentRequest`) to include the
    /// headers URLSession added. Cookies URLSession attaches from its cookie storage, and headers it
    /// sets itself (such as `Accept-Encoding`), are not part of a `URLRequest` and so are missing.
    ///
    /// `URLRequest` keeps neither the order nor the repetitions of headers, so they are sorted by
    /// name. A body given as `httpBodyStream` cannot be read without consuming it: it is left out
    /// and `HAR.Request.bodySize` is `-1`.
    ///
    /// - Parameters:
    ///   - request: The request that was sent.
    ///   - httpVersion: For example `HTTP/1.1`, or `URLSessionTaskTransactionMetrics.networkProtocolName`
    ///     (`h2`, `http/1.1`); empty when not known.
    /// - Throws: ``HAR/URLRequestError/missingURL`` when `request.url` is `nil`.
    public init(_ request: URLRequest, httpVersion: String) throws(HAR.URLRequestError) {
        guard let url = request.url else { throw .missingURL }
        self.init(
            method: request.httpMethod ?? "GET", url: url, httpVersion: httpVersion,
            headers: sortedHeaders(request.allHTTPHeaderFields ?? [:]), body: request.httpBody)
        if request.httpBody == nil && request.httpBodyStream != nil {
            bodySize = -1
        }
    }
}

extension HAR.Response {
    /// Creates a response from an `HTTPURLResponse` and its body, as
    /// `HAR.Response.init(status:statusText:httpVersion:headers:body:)` does.
    ///
    /// `HTTPURLResponse` exposes no reason phrase, so `HAR.Response.statusText` is empty. Headers
    /// are sorted by name, because their order is not kept; repeated `Set-Cookie` headers that
    /// Foundation joined with commas still give one cookie each.
    ///
    /// - Parameters:
    ///   - response: The response that was received.
    ///   - body: The body as URLSession delivered it (already decompressed); an empty `Data` states
    ///     that it was empty.
    ///   - httpVersion: For example `HTTP/1.1`, or `URLSessionTaskTransactionMetrics.networkProtocolName`
    ///     (`h2`, `http/1.1`); empty when not known.
    public init(_ response: HTTPURLResponse, body: Data, httpVersion: String) {
        var fields: [String: String] = [:]
        for case (let name as String, let value as String) in response.allHeaderFields {
            fields[name] = value
        }
        self.init(
            status: response.statusCode, statusText: "", httpVersion: httpVersion, headers: sortedHeaders(fields),
            body: body)
    }
}

extension HAR.Timings {
    /// The timings of one URLSession transaction (`URLSessionTaskMetrics.transactionMetrics`),
    /// or `nil` when it did not record a request and a response, as for a response served from the
    /// local cache.
    ///
    /// - `blocked` runs from the fetch start to the first network phase, and is omitted without a
    ///   fetch start date.
    /// - `dns`, `connect` and `ssl` are `-1` when the transaction has no dates for them, as on a
    ///   reused connection. `connect` includes `ssl`.
    /// - `send`, `wait` and `receive` come from the request and response dates. If they are out of
    ///   order (a server that answered before the upload finished), the result is `nil` rather than
    ///   adjusted timings.
    ///
    /// swift-corelibs-foundation records few or no transaction metrics on Linux, so this mostly
    /// applies to Apple platforms.
    public init?(_ metrics: URLSessionTaskTransactionMetrics) {
        self.init(
            fetchStart: metrics.fetchStartDate, domainLookupStart: metrics.domainLookupStartDate,
            domainLookupEnd: metrics.domainLookupEndDate, connectStart: metrics.connectStartDate,
            connectEnd: metrics.connectEndDate, secureConnectionStart: metrics.secureConnectionStartDate,
            secureConnectionEnd: metrics.secureConnectionEndDate, requestStart: metrics.requestStartDate,
            requestEnd: metrics.requestEndDate, responseStart: metrics.responseStartDate,
            responseEnd: metrics.responseEndDate)
    }

    /// The mapping behind ``init(_:)``, on plain dates so that it can be tested.
    init?(
        fetchStart: Date?, domainLookupStart: Date?, domainLookupEnd: Date?, connectStart: Date?, connectEnd: Date?,
        secureConnectionStart: Date?, secureConnectionEnd: Date?, requestStart: Date?, requestEnd: Date?,
        responseStart: Date?, responseEnd: Date?
    ) {
        guard let requestStart, let requestEnd, let responseStart, let responseEnd else { return nil }
        /// Milliseconds between two dates, rounded to the microsecond.
        func duration(_ start: Date, _ end: Date) -> Double {
            (end.timeIntervalSince(start) * 1_000_000).rounded() / 1000
        }
        func duration(_ start: Date?, _ end: Date?) -> Double? {
            guard let start, let end else { return nil }
            return duration(start, end)
        }
        let firstPhaseStart = domainLookupStart ?? connectStart ?? requestStart
        try? self.init(
            blocked: duration(fetchStart, firstPhaseStart),
            dns: duration(domainLookupStart, domainLookupEnd) ?? -1,
            connect: duration(connectStart, connectEnd) ?? -1,
            send: duration(requestStart, requestEnd),
            wait: duration(requestEnd, responseStart),
            receive: duration(responseStart, responseEnd),
            ssl: duration(secureConnectionStart, secureConnectionEnd) ?? -1
        )
    }
}

private func sortedHeaders(_ fields: [String: String]) -> [HAR.Header] {
    fields.map { HAR.Header(name: $0.key, value: $0.value) }
        .sorted { ($0.name.lowercased(), $0.name) < ($1.name.lowercased(), $1.name) }
}
