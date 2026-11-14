import Benchmark
import Foundation
import HARKit

/// A typical JSON API exchange: query string, cookies, a JSON body each way, and the headers a browser or an
/// HTTP client sends.
enum Traffic {
    static let start = Date(timeIntervalSince1970: 1_239_883_643.596)

    static let requestHeaders = [
        HAR.Header(name: "Host", value: "api.example.com"),
        HAR.Header(name: "User-Agent", value: "MyApp/1.0 (iPhone; iOS 18.0) CFNetwork/1568 Darwin/24.0.0"),
        HAR.Header(name: "Accept", value: "application/json"),
        HAR.Header(name: "Accept-Language", value: "en-GB,en;q=0.9"),
        HAR.Header(name: "Accept-Encoding", value: "gzip, deflate, br"),
        HAR.Header(name: "Authorization", value: "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl"),
        HAR.Header(name: "Content-Type", value: "application/json; charset=utf-8"),
        HAR.Header(name: "Cookie", value: "session=abc123; theme=dark; consent=yes; ab_test=variant%20b"),
    ]

    static let responseHeaders = [
        HAR.Header(name: "Date", value: "Thu, 16 Apr 2009 12:07:23 GMT"),
        HAR.Header(name: "Content-Type", value: "application/json; charset=utf-8"),
        HAR.Header(name: "Cache-Control", value: "private, max-age=0"),
        HAR.Header(name: "ETag", value: #"W/"5e8-1a2b3c""#),
        HAR.Header(
            name: "Set-Cookie", value: "session=def456; Path=/; Expires=Wed, 21 Oct 2015 07:28:00 GMT; HttpOnly"),
        HAR.Header(name: "Set-Cookie", value: "theme=dark; Path=/; Domain=example.com; Secure"),
        HAR.Header(name: "X-Request-ID", value: "7f3c2a1e-9b4d-4c8e-a6f0-2d1b3e4f5a6b"),
    ]

    static let url = URL(string: "https://api.example.com/v1/pets?limit=20&offset=40&sort=name&filter=dog%20cat#list")!

    static let requestBody = Data(#"{"name":"Rex","species":"dog","tags":["good","boy"],"age":4}"#.utf8)

    static let responseBody = Data(
        ("["
            + (0..<20).map { #"{"id":\#($0),"name":"Pet \#($0)","species":"dog","status":"available"}"# }
            .joined(separator: ",") + "]").utf8)

    static let binaryBody = Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    static let timings = try! HAR.Timings(
        blocked: 0.4, dns: 12.1, connect: 30.2, send: 0.3, wait: 85.4, receive: 3.1, ssl: 20.5)

    static func entry(_ index: Int) -> HAR.Entry {
        HAR.Entry(
            startedDateTime: start.addingTimeInterval(Double(index) * 0.137),
            request: HAR.Request(
                method: "POST", url: url, httpVersion: "HTTP/1.1", headers: requestHeaders, body: requestBody),
            response: HAR.Response(
                status: 200, statusText: "OK", httpVersion: "HTTP/1.1", headers: responseHeaders,
                body: responseBody),
            timings: timings, serverIPAddress: "93.184.216.34", connection: "\(52_000 + index % 100)")
    }

    /// A log as a long capture session produces it.
    static func log(entries count: Int) -> HAR.Log {
        HAR.Log(
            creator: HAR.Creator(name: "Benchmarks", version: "1.0"),
            pages: [HAR.Page(startedDateTime: start, id: "page_1", title: "Pets")],
            entries: (0..<count).map(entry))
    }
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident, .retainCount],
        // Exact counts and microseconds, so a change of a few percent shows up in a comparison.
        timeUnits: .microseconds,
        units: [.mallocCountTotal: .count, .retainCount: .count],
        maxDuration: .seconds(2),
        maxIterations: 1_000
    )

    // MARK: Building entries

    Benchmark("Build request, JSON body", configuration: .init(timeUnits: .nanoseconds, scalingFactor: .kilo)) {
        benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                HAR.Request(
                    method: "POST", url: Traffic.url, httpVersion: "HTTP/1.1", headers: Traffic.requestHeaders,
                    body: Traffic.requestBody))
        }
    }

    Benchmark("Build response, JSON body", configuration: .init(timeUnits: .nanoseconds, scalingFactor: .kilo)) {
        benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                HAR.Response(
                    status: 200, statusText: "OK", httpVersion: "HTTP/1.1", headers: Traffic.responseHeaders,
                    body: Traffic.responseBody))
        }
    }

    Benchmark("Build response, binary body", configuration: .init(timeUnits: .nanoseconds, scalingFactor: .kilo)) {
        benchmark in
        let headers = [HAR.Header(name: "Content-Type", value: "image/png")]
        for _ in benchmark.scaledIterations {
            blackHole(
                HAR.Response(
                    status: 200, statusText: "OK", httpVersion: "HTTP/2", headers: headers, body: Traffic.binaryBody))
        }
    }

    Benchmark("Build entry", configuration: .init(timeUnits: .nanoseconds, scalingFactor: .kilo)) { benchmark in
        for index in benchmark.scaledIterations { blackHole(Traffic.entry(index)) }
    }

    Benchmark("Build log, 1000 entries") { benchmark in
        blackHole(Traffic.log(entries: 1_000))
    }

    // MARK: Encoding and decoding

    let log = Traffic.log(entries: 1_000)
    let archive = HAR.Archive(log: log)
    let json = try! archive.jsonData()

    Benchmark("Encode log, 1000 entries") { benchmark in
        blackHole(try archive.jsonData())
    }

    Benchmark("Encode log, 1000 entries, pretty") { benchmark in
        blackHole(try archive.jsonData(prettyPrinted: true))
    }

    Benchmark("Decode log, 1000 entries") { benchmark in
        blackHole(try HAR.Archive(json: json))
    }
}
