#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension HAR {
    /// A HAR file: a JSON object whose only member is ``log``.
    ///
    /// ```swift
    /// let data = try HAR.Archive(log: log).jsonData(prettyPrinted: true)
    /// let archive = try HAR.Archive(json: data)
    /// ```
    public struct Archive: Codable, Hashable, Sendable {
        public var log: Log

        public init(log: Log) {
            self.log = log
        }

        /// Decodes a HAR file, ignoring a leading UTF-8 byte order mark as HAR 1.2 requires.
        ///
        /// Decoding is lenient: custom (`_`-prefixed) and unknown fields are ignored, and values
        /// HAR 1.2 forbids but other writers produce (such as `-1` in a required timing) are kept.
        public init(json data: Data) throws {
            let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
            let body = data.starts(with: bom) ? data.dropFirst(bom.count) : data[...]
            self = try JSONDecoder().decode(Archive.self, from: Data(body))
        }

        /// The archive as UTF-8 JSON, with keys sorted so that the same archive always produces the
        /// same bytes.
        public func jsonData(prettyPrinted: Bool = false) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if prettyPrinted { encoder.outputFormatting.insert(.prettyPrinted) }
            return try encoder.encode(self)
        }
    }

    /// The root of the exported data (HAR 1.2 `log`).
    public struct Log: Codable, Hashable, Sendable {
        /// The format version, ``HAR/formatVersion`` for logs built by this package.
        public var version: String
        /// The application that exported the log.
        public var creator: Creator
        /// The browser that made the requests, when there is one.
        public var browser: Creator?
        /// Pages grouping the entries; `nil` (omitted) when requests are not grouped by page.
        public var pages: [Page]?
        public var entries: [Entry]
        public var comment: String?

        /// Creates a log, sorting `entries` by ``Entry/startedDateTime`` (oldest first, ties kept in
        /// the given order), which HAR 1.2 names the preferred export order.
        public init(
            creator: Creator, browser: Creator? = nil, pages: [Page]? = nil, entries: [Entry], comment: String? = nil
        ) {
            self.version = HAR.formatVersion
            self.creator = creator
            self.browser = browser
            self.pages = pages
            self.entries = entries.enumerated()
                .sorted { ($0.element.startedDateTime, $0.offset) < ($1.element.startedDateTime, $1.offset) }
                .map(\.element)
            self.comment = comment
        }
    }

    /// The name and version of an application (HAR 1.2 `creator`, and `browser`, which has the same
    /// fields).
    public struct Creator: Codable, Hashable, Sendable {
        public var name: String
        public var version: String
        public var comment: String?

        public init(name: String, version: String, comment: String? = nil) {
            self.name = name
            self.version = version
            self.comment = comment
        }
    }

    /// A page that entries refer to through ``Entry/pageref`` (HAR 1.2 `pages`).
    public struct Page: Codable, Hashable, Sendable {
        /// When the page load began, written in UTC with millisecond precision.
        public var startedDateTime: Date
        /// Unique within the log.
        public var id: String
        public var title: String
        public var pageTimings: PageTimings
        public var comment: String?

        public init(
            startedDateTime: Date, id: String, title: String, pageTimings: PageTimings = PageTimings(),
            comment: String? = nil
        ) {
            self.startedDateTime = startedDateTime
            self.id = id
            self.title = title
            self.pageTimings = pageTimings
            self.comment = comment
        }

        private enum CodingKeys: String, CodingKey {
            case startedDateTime, id, title, pageTimings, comment
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startedDateTime = try container.decodeDate(forKey: .startedDateTime)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            pageTimings = try container.decode(PageTimings.self, forKey: .pageTimings)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeDate(startedDateTime, forKey: .startedDateTime)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(pageTimings, forKey: .pageTimings)
            try container.encodeIfPresent(comment, forKey: .comment)
        }
    }

    /// Page load events in milliseconds since ``Page/startedDateTime`` (HAR 1.2 `pageTimings`).
    ///
    /// A `nil` time is omitted, which HAR 1.2 reads as `-1`, not available.
    public struct PageTimings: Codable, Hashable, Sendable {
        /// `DOMContentLoaded`, or `document.readyState == "interactive"`, depending on the browser.
        public var onContentLoad: Double?
        /// The `load` event.
        public var onLoad: Double?
        public var comment: String?

        public init(onContentLoad: Double? = nil, onLoad: Double? = nil, comment: String? = nil) {
            self.onContentLoad = onContentLoad
            self.onLoad = onLoad
            self.comment = comment
        }
    }
}
