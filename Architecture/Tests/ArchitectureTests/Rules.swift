import LLMCheck

extension Rule {
    static let libraryPerformsNoIO = Rule(
        id: "library-performs-no-io",
        title: "The library performs no I/O, reads no clock, makes no UUID and touches no singleton.",
        category: .purity,
        rationale: """
            swift-har represents and serializes traffic; it never captures or sends it (CODING_STANDARDS.md, "Pure \
            library", "Scoped to export"). CONSTRAINTS.md forbids invented data: the start time, the timings and the \
            bodies come from the caller, so `Date()`, `UUID()`, a `URLSession`, a file read or a `.shared` singleton \
            would make up a value the caller never gave, and `print` writes to a host's standard output.
            """,
        howToFix: """
            Take the value as a parameter, as `HAR.Entry(startedDateTime:…)` and `HAR.Timings(send:wait:receive:)` \
            do. Report a problem as a thrown error (`HAR.TimingsError`), never by printing.
            """,
        badExample: """
            let entry = HAR.Entry(startedDateTime: Date(), request: request, response: response, timings: timings)
            """,
        goodExample: """
            public init(startedDateTime: Date, request: Request, response: Response, timings: Timings, …)
            """
    )

    static let libraryDoesNotTrap = Rule(
        id: "library-does-not-trap",
        title: "Library code has no `fatalError`, `precondition`, `try!`, `as!` or force unwrap.",
        category: .purity,
        rationale: """
            HAR files come from browsers, proxies and other writers, and decoding is lenient by design \
            (CODING_STANDARDS.md, "Lenient decoding, strict construction"). A trap on unexpected input crashes the \
            host app that is only trying to export or read its traffic. Failures are typed values instead \
            (CODING_STANDARDS.md, "Failures are typed values"), and CONSTRAINTS.md bans `fatalError(\"TODO\")` stubs.
            """,
        howToFix: """
            Throw a dedicated error (`throws(HAR.TimingsError)`), return `nil` for genuine absence, or use the \
            HAR 1.2 "not available" value (`-1`, an omitted field).
            """,
        badExample: """
            let url = URL(string: request.url)!
            """,
        goodExample: """
            guard let url = request.url else { throw .missingURL }
            """
    )

    static let foundationFallsBackFromEssentials = Rule(
        id: "foundation-falls-back-from-essentials",
        title: "In HARKit, `import Foundation` appears only as the `#else` of `#if canImport(FoundationEssentials)`.",
        category: .platforms,
        rationale: """
            On Linux, FoundationEssentials is the small, Codable-only part of swift-foundation; full Foundation pulls \
            in ICU and everything else. HARKit needs only the essentials, so it imports them where they exist and \
            falls back to Foundation elsewhere (CONSTRAINTS.md, "HARKit dependency budget"; ADR 0003). This rule is \
            the syntax-aware form of `scripts/check-foundation-imports.sh`.
            """,
        howToFix: "Wrap the import in the same guard as `Sources/HARKit/Archive.swift`.",
        badExample: "import Foundation",
        goodExample: """
            #if canImport(FoundationEssentials)
            import FoundationEssentials
            #else
            import Foundation
            #endif
            """
    )

    static let importsStayWithinBudget = Rule(
        id: "imports-stay-within-budget",
        title: """
            HARKit imports only FoundationEssentials or Foundation; HARKitURLSession imports FoundationNetworking \
            only under `#if canImport(FoundationNetworking)`.
            """,
        category: .platforms,
        rationale: """
            HARKit has no package dependencies and never links FoundationNetworking (CONSTRAINTS.md, "HARKit \
            dependency budget"), so a client that only writes HAR files does not pay for URLSession. Everything that \
            needs `URLRequest`, `HTTPURLResponse` or `URLSession` lives in HARKitURLSession (ADR 0003), where \
            FoundationNetworking exists only on Linux.
            """,
        howToFix: """
            Implement the feature with the standard library or FoundationEssentials. Code that needs URLSession's \
            types belongs in `Sources/HARKitURLSession`. A new dependency is a decision for the maintainer, recorded \
            in `Package.swift` and CONSTRAINTS.md first.
            """,
        badExample: """
            // Sources/HARKit/Request.swift
            import FoundationNetworking
            """,
        goodExample: """
            // Sources/HARKitURLSession/HARKitURLSession.swift
            #if canImport(FoundationNetworking)
            import FoundationNetworking
            #endif
            """
    )

    static let publicModelsAreValues = Rule(
        id: "public-models-are-values",
        title: """
            A public struct is declared `Codable`, `Hashable` and `Sendable`; a public enum `Hashable` and `Sendable`.
            """,
        category: .models,
        rationale: """
            Every HAR object is one `Codable, Hashable, Sendable` value type (CODING_STANDARDS.md, "Sendable value \
            types", "Matches its surroundings"): `Codable` so callers can use their own encoder, `Sendable` so a log \
            can cross tasks under Swift 6, and `Hashable` so tests compare whole values. A missing conformance is a \
            source break to add later, since a client cannot add it.
            """,
        howToFix: """
            Declare the conformances on the type itself, like its neighbours: \
            `public struct Header: Codable, Hashable, Sendable`.
            """,
        badExample: "public struct Header: Codable {",
        goodExample: "public struct Header: Codable, Hashable, Sendable {"
    )

    static let uncheckedSendableExplainsItself = Rule(
        id: "unchecked-sendable-explains-itself",
        title: "An `@unchecked Sendable` conformance has a comment that proves it safe.",
        category: .models,
        rationale: """
            `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only \
            proof left that the type is safe to share (CODING_STANDARDS.md, "Sendable value types").
            """,
        howToFix: """
            Prefer a value type. If it cannot be one, put a comment on the declaration that says what guards the \
            mutable state.
            """,
        badExample: "final class Cache: @unchecked Sendable {",
        goodExample: """
            // Every access to `storage` holds `lock`.
            final class Cache: @unchecked Sendable {
            """
    )

    static let testsUseSwiftTesting = Rule(
        id: "tests-use-swift-testing",
        title: "Tests use Swift Testing, never XCTest.",
        category: .testing,
        rationale: """
            The suite is Swift Testing only (CODING_STANDARDS.md, "Swift Testing only"): `@Test`, `#expect` and \
            `#require` give one failure message style, parameterised tests and parallel, randomly ordered runs.
            """,
        howToFix: "Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`.",
        badExample: """
            import XCTest
            final class CookieTests: XCTestCase { func testParsing() { XCTAssertEqual(…) } }
            """,
        goodExample: """
            import Testing
            @Suite struct CookieTests { @Test func parsing() { #expect(…) } }
            """
    )

    static let knownIssuesExplainThemselves = Rule(
        id: "known-issues-explain-themselves",
        title: "`withKnownIssue` names the issue that tracks it.",
        category: .testing,
        rationale: """
            A known issue hides a failing expectation. CONSTRAINTS.md ("Floor") allows `withKnownIssue` only with a \
            linked issue: without one, nobody can tell a bug waiting for a fix from a test nobody understood.
            """,
        howToFix: "Pass the reason as the first argument, with the GitHub issue that tracks it.",
        badExample: "withKnownIssue { try HAR.Archive(json: data) }",
        goodExample: """
            withKnownIssue("Charles writes `time` as a string (mackoj/swift-har#12)") {
                try HAR.Archive(json: data)
            }
            """
    )

    static let testsAreNotDisabled = Rule(
        id: "tests-are-not-disabled",
        title: "No test or suite is `.disabled`.",
        category: .testing,
        rationale: """
            A disabled test still reads as coverage while checking nothing (CONSTRAINTS.md, "Floor"). A failing \
            behaviour is either fixed, or asserted as a known issue that names its tracking issue.
            """,
        howToFix: "Fix the code or the test. If the bug must wait, wrap the failing part in `withKnownIssue(\"…#N\")`.",
        badExample: "@Test(.disabled(\"flaky\")) func decodesChromeExport() throws {",
        goodExample: "@Test func decodesChromeExport() throws {"
    )

    static let tryLeadsExpectations = Rule(
        id: "try-leads-expectations",
        title: "In `#expect` and `#require`, `try` comes first or not at all.",
        category: .testing,
        rationale: """
            CI builds the tests on Swift 6.0 (CONSTRAINTS.md), whose `#expect` and `#require` expand the expression \
            into a non-throwing autoclosure unless it starts with `try`. A `try` nested inside it, such as \
            `#expect(entries == [try makeEntry()])`, compiles on Swift 6.1 and later and fails on 6.0 with "call can \
            throw, but it is executed in a non-throwing autoclosure".
            """,
        howToFix: "Compute the throwing value in a `let` before the expectation, or start the expression with `try`.",
        badExample: """
            #expect(archive.log.entries == [try makeEntry()])
            """,
        goodExample: """
            let entry = try makeEntry()
            #expect(archive.log.entries == [entry])
            """
    )
}

/// Every rule, in the order `docs/architecture-rules.md` lists them.
let allRules: [Rule] = [
    .libraryPerformsNoIO, .libraryDoesNotTrap, .foundationFallsBackFromEssentials, .importsStayWithinBudget,
    .publicModelsAreValues, .uncheckedSendableExplainsItself, .testsUseSwiftTesting, .knownIssuesExplainThemselves,
    .testsAreNotDisabled, .tryLeadsExpectations,
]
