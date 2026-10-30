# 3. Two products: HARKit and HARKitURLSession

Date: 2026-10-30. Status: accepted.

## Context

`URLRequest`, `HTTPURLResponse` and `URLSessionTaskMetrics` live in FoundationNetworking on Linux, which links libcurl, and in full Foundation elsewhere. Many HTTP clients (AsyncHTTPClient, swift-nio based servers, custom stacks) never use them. FoundationEssentials provides everything else HAR export needs (`Data`, `Date`, `URL`, base64, ISO 8601, JSON coding).

## Decision

- `HARKit`: HAR 1.2 models, builders from plain values (method, `URL`, ordered headers, body `Data`, status) and JSON serialization. It imports FoundationEssentials when available and full Foundation only as the fallback, and never FoundationNetworking.
- `HARKitURLSession`: initializers from `URLRequest`, `HTTPURLResponse` and (on Apple platforms) URLSession task metrics, built on `HARKit`.

## Consequences

- Clients that do not use URLSession depend on `HARKit` alone and do not link FoundationNetworking.
- `scripts/check-foundation-imports.sh` and `CONSTRAINTS.md` keep the budget honest.
- Two products to document and test; the URLSession adapter stays thin.
