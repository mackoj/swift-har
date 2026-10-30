# Handoff

Living status of the work, so anyone (human or agent) can pick it up after an interruption. Update it in every pull request: move items between sections and keep "Next" ordered.

Last updated: 2026-10-30

## Goal

A Swift package that exports HTTP traffic as HAR 1.2 JSON, scoped to representing and serializing (no networking), with a minimal public API, honest handling of missing data, and FoundationEssentials rather than Foundation in the core module. The original request and the decisions taken with the maintainer are in `docs/adr/` (0001–0004).

## Decisions taken with the maintainer

- No response → no entry: `HAR.Entry` requires a `HAR.Response` (ADR 0001).
- Timings are a required input; the library never invents them (ADR 0002).
- Two products: `HARKit` (FoundationEssentials only) and `HARKitURLSession` (ADR 0003).
- Prefer FoundationEssentials over Foundation everywhere possible.
- Commit, push, open, merge pull requests and tag often.

## Environment notes

- The HAR spec site (softwareishard.com) is blocked from the cloud sandbox; the GitHub mirror `ahmadnassri/har-spec` (`versions/1.2.md`) and the `ahmadnassri/har-schema` JSON schemas (ISC) were used instead.
- No Swift toolchain on the host: start `dockerd` and use the `swift:6.0`, `swift:6.2` and `swift:6.3` (swift-format) images, e.g. `docker run --rm -v "$PWD":/src -w /src swift:6.0 swift test`.
- FoundationEssentials on Swift 6.0 has no `String.removingPercentEncoding`; `Date.ISO8601FormatStyle` truncates fractional seconds (format whole seconds and append rounded milliseconds).
- `gh` GraphQL is unavailable; use `gh api` REST calls for pull requests (`/pulls/{n}/ccr/ready_for_review`, `PUT /pulls/{n}/merge`). Job logs are not downloadable from the sandbox; reproduce soundness checks locally (see below).
- DocC check locally: copy the tree, then run swiftlang/github-workflows' `check-docs.sh --doc-targets HARKit HARKitURLSession` in `swift:6.3` with `--network host`, the proxy variables and `GIT_SSL_CAINFO=/root/.ccr/ca-bundle.crt` mounted.
- API breakage locally: `swift package diagnose-api-breaking-changes origin/main` in `swift:6.2`.

## Done

- PR #1 (merged): repository scaffolding: manifest, CI and soundness workflows, constraints, coding standards, glossary, ADRs, this file.
- PR #2: `HARKit` models for every HAR 1.2 object, JSON serialization (`HAR.Archive.jsonData`, `init(json:)`), builders `HAR.Request(method:url:httpVersion:headers:body:)`, `HAR.Response(status:statusText:httpVersion:headers:body:)`, `HAR.Content(body:mimeType:)`, `HAR.PostData(body:mimeType:)`, throwing `HAR.Timings`, cookie parsing (`Cookie`, `Set-Cookie`, RFC 6265 dates); README with usage, missing-data guidance and specification notes; `ReadmeTests`.

## In progress

- Merging PR #2 once CI is green.

## Next

1. `HARKitURLSession`: `HAR.Request(_ URLRequest, httpVersion:)`, `HAR.Response(_ HTTPURLResponse, body:httpVersion:)`, Darwin `HAR.Timings(_ URLSessionTaskTransactionMetrics)`.
2. README section for `HARKitURLSession` and its README tests.
3. Tag `0.1.0` once CI is green on main.
