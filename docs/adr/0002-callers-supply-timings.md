# 2. Callers supply timings

Date: 2026-10-30. Status: accepted.

## Context

HAR 1.2 requires `timings.send`, `timings.wait` and `timings.receive`, says they "must have non-negative values", and requires `entry.time` to equal the sum of the timings that are not `-1`. There is no value for "not measured" for these three. Many callers have no phase timings: `URLSessionTaskMetrics` is Apple-only in practice (swift-corelibs-foundation leaves it mostly empty), and other HTTP clients expose nothing.

Writing zeros would look like a measurement; writing `-1` contradicts the specification's prose (although `har-schema` accepts it).

## Decision

`HAR.Entry` takes a `HAR.Timings` with no default, and `HAR.Timings` requires `send`, `wait` and `receive`. Its initializer throws `HAR.TimingsError` for values HAR forbids (negative or non-finite required phases, optional phases below `-1`, `ssl` larger than `connect`). `entry.time` is computed from the timings, never stored, so it always matches them.

On Apple platforms `HARKitURLSession` converts a `URLSessionTaskTransactionMetrics` into `HAR.Timings`, returning `nil` when the required phases were not recorded.

## Consequences

- Whatever timings appear in an archive are the caller's statement; the library never invents them.
- Every call site has to decide what to write when it has no measurements, which the README discusses.
- Decoding stays lenient: an archive written by another tool with `-1` in a required phase still decodes.
