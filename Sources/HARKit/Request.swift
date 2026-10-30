#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension HAR {
    /// The request of an entry (HAR 1.2 `request`).
    public struct Request: Codable, Hashable, Sendable {
        public var method: String
        /// The absolute URL, without fragment.
        public var url: String
        /// For example `HTTP/1.1` or `HTTP/2`; empty when not known.
        public var httpVersion: String
        public var cookies: [Cookie]
        public var headers: [Header]
        public var queryString: [QueryParameter]
        public var postData: PostData?
        /// Bytes from the start of the request up to and including the blank line before the body;
        /// `-1` when not available.
        public var headersSize: Int
        /// Bytes of the request body; `-1` when not available.
        public var bodySize: Int
        public var comment: String?

        /// Creates a request with every field given explicitly.
        public init(
            method: String, url: String, httpVersion: String, cookies: [Cookie] = [], headers: [Header] = [],
            queryString: [QueryParameter] = [], postData: PostData? = nil, headersSize: Int = -1, bodySize: Int = -1,
            comment: String? = nil
        ) {
            self.method = method
            self.url = url
            self.httpVersion = httpVersion
            self.cookies = cookies
            self.headers = headers
            self.queryString = queryString
            self.postData = postData
            self.headersSize = headersSize
            self.bodySize = bodySize
            self.comment = comment
        }

        /// Creates a request from what was sent, deriving the fields HAR 1.2 repeats.
        ///
        /// - `url` loses its fragment, and ``queryString`` is its query split on `&`, percent-decoded
        ///   (`+` is kept: only form bodies use it for spaces). Malformed escapes are kept as written.
        /// - ``cookies`` come from the `Cookie` headers, with only a name and a value.
        /// - ``postData`` is the body as text, or as `params` for `application/x-www-form-urlencoded`,
        ///   when its `Content-Type` is textual and it is UTF-8; otherwise it is left out, because
        ///   HAR 1.2 cannot mark post data as base64 (ADR 0004).
        /// - ``bodySize`` is the byte count of `body` (0 without one). ``headersSize`` is `-1`: the
        ///   header block on the wire depends on the HTTP version and on headers the client adds.
        ///
        /// - Parameters:
        ///   - method: The request method, such as `GET`.
        ///   - url: The absolute request URL.
        ///   - httpVersion: For example `HTTP/1.1`; empty when not known.
        ///   - headers: The request headers in the order they were sent, repetitions included.
        ///   - body: The body bytes as sent, or `nil` when the request has none.
        public init(method: String, url: URL, httpVersion: String, headers: [Header] = [], body: Data? = nil) {
            let absolute = url.absoluteString
            let withoutFragment = absolute.prefix { $0 != "#" }
            let query = withoutFragment.drop { $0 != "?" }.dropFirst()
            self.init(
                method: method,
                url: String(withoutFragment),
                httpVersion: httpVersion,
                cookies: headers.values(named: "Cookie").flatMap(Cookie.parseCookieHeader),
                headers: headers,
                queryString: nameValuePairs(query, plusAsSpace: false).map {
                    QueryParameter(name: $0.name, value: $0.value)
                },
                postData: body.flatMap { PostData(body: $0, mimeType: headers.value(named: "Content-Type") ?? "") },
                bodySize: body?.count ?? 0
            )
        }
    }

    /// A header line (HAR 1.2 `headers`).
    public struct Header: Codable, Hashable, Sendable {
        public var name: String
        public var value: String
        public var comment: String?

        public init(name: String, value: String, comment: String? = nil) {
            self.name = name
            self.value = value
            self.comment = comment
        }
    }

    /// A parameter of the URL query (HAR 1.2 `queryString`).
    public struct QueryParameter: Codable, Hashable, Sendable {
        public var name: String
        public var value: String
        public var comment: String?

        public init(name: String, value: String, comment: String? = nil) {
            self.name = name
            self.value = value
            self.comment = comment
        }
    }

    /// The posted body (HAR 1.2 `postData`).
    public struct PostData: Codable, Hashable, Sendable {
        /// Either the text or the parameters: HAR 1.2 makes them mutually exclusive.
        public enum Payload: Hashable, Sendable {
            case text(String)
            /// URL-encoded form parameters.
            case params([PostParameter])
        }

        /// The request's `Content-Type`, parameters included.
        public var mimeType: String
        public var payload: Payload
        public var comment: String?

        public init(mimeType: String, payload: Payload, comment: String? = nil) {
            self.mimeType = mimeType
            self.payload = payload
            self.comment = comment
        }

        /// The body as post data, or `nil` when HAR 1.2 cannot represent it.
        ///
        /// An `application/x-www-form-urlencoded` UTF-8 body becomes ``Payload/params(_:)``, decoded
        /// with `+` as space. Another body becomes ``Payload/text(_:)`` when `mimeType` is textual
        /// (`text/*`, JSON, XML, JavaScript…), declares no charset other than UTF-8 or ASCII, and the
        /// bytes are valid UTF-8. Anything else, binary or `multipart/form-data` included, is `nil`.
        public init?(body: Data, mimeType: String) {
            let mediaType = MediaType(mimeType)
            guard let text = mediaType.text(of: body) else { return nil }
            if mediaType.essence == MediaType.formURLEncoded {
                let params = nameValuePairs(text, plusAsSpace: true).map {
                    PostParameter(name: $0.name, value: $0.value)
                }
                self.init(mimeType: mimeType, payload: .params(params))
            } else {
                self.init(mimeType: mimeType, payload: .text(text))
            }
        }

        private enum CodingKeys: String, CodingKey {
            case mimeType, params, text, comment
        }

        /// Decodes `text` when present, `params` otherwise: some writers include both.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mimeType = try container.decode(String.self, forKey: .mimeType)
            if let text = try container.decodeIfPresent(String.self, forKey: .text) {
                payload = .text(text)
            } else {
                payload = .params(try container.decodeIfPresent([PostParameter].self, forKey: .params) ?? [])
            }
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mimeType, forKey: .mimeType)
            switch payload {
            case .text(let text): try container.encode(text, forKey: .text)
            case .params(let params): try container.encode(params, forKey: .params)
            }
            try container.encodeIfPresent(comment, forKey: .comment)
        }
    }

    /// A posted parameter or file (HAR 1.2 `params`).
    public struct PostParameter: Codable, Hashable, Sendable {
        public var name: String
        /// The value, or the content of a posted file.
        public var value: String?
        public var fileName: String?
        /// The content type of a posted file.
        public var contentType: String?
        public var comment: String?

        public init(
            name: String, value: String? = nil, fileName: String? = nil, contentType: String? = nil,
            comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.fileName = fileName
            self.contentType = contentType
            self.comment = comment
        }
    }
}
