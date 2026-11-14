import LLMCheck
import Testing

/// Each detector on snippets: it finds what its rule forbids and nothing its rule allows.
@Suite struct DetectorTests {
    func scope(_ source: String, at path: String = "Sources/HARKit/File.swift") -> Scope {
        Scope(files: [SourceFile(path: path, source: source)])
    }

    @Test func impureCodeIsFound() {
        let found = Detect.impureCode(
            in: scope(
                """
                let files = FileManager.default
                let now = Date()
                let later = Date.now
                let id = UUID()
                print("encoded")
                func send(_ session: URLSession) {}
                """))
        #expect(found.map(\.location.line).sorted() == [1, 2, 3, 4, 5, 6])
    }

    @Test func pureCodePasses() {
        let found = Detect.impureCode(
            in: scope(
                """
                // FileManager and URLSession are fine in a comment.
                let message = "Date() and print() are fine in a string"
                let epoch = Date(timeIntervalSince1970: 0)
                let metrics: URLSessionTaskTransactionMetrics? = nil
                reporter.print(issue)
                """))
        #expect(found.isEmpty)
    }

    @Test func trapsAreFound() {
        let found = Detect.traps(
            in: scope(
                """
                fatalError("TODO")
                precondition(size >= 0)
                let data = try! encoder.encode(log)
                let response = task.response as! HTTPURLResponse
                let url = URL(string: text)!
                """))
        #expect(found.map(\.location.line).sorted() == [1, 2, 3, 4, 5])
    }

    @Test func safeCodePasses() {
        let found = Detect.traps(
            in: scope(
                """
                // fatalError() and try! are fine in a comment.
                let message = "x! as! y"
                let data = try? encoder.encode(log)
                let response = task.response as? HTTPURLResponse
                if !body.isEmpty, size != -1 { reporter.fatalError() }
                """))
        #expect(found.isEmpty)
    }

    @Test func unguardedFoundationIsFound() {
        let found = Detect.unguardedFoundationImports(
            in: scope(
                """
                import Foundation
                #if canImport(Darwin)
                import Foundation
                #endif
                #if canImport(FoundationEssentials)
                import Foundation
                #endif
                """))
        #expect(found.map(\.location.line) == [1, 3, 6])
    }

    @Test func guardedFoundationPasses() {
        let found = Detect.unguardedFoundationImports(
            in: scope(
                """
                #if canImport(FoundationEssentials)
                import FoundationEssentials
                #else
                import Foundation
                #endif
                """))
        #expect(found.isEmpty)
    }

    @Test func importsOverBudgetAreFound() {
        let found = Detect.importsOverBudget(
            harKit: scope("import FoundationNetworking\nimport Collections"),
            harKitURLSession: scope(
                "import HARKit\nimport FoundationNetworking\nimport NIOHTTP1",
                at: "Sources/HARKitURLSession/HARKitURLSession.swift"))
        #expect(
            found.map(\.node.moduleName) == ["FoundationNetworking", "Collections", "FoundationNetworking", "NIOHTTP1"])
    }

    @Test func importsWithinBudgetPass() {
        let found = Detect.importsOverBudget(
            harKit: scope(
                """
                #if canImport(FoundationEssentials)
                import FoundationEssentials
                #else
                import Foundation
                #endif
                """),
            harKitURLSession: scope(
                """
                @_exported import HARKit
                import Foundation

                #if canImport(FoundationNetworking)
                import FoundationNetworking
                #endif
                """, at: "Sources/HARKitURLSession/HARKitURLSession.swift"))
        #expect(found.isEmpty)
    }

    @Test func missingConformancesAreFound() {
        let found = Detect.publicTypesMissingConformances(
            in: scope(
                """
                public enum HAR {
                    public struct Header: Hashable, Sendable {}
                    public struct Cookie: Codable, Hashable, Sendable {
                        public enum SameSite: Codable { case lax }
                    }
                    public enum TimingsError: Error, Hashable, Sendable { case invalid }
                    struct MediaType {}
                }
                """))
        #expect(found.map(\.qualifiedName) == ["HAR.Header", "HAR.Cookie.SameSite"])
    }

    @Test func nestedTryInExpectationsIsFound() {
        let found = Detect.nestedTryInExpectations(
            in: scope(
                """
                #expect(entries == [try makeEntry()])
                #expect(try encodedJSON(a) == try encodedJSON(b))
                #require(try value())
                #expect(throws: DecodingError.self) { try HAR.Archive(json: data) }
                #expect(values.map { try? parse($0) } == [nil])
                #expect(Data(base64Encoded: try #require(content.text)) == body)
                """, at: "Tests/T/A.swift"))
        #expect(found.map(\.location.line) == [1, 6])
    }

}
