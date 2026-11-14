import LLMCheck

/// The swift-har repository, rooted where `.llm-check.yaml` is. Its file list and every parsed file are shared by
/// all suites, which Swift Testing runs in parallel.
func har() throws -> Codebase { try Codebase() }

extension RuleCategory {
    static let purity = RuleCategory(
        "purity",
        description: """
            The library is pure and never traps. Read before you reach for the file system, a clock, a UUID, or \
            `fatalError`.
            """
    )
    static let platforms = RuleCategory(
        "platforms",
        description: "Imports and the dependency budget of each product. Read before you add an `import` to `Sources`."
    )
    static let models = RuleCategory(
        "models",
        description: "Public types and concurrency. Read before you add or change a public type."
    )
    static let testing = RuleCategory(
        "testing",
        description: "Swift Testing, and no silenced tests. Read before you add, skip or mark a test."
    )
}
