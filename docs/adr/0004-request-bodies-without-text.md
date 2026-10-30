# 4. Binary request bodies are left out of postData

Date: 2026-10-30. Status: accepted.

## Context

HAR 1.2 `postData` has `text` ("plain text posted data") or `params`, and no `encoding` field; `postData.encoding` only exists in the 1.3 proposal. Some tools (for example google/martian) still write base64 into `postData.text` with a non-standard `encoding` key, which a HAR 1.2 reader takes for plain text.

## Decision

A request body becomes `postData.text` only when its `Content-Type` is textual and the bytes are valid UTF-8 (with no non-UTF-8 charset declared), and `params` when it is `application/x-www-form-urlencoded`. Otherwise `postData` is omitted. `request.bodySize` still records the body's byte count.

## Consequences

- Archives never present binary as text. Binary uploads lose their bytes in the export, which the README states.
- Supporting HAR 1.3's `postData.encoding` later is additive.
