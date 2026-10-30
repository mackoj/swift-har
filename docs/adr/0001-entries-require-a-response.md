# 1. Entries require a response

Date: 2026-10-30. Status: accepted.

## Context

HAR 1.2 makes `entry.response` required, with required `status`, `statusText`, `httpVersion`, `content`, `redirectURL` and sizes. A request can fail, be cancelled or still be in flight, and then there is no response to describe. Browsers (Chrome, Firefox) export such requests with a placeholder response (`status: 0`, empty strings, sizes `-1`) and sometimes a custom `_error` field.

## Decision

`HAR.Entry` requires a `HAR.Response`. The library has no placeholder response and no "failed request" mode. A caller that wants failed requests in the archive builds a `HAR.Response` explicitly with the memberwise initializer, choosing the values it is willing to stand behind.

## Consequences

- The API stays small and every entry the library builds describes a response that was actually received.
- Failed requests are not exported unless the caller opts in by building a response; the README says how.
- Adding a placeholder later is additive (a new initializer), not a break.
