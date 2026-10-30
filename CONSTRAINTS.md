# Constraints

Last reviewed: 2026-10-30

## Floor

- No new checker suppressions, disabled or skipped tests (`.disabled`, `withKnownIssue` without a linked issue), `fatalError("TODO")`-style stubs, or secrets in source.
- No deleted tests or removed assertions without a reason in the commit message.
- No invented data: the library never reads the clock, generates identifiers, or fills in a timing, size, body or other value it was not given. Unknown values follow the HAR 1.2 rule for that field (`-1`, or the field omitted).
- Do not weaken this file to make a change pass.

## Enforced checks

Run these before handing back a code change; each must pass.

| Dimension | Rule | Checked by |
|-----------|------|------------|
| Diff integrity | 0 whitespace errors | `git diff --check main` |
| Compilation | 0 errors, debug and release | `swift build --build-tests` and `swift build -c release` |
| Behaviour | 0 failing tests, including README examples | `swift test` |
| Formatting | 0 changes from formatting, 0 lint findings, with swift-format 6.3 | `swift-format lint --strict --parallel --recursive Sources Tests Package.swift` |
| Public API | 0 breaking changes against the base branch, unless intended and called out in the pull request | `swift package diagnose-api-breaking-changes main` |
| Documentation | 0 DocC warnings for the `.spi.yml` targets | Soundness workflow's documentation check (CI) |
| Workflows and YAML | 0 findings | `actionlint`, `zizmor .github/workflows` and `yamllint --strict .` |
| HARKit dependency budget | `HARKit` has no package dependencies; `import Foundation` appears only as the `#else` of `#if canImport(FoundationEssentials)`, and `FoundationNetworking` is never imported. Only `HARKitURLSession` may use Foundation and FoundationNetworking. | `Package.swift` review and `scripts/check-foundation-imports.sh` |

Linux is the platform most likely to break (no Objective-C Foundation, older toolchains): CI runs Swift 6.0, 6.1 and 6.2 in Linux containers. When a change touches Foundation APIs or platform guards, say whether you checked it on Linux (for example `docker run --rm -v "$PWD":/src -w /src swift:6.0 swift test`) or leave it to CI. Darwin-only code (`#if canImport(Darwin)`) is compiled only by the macOS CI job: say so when you change it.

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|----|------|------|--------|-------|---------|
