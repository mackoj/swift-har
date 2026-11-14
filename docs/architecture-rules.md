# Architecture rules

The mechanical part of `CODING_STANDARDS.md` and `CONSTRAINTS.md`, enforced by the `Architecture/` package with [swift-llm-check](https://github.com/mackoj/swift-llm-check): `swift test --package-path Architecture` (macOS). Generated from its rules; do not edit by hand.

## purity

The library is pure and never traps. Read before you reach for the file system, a clock, a UUID, or `fatalError`.

### The library performs no I/O, reads no clock, makes no UUID and touches no singleton.

`library-performs-no-io`: swift-har represents and serializes traffic; it never captures or sends it (CODING_STANDARDS.md, "Pure library", "Scoped to export"). CONSTRAINTS.md forbids invented data: the start time, the timings and the bodies come from the caller, so `Date()`, `UUID()`, a `URLSession`, a file read or a `.shared` singleton would make up a value the caller never gave, and `print` writes to a host's standard output.

**How to fix:** Take the value as a parameter, as `HAR.Entry(startedDateTime:…)` and `HAR.Timings(send:wait:receive:)` do. Report a problem as a thrown error (`HAR.TimingsError`), never by printing.

Bad:

```swift
let entry = HAR.Entry(startedDateTime: Date(), request: request, response: response, timings: timings)
```

Good:

```swift
public init(startedDateTime: Date, request: Request, response: Response, timings: Timings, …)
```

### Library code has no `fatalError`, `precondition`, `try!`, `as!` or force unwrap.

`library-does-not-trap`: HAR files come from browsers, proxies and other writers, and decoding is lenient by design (CODING_STANDARDS.md, "Lenient decoding, strict construction"). A trap on unexpected input crashes the host app that is only trying to export or read its traffic. Failures are typed values instead (CODING_STANDARDS.md, "Failures are typed values"), and CONSTRAINTS.md bans `fatalError("TODO")` stubs.

**How to fix:** Throw a dedicated error (`throws(HAR.TimingsError)`), return `nil` for genuine absence, or use the HAR 1.2 "not available" value (`-1`, an omitted field).

Bad:

```swift
let url = URL(string: request.url)!
```

Good:

```swift
guard let url = request.url else { throw .missingURL }
```

## platforms

Imports and the dependency budget of each product. Read before you add an `import` to `Sources`.

### In HARKit, `import Foundation` appears only as the `#else` of `#if canImport(FoundationEssentials)`.

`foundation-falls-back-from-essentials`: On Linux, FoundationEssentials is the small, Codable-only part of swift-foundation; full Foundation pulls in ICU and everything else. HARKit needs only the essentials, so it imports them where they exist and falls back to Foundation elsewhere (CONSTRAINTS.md, "HARKit dependency budget"; ADR 0003). This rule is the syntax-aware form of `scripts/check-foundation-imports.sh`.

**How to fix:** Wrap the import in the same guard as `Sources/HARKit/Archive.swift`.

Bad:

```swift
import Foundation
```

Good:

```swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
```

### HARKit imports only FoundationEssentials or Foundation; HARKitURLSession imports FoundationNetworking only under `#if canImport(FoundationNetworking)`.

`imports-stay-within-budget`: HARKit has no package dependencies and never links FoundationNetworking (CONSTRAINTS.md, "HARKit dependency budget"), so a client that only writes HAR files does not pay for URLSession. Everything that needs `URLRequest`, `HTTPURLResponse` or `URLSession` lives in HARKitURLSession (ADR 0003), where FoundationNetworking exists only on Linux.

**How to fix:** Implement the feature with the standard library or FoundationEssentials. Code that needs URLSession's types belongs in `Sources/HARKitURLSession`. A new dependency is a decision for the maintainer, recorded in `Package.swift` and CONSTRAINTS.md first.

Bad:

```swift
// Sources/HARKit/Request.swift
import FoundationNetworking
```

Good:

```swift
// Sources/HARKitURLSession/HARKitURLSession.swift
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
```

## models

Public types and concurrency. Read before you add or change a public type.

### A public struct is declared `Codable`, `Hashable` and `Sendable`; a public enum `Hashable` and `Sendable`.

`public-models-are-values`: Every HAR object is one `Codable, Hashable, Sendable` value type (CODING_STANDARDS.md, "Sendable value types", "Matches its surroundings"): `Codable` so callers can use their own encoder, `Sendable` so a log can cross tasks under Swift 6, and `Hashable` so tests compare whole values. A missing conformance is a source break to add later, since a client cannot add it.

**How to fix:** Declare the conformances on the type itself, like its neighbours: `public struct Header: Codable, Hashable, Sendable`.

Bad:

```swift
public struct Header: Codable {
```

Good:

```swift
public struct Header: Codable, Hashable, Sendable {
```

### An `@unchecked Sendable` conformance has a comment that proves it safe.

`unchecked-sendable-explains-itself`: `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only proof left that the type is safe to share (CODING_STANDARDS.md, "Sendable value types").

**How to fix:** Prefer a value type. If it cannot be one, put a comment on the declaration that says what guards the mutable state.

Bad:

```swift
final class Cache: @unchecked Sendable {
```

Good:

```swift
// Every access to `storage` holds `lock`.
final class Cache: @unchecked Sendable {
```

## testing

Swift Testing, and no silenced tests. Read before you add, skip or mark a test.

### Tests use Swift Testing, never XCTest.

`tests-use-swift-testing`: The suite is Swift Testing only (CODING_STANDARDS.md, "Swift Testing only"): `@Test`, `#expect` and `#require` give one failure message style, parameterised tests and parallel, randomly ordered runs.

**How to fix:** Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`.

Bad:

```swift
import XCTest
final class CookieTests: XCTestCase { func testParsing() { XCTAssertEqual(…) } }
```

Good:

```swift
import Testing
@Suite struct CookieTests { @Test func parsing() { #expect(…) } }
```

### `withKnownIssue` names the issue that tracks it.

`known-issues-explain-themselves`: A known issue hides a failing expectation. CONSTRAINTS.md ("Floor") allows `withKnownIssue` only with a linked issue: without one, nobody can tell a bug waiting for a fix from a test nobody understood.

**How to fix:** Pass the reason as the first argument, with the GitHub issue that tracks it.

Bad:

```swift
withKnownIssue { try HAR.Archive(json: data) }
```

Good:

```swift
withKnownIssue("Charles writes `time` as a string (mackoj/swift-har#12)") {
    try HAR.Archive(json: data)
}
```

### No test or suite is `.disabled`.

`tests-are-not-disabled`: A disabled test still reads as coverage while checking nothing (CONSTRAINTS.md, "Floor"). A failing behaviour is either fixed, or asserted as a known issue that names its tracking issue.

**How to fix:** Fix the code or the test. If the bug must wait, wrap the failing part in `withKnownIssue("…#N")`.

Bad:

```swift
@Test(.disabled("flaky")) func decodesChromeExport() throws {
```

Good:

```swift
@Test func decodesChromeExport() throws {
```

### In `#expect` and `#require`, `try` comes first or not at all.

`try-leads-expectations`: CI builds the tests on Swift 6.0 (CONSTRAINTS.md), whose `#expect` and `#require` expand the expression into a non-throwing autoclosure unless it starts with `try`. A `try` nested inside it, such as `#expect(entries == [try makeEntry()])`, compiles on Swift 6.1 and later and fails on 6.0 with "call can throw, but it is executed in a non-throwing autoclosure".

**How to fix:** Compute the throwing value in a `let` before the expectation, or start the expression with `try`.

Bad:

```swift
#expect(archive.log.entries == [try makeEntry()])
```

Good:

```swift
let entry = try makeEntry()
#expect(archive.log.entries == [entry])
```
