# Changelog

All notable changes to this package. Versions follow [Semantic Versioning](https://semver.org); before 1.0, a minor version may contain breaking changes, listed under **Breaking**.

## 0.1.0 — 2026-10-30

First release.

### Added

- `HARKit`: one `Codable`, `Hashable`, `Sendable` type per HAR 1.2 object (`HAR.Archive`, `Log`, `Creator`, `Page`, `PageTimings`, `Entry`, `Request`, `Response`, `Header`, `QueryParameter`, `Cookie`, `PostData`, `PostParameter`, `Content`, `Cache`, `CacheEntry`, `Timings`).
- Builders from plain values: `HAR.Request(method:url:httpVersion:headers:body:)`, `HAR.Response(status:statusText:httpVersion:headers:body:)`, `HAR.Content(body:mimeType:)` and `HAR.PostData(body:mimeType:)`. They derive the query string, cookies (with RFC 6265 `Set-Cookie` parsing), post data, content text or base64, redirect URL and sizes.
- `HAR.Timings` validates HAR 1.2's rules and throws `HAR.TimingsError`; `HAR.Entry.time` is computed from the timings.
- JSON: `HAR.Archive.jsonData(prettyPrinted:)` and lenient `HAR.Archive(json:)`, which ignores a byte order mark.
- `HARKitURLSession`: `HAR.Request(_:httpVersion:)` from `URLRequest`, `HAR.Response(_:body:httpVersion:)` from `HTTPURLResponse`, and `HAR.Timings(_:)` from `URLSessionTaskTransactionMetrics`.
