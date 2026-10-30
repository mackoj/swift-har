# swift-har

[![CI](https://github.com/mackoj/swift-har/actions/workflows/ci.yml/badge.svg)](https://github.com/mackoj/swift-har/actions/workflows/ci.yml)

Export HTTP traffic as [HTTP Archive (HAR) 1.2](http://www.softwareishard.com/blog/har-12-spec/) JSON from Swift: build a HAR entry from a request and its response, collect entries in a log, and write the file that browsers' developer tools, Charles, Proxyman and HAR viewers open.

- **Export only.** The package represents and serializes traffic. It makes no network requests, does not capture traffic for you and works with any HTTP client.
- **Honest about missing data.** It never reads the clock, invents timings or guesses a body. Unknown sizes are `-1` and unknown optional fields are omitted, as HAR 1.2 prescribes. Values only you know (start time, timings, a response) are required inputs.
- **Small API.** One `Codable`, `Hashable`, `Sendable` value type per HAR object, plus builders that derive the redundant fields (query string, cookies, post data, content encoding, redirect URL).
- **FoundationEssentials.** `HARKit` has no dependencies and imports `FoundationEssentials` where it exists, so on Linux it does not link full Foundation or FoundationNetworking. The URLSession adapters live in a separate product.
- **Swift 6**, strict concurrency, Linux and Apple platforms.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mackoj/swift-har.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "HARKit", package: "swift-har"),
    ]),
]
```

Requires Swift 6.0+. Platforms: Linux, macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, visionOS 1+.

| Product            | Depends on                                         | Purpose                                                    |
|--------------------|----------------------------------------------------|------------------------------------------------------------|
| `HARKit`           | FoundationEssentials (Foundation where it is missing) | HAR 1.2 models, builders from plain values, JSON           |
| `HARKitURLSession` | `HARKit`, Foundation, FoundationNetworking on Linux | Builders from `URLRequest`, `HTTPURLResponse` and metrics  |

## Usage

### Building an entry

```swift
import HARKit

let requestStart = Date() // when you sent the request

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

let entry = HAR.Entry(startedDateTime: requestStart, request: request, response: response, timings: timings)
```

From what you pass in, the builders derive:

| Field                         | Derived from                                                                                     |
|-------------------------------|--------------------------------------------------------------------------------------------------|
| `request.url`                 | the URL without its fragment (`https://api.example.com/pets?limit=10`)                           |
| `request.queryString`         | the URL query, split on `&` and percent-decoded                                                  |
| `request.cookies`             | `Cookie` headers                                                                                 |
| `request.postData`            | the body as `text`, or `params` for `application/x-www-form-urlencoded`, when it is UTF-8 text  |
| `request.bodySize`            | the body's byte count (0 without a body)                                                         |
| `response.content`            | the body and `Content-Type`: plain `text` for UTF-8 text, base64 with `encoding` otherwise      |
| `response.cookies`            | `Set-Cookie` headers (RFC 6265 parsing, `Expires` converted to ISO 8601)                         |
| `response.redirectURL`        | the `Location` header                                                                            |
| `response.bodySize`           | the body's byte count, or `-1` when a `Content-Encoding` means the transferred size is unknown  |
| `headersSize`                 | always `-1`: the bytes on the wire depend on the HTTP version and on headers the client adds     |
| `entry.time`                  | the sum of the timings, as HAR 1.2 requires                                                      |

Every model also has a memberwise initializer, and every field is a `var`, so you can set anything the builders cannot know, such as `headersSize`, `content.compression`, `serverIPAddress` or `pageref`.

### Writing the file

```swift
let log = HAR.Log(creator: HAR.Creator(name: "MyApp", version: "1.0"), entries: [entry])
let data = try HAR.Archive(log: log).jsonData(prettyPrinted: true)
// Write `data` to a file named with a `.har` extension.
```

`jsonData` writes UTF-8 with sorted keys, so the same archive always gives the same bytes. The models are plain `Codable` types, so your own `JSONEncoder` works too.

### Reading a file

```swift
let archive = try HAR.Archive(json: data)
for entry in archive.log.entries {
    print(entry.request.method, entry.request.url, entry.response.status, entry.time)
}
```

Decoding is lenient, so files from browsers and proxies load. A byte order mark, custom `_fields` and unknown fields are ignored. Values HAR 1.2 forbids but other writers produce, such as `-1` in `timings.send`, are kept.

## When data is missing

HAR 1.2 has a "not available" value for some fields and none for others. The package never fills the gap for you.

- **No timings.** `send`, `wait` and `receive` are required and must be non-negative, and `entry.time` must equal the sum of the timings. Because there is no "not measured" value for them, `HAR.Timings` has no default ([ADR 0002](docs/adr/0002-callers-supply-timings.md)). Pass what you measured, and leave out `blocked`, `dns`, `connect` and `ssl` (or use `-1` when a phase does not apply, like `connect` on a reused connection). If you measured nothing, it is your call what to write. Zeros with a comment are valid and honest:

  ```swift
  let unmeasured = try HAR.Timings(send: 0, wait: 0, receive: 0, comment: "Timings were not measured")
  ```

- **No response** (the request failed, was cancelled or is still running). HAR 1.2 requires a response, so `HAR.Entry` requires one too ([ADR 0001](docs/adr/0001-entries-require-a-response.md)). Leave the request out, or write the placeholder browsers use, stating it yourself:

  ```swift
  let failed = HAR.Response(
      status: 0, statusText: "", httpVersion: "",
      content: HAR.Content(size: 0, mimeType: ""),
      comment: "The request timed out"
  )
  ```

- **Body not captured.** `HAR.Response(…, body:)` takes the body you have, and an empty `Data` means the body was empty. If you did not capture it, build `HAR.Content` yourself with the memberwise initializer and no `text`.
- **Unknown sizes.** `headersSize` and `bodySize` are `-1` when not known; `content.compression` is omitted.
- **Unknown HTTP version or reason phrase.** Pass an empty string. HTTP/2 and later have no reason phrase.

## Specification notes

Where HAR 1.2 leaves a choice open, or where this package departs from the letter of the text, the behaviour is:

- **`entry.time` is computed.** It is always the sum of the timings, excluding `-1` values and `ssl` (which `connect` already includes). A `time` read from a file is ignored.
- **`ssl` must fit in `connect`.** `HAR.Timings` rejects a measured `ssl` larger than `connect`, or one without `connect`. Negative or non-finite `send`, `wait` and `receive`, and optional phases other than `-1` or non-negative, are rejected as well (`HAR.TimingsError`).
- **Binary request bodies are left out.** HAR 1.2 `postData` has no `encoding` (that is a 1.3 proposal), so a body that is not UTF-8 text gets no `postData`. `bodySize` still counts it ([ADR 0004](docs/adr/0004-request-bodies-without-text.md)). This includes `multipart/form-data`. Response bodies are never lost: binary content is base64-encoded with `encoding: "base64"`.
- **What counts as text.** A body is written as `text` when its media type is `text/*`, `*/*+json`, `*/*+xml`, JSON, XML, JavaScript, GraphQL, NDJSON, YAML, SQL or a URL-encoded form, it declares no charset other than UTF-8 or ASCII, and the bytes are valid UTF-8. The body is not transcoded from other charsets.
- **`text` or `params`, never both.** URL-encoded form bodies become `params` (with `+` as space), as HAR 1.2 makes the two fields mutually exclusive. When decoding a file that has both, `text` wins.
- **Query strings.** Values are percent-decoded, `+` is kept as is (only form bodies use it for a space), a parameter without `=` has an empty value, and a malformed escape is kept as written.
- **Cookies.** A `Cookie` pair without `=` becomes a cookie with an empty name, as browsers treat it. Set-Cookie values joined with commas are split again. `Max-Age`, `SameSite` and other attributes are ignored, and `Domain` and `Path` are kept as sent. Request cookies have only a name and a value.
- **Dates.** They are written in UTC with millisecond precision (`2009-04-16T12:07:23.596Z`). When reading, any offset is accepted, but the offset itself is not kept. Cache entry dates stay strings, because HAR 1.2 does not specify their format.
- **`mimeType` with no `Content-Type`** is an empty string, not a guessed type.
- **Entries are sorted** by `startedDateTime` when a `HAR.Log` is created (ties keep their order), as HAR 1.2 prefers.
- **Custom fields** (`_name`) are neither written nor kept when decoding.
- **Cache.** `HAR.Cache()` is `{}`, meaning no information. `.noEntry` writes `null`.
- **Privacy.** A HAR file contains whatever you put in it, cookies and `Authorization` headers included. Redact headers and bodies before building entries from sensitive traffic.

## Sources

- The HAR 1.2 specification by Jan Odvarko, read through its GitHub mirror [ahmadnassri/har-spec](https://github.com/ahmadnassri/har-spec/blob/master/versions/1.2.md).
- The [ahmadnassri/har-schema](https://github.com/ahmadnassri/har-schema) JSON schemas (ISC), used as a reference for which fields validators require. Nothing from it is copied.
- Edge cases (form bodies, multipart, binary post data, sorted export) were inspired by the tests of [google/martian](https://github.com/google/martian/tree/master/har) (Apache 2.0). The tests here were written independently from the specification.

## License

MIT, see [LICENSE](LICENSE).
