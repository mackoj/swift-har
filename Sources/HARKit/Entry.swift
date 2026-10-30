#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension HAR {
    /// One HTTP exchange (HAR 1.2 `entries`).
    ///
    /// An entry always has a response (ADR 0001) and caller-supplied timings (ADR 0002): the library
    /// does not make up either.
    public struct Entry: Codable, Hashable, Sendable {
        /// The ``Page/id`` of the parent page, if the log has pages.
        public var pageref: String?
        /// When the request started. Supplied by the caller: the library never reads the clock.
        /// Written in UTC with millisecond precision.
        public var startedDateTime: Date
        public var request: Request
        public var response: Response
        public var cache: Cache
        public var timings: Timings
        /// The IP address of the server, as resolved by DNS.
        public var serverIPAddress: String?
        /// An identifier of the TCP connection, such as the client port.
        public var connection: String?
        public var comment: String?

        /// The total time of the entry in milliseconds: the sum of its timings, without `-1` values
        /// and without `ssl` (already part of `connect`), as HAR 1.2 requires.
        ///
        /// Computed from ``timings``, so the two never disagree; a `time` read from a file is ignored.
        public var time: Double { timings.total }

        public init(
            startedDateTime: Date, request: Request, response: Response, timings: Timings, cache: Cache = Cache(),
            pageref: String? = nil, serverIPAddress: String? = nil, connection: String? = nil, comment: String? = nil
        ) {
            self.pageref = pageref
            self.startedDateTime = startedDateTime
            self.request = request
            self.response = response
            self.cache = cache
            self.timings = timings
            self.serverIPAddress = serverIPAddress
            self.connection = connection
            self.comment = comment
        }

        private enum CodingKeys: String, CodingKey {
            case pageref, startedDateTime, time, request, response, cache, timings, serverIPAddress, connection,
                comment
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pageref = try container.decodeIfPresent(String.self, forKey: .pageref)
            startedDateTime = try container.decodeDate(forKey: .startedDateTime)
            request = try container.decode(Request.self, forKey: .request)
            response = try container.decode(Response.self, forKey: .response)
            // The specification's cache example 1 allows leaving out the whole field.
            cache = try container.decodeIfPresent(Cache.self, forKey: .cache) ?? Cache()
            timings = try container.decode(Timings.self, forKey: .timings)
            serverIPAddress = try container.decodeIfPresent(String.self, forKey: .serverIPAddress)
            connection = try container.decodeIfPresent(String.self, forKey: .connection)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(pageref, forKey: .pageref)
            try container.encodeDate(startedDateTime, forKey: .startedDateTime)
            try container.encode(time, forKey: .time)
            try container.encode(request, forKey: .request)
            try container.encode(response, forKey: .response)
            try container.encode(cache, forKey: .cache)
            try container.encode(timings, forKey: .timings)
            try container.encodeIfPresent(serverIPAddress, forKey: .serverIPAddress)
            try container.encodeIfPresent(connection, forKey: .connection)
            try container.encodeIfPresent(comment, forKey: .comment)
        }
    }

    /// What the client cache held before and after the request (HAR 1.2 `cache`).
    ///
    /// `Cache()` encodes as `{}`: no cache information.
    public struct Cache: Codable, Hashable, Sendable {
        /// What HAR 1.2 `beforeRequest` or `afterRequest` says about the cache.
        public enum State: Hashable, Sendable {
            /// There was no cache entry (`null`).
            case noEntry
            /// The cache entry at that point.
            case entry(CacheEntry)
        }

        /// The cache state before the request; `nil` (omitted) when not known.
        public var beforeRequest: State?
        /// The cache state after the request; `nil` (omitted) when not known.
        public var afterRequest: State?
        public var comment: String?

        public init(beforeRequest: State? = nil, afterRequest: State? = nil, comment: String? = nil) {
            self.beforeRequest = beforeRequest
            self.afterRequest = afterRequest
            self.comment = comment
        }

        private enum CodingKeys: String, CodingKey {
            case beforeRequest, afterRequest, comment
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func state(_ key: CodingKeys) throws -> State? {
                guard container.contains(key) else { return nil }
                if try container.decodeNil(forKey: key) { return .noEntry }
                return .entry(try container.decode(CacheEntry.self, forKey: key))
            }
            beforeRequest = try state(.beforeRequest)
            afterRequest = try state(.afterRequest)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            func encode(_ state: State?, forKey key: CodingKeys) throws {
                switch state {
                case nil: break
                case .noEntry: try container.encodeNil(forKey: key)
                case .entry(let entry): try container.encode(entry, forKey: key)
                }
            }
            try encode(beforeRequest, forKey: .beforeRequest)
            try encode(afterRequest, forKey: .afterRequest)
            try container.encodeIfPresent(comment, forKey: .comment)
        }
    }

    /// A cache entry (HAR 1.2 `beforeRequest` / `afterRequest`).
    ///
    /// The dates are kept as strings: HAR 1.2 does not give them a format, and its own example uses
    /// a value that is not a valid ISO 8601 date.
    public struct CacheEntry: Codable, Hashable, Sendable {
        public var expires: String?
        /// The last time the cache entry was opened.
        public var lastAccess: String
        public var eTag: String
        /// How many times the cache entry was opened.
        public var hitCount: Int
        public var comment: String?

        public init(expires: String? = nil, lastAccess: String, eTag: String, hitCount: Int, comment: String? = nil) {
            self.expires = expires
            self.lastAccess = lastAccess
            self.eTag = eTag
            self.hitCount = hitCount
            self.comment = comment
        }
    }
}
