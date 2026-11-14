# Measuring and profiling

The benchmarks live in `Benchmarks/`, a separate package on [package-benchmark](https://github.com/ordo-one/benchmark),
so HARKit never depends on it. Run everything from the repository root.

| Benchmark | What it measures |
|---|---|
| Build request, JSON body | `HAR.Request(method:url:httpVersion:headers:body:)` with a query string, eight headers, cookies and a JSON body |
| Build response, JSON body | `HAR.Response(status:statusText:httpVersion:headers:body:)` with two `Set-Cookie` headers and a 20-item JSON array body |
| Build response, binary body | The same with a 4 KB binary body, which becomes base64 content |
| Build entry | A request, a response and an `HAR.Entry` |
| Build log, 1000 entries | 1000 entries and the `HAR.Log` that sorts them |
| Encode log, 1000 entries (pretty) | `HAR.Archive.jsonData(prettyPrinted:)` on that log |
| Decode log, 1000 entries | `HAR.Archive(json:)` on the encoded log |

## Measure a change

Save `main`'s numbers before you change code, then compare the same harness after:

```sh
swift package --package-path Benchmarks benchmark --format markdown --no-progress > .build/before.md
# … change the code …
swift package --package-path Benchmarks benchmark --format markdown --no-progress > .build/after.md
swift run --package-path Benchmarks -c release p50 .build/before.md .build/after.md
```

`p50` prints a Markdown table of each benchmark's median wall clock, CPU time and mallocs, before → after, ready for
the pull request. Malloc and retain counts are deterministic; time moves between runs, a lot on a busy machine, so run
before and after alternately a few times and compare the best medians before trusting a small change.

- `--filter` takes one regular expression per flag and runs the benchmarks that match any of them: repeat the flag
  (`--filter 'Build.*' --filter 'Decode.*'`) rather than writing `A|B`.
- The per-operation benchmarks (`scalingFactor: .kilo`) report nanoseconds per operation, marked `*` in
  package-benchmark's tables; `p50` converts them to microseconds.
- Malloc counts need jemalloc (`brew install jemalloc`). Without it, set `BENCHMARK_DISABLE_JEMALLOC=true`, as CI does
  to build the package.

## Profile a benchmark

```sh
Benchmarks/scripts/profile.sh 'Build entry' 25
```

It runs that one benchmark under Instruments' Time Profiler and prints:

- **Self**: the functions the samples were in. Standard library entries here say what kind of work dominates
  (`Data.Iterator.next` is byte-by-byte iteration over `Data`, `_xzm_malloc` allocation, `swift_retain` reference
  counting).
- **Inclusive**: the HARKit functions with the most samples under them, which says whose work it is.

The trace stays in `Benchmarks/.build/profiles/` to open in Instruments. The benchmark's setup (building and encoding
the shared log) is in every trace, so `HAR.Archive.jsonData` shows up in the inclusive list of a building benchmark.

## What has paid off

0.1.1, measured on Apple silicon (best p50 of three alternating runs):

| Benchmark | CPU p50 (µs) | Mallocs p50 |
|---|---|---|
| Build request, JSON body | 9.5 → 8.1 (0.85x) | 40 → 26 (0.65x) |
| Build response, JSON body | 15.9 → 10.9 (0.68x) | 31 → 30 (0.97x) |
| Build response, binary body | 2.3 → 2.3 (0.97x) | 3 → 2 (0.67x) |
| Build entry | 25.9 → 19.2 (0.74x) | 71 → 56 (0.79x) |
| Build log, 1000 entries | 26,608 → 19,726 (0.74x) | 71,016 → 56,016 (0.79x) |
| Encode log, 1000 entries | 59,736 → 58,360 (0.98x) | 216,075 → 206,073 (0.95x) |
| Encode log, 1000 entries, pretty | 63,570 → 62,358 (0.98x) | 216,075 → 206,073 (0.95x) |
| Decode log, 1000 entries | 71,827 → 70,517 (0.98x) | 179,054 → 175,052 (0.98x) |

- **Validate UTF-8 over buffers, not through `Data`'s iterator.** Checking that a body is UTF-8 text (decode, then
  compare the bytes) iterated `Data` one byte at a time through a generic iterator: a quarter of the time to build an
  entry. `withContiguousStorageIfAvailable` gives both passes a buffer.
- **Compare names without lowercased copies.** Header lookups (`Content-Type`, `Cookie`, `Set-Cookie`, `Location`,
  `Content-Encoding`) and cookie attributes compared `lowercased()` strings. ASCII names are now folded byte by byte;
  a non-ASCII name still goes through `lowercased()`, because Unicode maps a few characters to ASCII letters
  (U+212A KELVIN SIGN is `k`).
- **Skip decoding when there is nothing to decode.** A query or form value without `%` (or `+` in a form) is returned
  as is instead of being copied into a byte array and validated again.
- **Write and read dates by hand in 1900–9999.** Each date went through a new `Date.ISO8601FormatStyle`. Dates in
  that range are now written and parsed with day arithmetic; other years, offsets other than `Z` and anything
  unusual still go through the format style, and a test checks both agree across the whole range.
- **Don't copy the input.** `HAR.Archive(json:)` copied the file before decoding even without a byte order mark.
- Encoding and decoding time is spent in Foundation's `JSONEncoder` and `JSONDecoder` (`JSONWriter.serializeString`,
  the scanner, key sorting), not here: the date and copy savings are a few percent of it.
