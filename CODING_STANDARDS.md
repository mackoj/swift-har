# Coding standards

Read during review. Each rule is a judgement call; mechanical rules live in `CONSTRAINTS.md`.

## Simplicity

- **Boring code.** The minimum that solves the stated problem: no options, parameters or variants nobody asked for, no protocol or abstraction with a single user. A plain `if`/`switch` over an enum beats a pattern.
- **Surgical diffs.** Every changed line traces to the request; adjacent code, comments and formatting stay as they were. Orphans the change creates are removed in the same change.
- **Matches its surroundings.** New code follows the naming, comment density and idioms of the file it lands in (e.g. `Codable, Hashable, Sendable` on every model, one HAR object per type, field names as in the specification).
- **Scoped to export.** The package represents and serializes traffic. Capturing it (swizzling, proxies, `URLProtocol`), sending it, or analysing it belongs to the caller.

## Specification fidelity

- **The spec decides.** Field names, required fields and "not available" values follow HAR 1.2. Where the specification is silent or contradicts itself, the choice is written down (README _Specification notes_, ADR when it shapes the API).
- **Honest about unknowns.** A value that is not known is not made up: sizes become `-1`, optional fields are omitted, and data the library cannot obtain (timings, a response) is a required input. A lossy conversion (a body that cannot be represented as text) drops the field rather than misrepresenting it.
- **Lenient decoding, strict construction.** Decoding accepts what other HAR writers produce; initializers that build new values reject what HAR 1.2 forbids (for example negative `send`, `wait` or `receive`).
- **Domain language.** Types, docs and messages use the terms in `GLOSSARY.md`, not the words under _Avoid_. A new concept gets a glossary entry in the same change.

## Compile-time safety

- **Make misuse unrepresentable.** Mutually exclusive fields become an enum (`PostData.Payload`); a field whose absence and `null` mean different things becomes an enum too (`Cache.State`). Derived values are computed, not stored (`Entry.time`).
- **Failures are typed values.** Initializers that validate `throw` a dedicated error type that says what failed (`TimingsError`). An optional return is for genuine absence, not to hide why something failed.
- **Sendable value types.** Public models are `struct`/`enum`, `Sendable` and `Hashable`, so tests compare whole values.
- **Pure library.** Callers pass data in; the library performs no I/O, reads no clock, generates no identifiers and touches no singletons.
- **Foundation, sparingly.** `HARKit` uses FoundationEssentials (falling back to Foundation where it does not exist) and nothing from Foundation that FoundationEssentials lacks; anything needing `URLRequest`, `HTTPURLResponse` or `URLSession` lives in `HARKitURLSession`. Platform differences go behind `#if canImport(…)`.

## Docs

- **Docs in the same change.** Public API or behaviour changes update the DocC comment, every affected README section or table, and the README tests (see `AGENTS.md`). A stale doc is a defect: wrong documentation is worse than none.
- **Doc comments explain why.** Document constraints, specification references and non-obvious semantics; skip restating names and signatures.

## Tests

- **Swift Testing only.** `@Suite`, `@Test`, `#expect`, `#require`; no XCTest.
- **Given / When / Then.** Each test has those three phases (comments when the test is longer than a few lines) and asserts one behaviour; related `#expect`s sit together under _Then_.
- **Isolated.** Each test builds its own values; no shared mutable state, so the default random order always passes.
- **Derived from the specification.** Tests cite the HAR 1.2 object or rule they check. Cases inspired by other HAR implementations are written independently and name their source in a comment; no code or test is copied unless its licence allows it and the copy is attributed.
