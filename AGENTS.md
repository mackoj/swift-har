# Agent notes

`swift-har` is a Swift library, not an app: `Codable` models for the HTTP Archive (HAR) 1.2 format, builders that turn an HTTP request and its response into a HAR entry, and JSON serialization. It never performs network requests. Products and their dependency budget are in `Package.swift`; usage is in `README.md`.

Read `CONSTRAINTS.md` before writing code. Do not weaken it to make a change pass.

## Project conventions
- Consult `GLOSSARY.md` for domain terms, `docs/adr/` for decisions and their rationale, and `CODING_STANDARDS.md` for review rules.
- Work on a topic branch, never directly on `main`. Locally, prefer a sibling worktree: `git worktree add -b <topic> ../swift-har-<topic> main`.
- The [HAR 1.2 specification](http://www.softwareishard.com/blog/har-12-spec/) is the source of truth for behaviour. Cite the HAR object (for example "HAR 1.2 `timings`") a change implements, and record a deliberate deviation or a choice the specification leaves open in the README's _Specification notes_ and, when it is a design decision, in an ADR.

## How to work
- **Plan first.** For a change spanning several files or with more than one reasonable reading, state your assumptions and a short plan (`step → verify: check`), then wait for approval. Name what is unclear instead of guessing.
- **Test first.** Turn the task into a check before coding: a bug gets a failing test that reproduces it; a feature gets a test that exercises it; a refactor keeps every existing test green before and after.
- **Smallest diff.** Every changed line traces to the request. Match the surrounding file's idioms even where you would write it differently. Remove what your change orphans; mention, rather than delete, pre-existing dead code.
- **Never invent data.** When a value is not known, use what the specification prescribes for "not available" (`-1` for sizes, an omitted optional field) or make the caller supply it. Do not read the clock, guess timings, or fabricate bodies.

## Docs travel with code
`README.md` is the user documentation and DocC comments are the API reference (Swift Package Index builds docs for `HARKit` and `HARKitURLSession`, see `.spi.yml`). In the same change as any API or behaviour change:
- Update the doc comment on every public declaration you touch.
- Update every README section, example and table the change affects (`grep -n "<Symbol>" README.md`), including _Specification notes_.
- Keep README snippets compiling: `Tests/HARKitTests/ReadmeTests.swift` and `Tests/HARKitURLSessionTests/ReadmeTests.swift` mirror them, so a changed snippet changes its test.

## Build and test
- `swift build` and `swift test`; one test with `swift test --filter <Suite>/<test>`.
- CI (`.github/workflows/ci.yml`) runs macOS and Linux on Swift 6.0, 6.1 and 6.2: code must compile on 6.0 and with swift-corelibs-foundation on Linux. Without a local Linux toolchain: `docker run --rm -v "$PWD":/src -w /src swift:6.0 swift test`.
- Format before handing back Swift changes: `swift-format format --in-place --parallel --recursive Sources Tests Package.swift` (config in `.swift-format`). Use the Swift 6.3 toolchain's swift-format (`docker run --rm -v "$PWD":/src -w /src swift:6.3 swift-format …`): other versions wrap lines differently.
- Pull requests also run `.github/workflows/soundness.yml`: swiftlang's soundness checks (format, DocC with warnings as errors, API breakage against the base branch, YAML lint, shellcheck, broken symlinks) plus actionlint and zizmor on the workflows. A deliberate API break is called out in the pull request.
