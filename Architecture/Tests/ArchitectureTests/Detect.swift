import LLMCheck
import SwiftSyntax

/// The detectors, separate from the codebase so `DetectorTests` can run them on snippets.
enum Detect {
    /// Types whose every use is I/O or shared global state.
    static let impureTypes: Set<String> = [
        "FileManager", "FileHandle", "URLSession", "ProcessInfo", "NotificationCenter", "UserDefaults", "Bundle",
        "DispatchQueue",
    ]

    /// Uses of I/O, a clock, randomness or a singleton: `FileManager.default`, `Date()`, `Date.now`, `UUID()`,
    /// `print(x)`. `Date(timeIntervalSince1970:)` and `UUID(uuidString:)` are pure and pass.
    static func impureCode(in scope: Scope) -> [Match<Syntax>] {
        let calls = scope.calls(named: "Date", "UUID", "print").filter { call in
            call.node.calledExpression.is(DeclReferenceExprSyntax.self)
                && (call.node.calledName == "print" || call.node.arguments.isEmpty)
        }
        let now = scope.containing("Date.now").nodes(of: MemberAccessExprSyntax.self) {
            $0.node.declName.baseName.text == "now" && $0.node.base?.trimmedDescription == "Date"
        }
        return scope.references(to: impureTypes) + calls.map(\.erased) + now.map(\.erased)
    }

    /// Functions that stop the process.
    static let trappingFunctions: Set<String> = ["fatalError", "precondition", "preconditionFailure"]

    /// `fatalError(…)`, `precondition(…)`, `try!`, `as!` and force unwraps (`value!`).
    static func traps(in scope: Scope) -> [Match<Syntax>] {
        let calls = scope.calls(named: trappingFunctions).filter { $0.node.receiver == nil }
        return calls.map(\.erased) + scope.forcedTries.map(\.erased) + scope.forcedCasts
            + scope.forceUnwraps.map(\.erased)
    }

    /// `import Foundation` anywhere but the `#else` of `#if canImport(FoundationEssentials)`.
    static func unguardedFoundationImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
        scope.imports(of: "Foundation").filter { match in
            guard let clause = match.node.enclosingIfConfigClauses.first else { return true }
            return !(clause.isElse && clause.ifCondition == "canImport(FoundationEssentials)")
        }
    }

    /// What `HARKit` may import: it has no package dependencies.
    static let harKitModules: Set<String> = ["FoundationEssentials", "Foundation"]

    /// What `HARKitURLSession` may import.
    static let harKitURLSessionModules: Set<String> = ["HARKit", "Foundation", "FoundationNetworking"]

    /// Imports in `HARKit` outside its budget, imports in `HARKitURLSession` outside its budget, and
    /// `import FoundationNetworking` in `HARKitURLSession` outside `#if canImport(FoundationNetworking)`.
    static func importsOverBudget(harKit: Scope, harKitURLSession: Scope) -> [Match<ImportDeclSyntax>] {
        let kit = harKit.imports.filter { !harKitModules.contains($0.node.moduleName) }
        let adapters = harKitURLSession.imports.filter { match in
            guard harKitURLSessionModules.contains(match.node.moduleName) else { return true }
            guard match.node.moduleName == "FoundationNetworking" else { return false }
            return !match.node.enclosingIfConfigClauses.contains {
                !$0.isElse && $0.condition?.trimmedDescription == "canImport(FoundationNetworking)"
            }
        }
        return kit + adapters
    }

    /// Public structs that are not declared `Codable`, `Hashable` and `Sendable`, and public enums with cases that
    /// are not declared `Hashable` and `Sendable`. A caseless enum is a namespace (`HAR`) and passes.
    static func publicTypesMissingConformances(in scope: Scope) -> [Declaration] {
        let structs = scope.structs.withModifier("public").filter {
            !($0.inherits(from: "Codable") && $0.inherits(from: "Hashable") && $0.inherits(from: "Sendable"))
        }
        let enums = scope.enums.withModifier("public").filter {
            !$0.cases.isEmpty && !($0.inherits(from: "Hashable") && $0.inherits(from: "Sendable"))
        }
        return structs + enums
    }

    /// `try` inside an `#expect` or `#require` argument that does not itself start with `try`. A `try` inside a
    /// closure argument is in a throwing closure, so it is not one.
    static func nestedTryInExpectations(in scope: Scope) -> [Match<TryExprSyntax>] {
        scope.containing("#expect", "#require").nodes(of: MacroExpansionExprSyntax.self) {
            ["expect", "require"].contains($0.node.macroName.text)
        }
        .flatMap { macro in
            macro.node.arguments.filter { !startsWithTry($0.expression) }
                .flatMap { TryFinder.tries(in: $0.expression) }
                .map { Match(node: $0, file: macro.file) }
        }
    }

    /// `try a == b` is not folded by the parser: it is a sequence whose first element is the `try`, which covers
    /// the whole expression.
    private static func startsWithTry(_ expression: ExprSyntax) -> Bool {
        if expression.is(TryExprSyntax.self) { return true }
        return expression.as(SequenceExprSyntax.self)?.elements.first?.is(TryExprSyntax.self) == true
    }

}

/// The `try` expressions under a node, outside closures.
private final class TryFinder: SyntaxVisitor {
    var found: [TryExprSyntax] = []

    static func tries(in node: some SyntaxProtocol) -> [TryExprSyntax] {
        let finder = TryFinder(viewMode: .sourceAccurate)
        finder.walk(node)
        return finder.found
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .skipChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}
