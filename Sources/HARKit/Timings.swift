extension HAR {
    /// Durations in milliseconds of the phases of an entry (HAR 1.2 `timings`).
    ///
    /// `send`, `wait` and `receive` are required and non-negative. `blocked`, `dns`, `connect` and
    /// `ssl` are `nil` (omitted) when they were not measured and `-1` when they do not apply, such as
    /// `connect` on a reused connection. `ssl` is part of `connect`, as in HAR 1.1.
    ///
    /// There is no default: only the caller knows what was measured (ADR 0002).
    public struct Timings: Codable, Hashable, Sendable {
        /// Time spent queued, waiting for a connection.
        public let blocked: Double?
        /// DNS resolution.
        public let dns: Double?
        /// Creating the connection, TLS negotiation included.
        public let connect: Double?
        /// Sending the request.
        public let send: Double
        /// Waiting for the first byte of the response.
        public let wait: Double
        /// Reading the response.
        public let receive: Double
        /// TLS negotiation, also counted in ``connect``.
        public let ssl: Double?
        public let comment: String?

        /// Creates timings, rejecting what HAR 1.2 forbids.
        ///
        /// - Throws: ``HAR/TimingsError/invalidValue(phase:)`` when `send`, `wait` or `receive` is
        ///   negative or not finite, or another phase is neither `-1` nor a finite non-negative number;
        ///   ``HAR/TimingsError/sslNotIncludedInConnect`` when a measured `ssl` exceeds `connect` or
        ///   `connect` is missing.
        public init(
            blocked: Double? = nil, dns: Double? = nil, connect: Double? = nil, send: Double, wait: Double,
            receive: Double, ssl: Double? = nil, comment: String? = nil
        ) throws(TimingsError) {
            func checkOptional(_ value: Double?, _ phase: String) throws(TimingsError) {
                guard let value else { return }
                guard value == -1 || (value.isFinite && value >= 0) else { throw .invalidValue(phase: phase) }
            }
            func checkRequired(_ value: Double, _ phase: String) throws(TimingsError) {
                guard value.isFinite && value >= 0 else { throw .invalidValue(phase: phase) }
            }
            try checkOptional(blocked, "blocked")
            try checkOptional(dns, "dns")
            try checkOptional(connect, "connect")
            try checkRequired(send, "send")
            try checkRequired(wait, "wait")
            try checkRequired(receive, "receive")
            try checkOptional(ssl, "ssl")
            if let ssl, ssl >= 0 {
                guard let connect, connect >= ssl else { throw .sslNotIncludedInConnect }
            }
            self.blocked = blocked
            self.dns = dns
            self.connect = connect
            self.send = send
            self.wait = wait
            self.receive = receive
            self.ssl = ssl
            self.comment = comment
        }

        /// The sum of the available timings, which is ``Entry/time``.
        var total: Double {
            [blocked, dns, connect, send, wait, receive].compactMap { $0 }.filter { $0 >= 0 }.reduce(0, +)
        }
    }

    /// Why ``Timings`` could not be created.
    public enum TimingsError: Error, Hashable, Sendable {
        /// The phase (`"send"`, `"dns"`…) has a value HAR 1.2 does not allow.
        case invalidValue(phase: String)
        /// A measured `ssl` must be included in `connect`, so `connect` must be present and at least
        /// as long.
        case sslNotIncludedInConnect
    }
}
