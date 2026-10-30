#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension HAR {
    /// The response of an entry (HAR 1.2 `response`).
    public struct Response: Codable, Hashable, Sendable {
        public var status: Int
        /// The reason phrase; empty when there is none (HTTP/2 and later) or it is not known.
        public var statusText: String
        /// For example `HTTP/1.1` or `HTTP/2`; empty when not known.
        public var httpVersion: String
        public var cookies: [Cookie]
        public var headers: [Header]
        public var content: Content
        /// The `Location` header, or empty.
        public var redirectURL: String
        /// Bytes of the received header block, up to and including the blank line; `-1` when not
        /// available.
        public var headersSize: Int
        /// Bytes of the body as received (compressed, if it was); `-1` when not available, `0` for a
        /// response served from cache (`304`).
        public var bodySize: Int
        public var comment: String?

        /// Creates a response with every field given explicitly.
        public init(
            status: Int, statusText: String, httpVersion: String, cookies: [Cookie] = [], headers: [Header] = [],
            content: Content, redirectURL: String = "", headersSize: Int = -1, bodySize: Int = -1,
            comment: String? = nil
        ) {
            self.status = status
            self.statusText = statusText
            self.httpVersion = httpVersion
            self.cookies = cookies
            self.headers = headers
            self.content = content
            self.redirectURL = redirectURL
            self.headersSize = headersSize
            self.bodySize = bodySize
            self.comment = comment
        }

        /// Creates a response from what was received, deriving the fields HAR 1.2 repeats.
        ///
        /// - ``content`` is built from `body` and the `Content-Type` header, see
        ///   ``Content/init(body:mimeType:)``.
        /// - ``cookies`` come from the `Set-Cookie` headers (RFC 6265 §5.2). Values joined with
        ///   commas, as some HTTP stacks do, are split again. `Max-Age` is not converted to `expires`
        ///   because that needs the current time.
        /// - ``redirectURL`` is the `Location` header.
        /// - ``bodySize`` is the byte count of `body` unless a `Content-Encoding` other than
        ///   `identity` is present: `body` is then the decoded body, and the transferred size is not
        ///   known (`-1`). ``headersSize`` is `-1`.
        ///
        /// - Parameters:
        ///   - status: The status code.
        ///   - statusText: The reason phrase; empty when there is none or it is not known.
        ///   - httpVersion: For example `HTTP/1.1`; empty when not known.
        ///   - headers: The response headers in the order they were received, repetitions included.
        ///   - body: The body after HTTP decoding (decompressed, unchunked). Pass the bytes you have;
        ///     an empty `Data` states that the body was empty.
        public init(status: Int, statusText: String, httpVersion: String, headers: [Header], body: Data) {
            let encoding = headers.value(named: "Content-Encoding").map { $0.trimmingOWS.lowercased() } ?? ""
            self.init(
                status: status,
                statusText: statusText,
                httpVersion: httpVersion,
                cookies: headers.values(named: "Set-Cookie").flatMap(Cookie.parseSetCookieHeader),
                headers: headers,
                content: Content(body: body, mimeType: headers.value(named: "Content-Type") ?? ""),
                redirectURL: headers.value(named: "Location") ?? "",
                bodySize: encoding.isEmpty || encoding == "identity" ? body.count : -1
            )
        }
    }

    /// The response body after HTTP decoding (HAR 1.2 `content`).
    public struct Content: Codable, Hashable, Sendable {
        /// Bytes of the decoded body.
        public var size: Int
        /// Bytes saved by compression; `nil` (omitted) when not known.
        public var compression: Int?
        /// The response's `Content-Type`, parameters included; empty when there was none.
        public var mimeType: String
        /// The body as text, or encoded as named by ``encoding``; `nil` when not included.
        public var text: String?
        /// How ``text`` is encoded, such as `"base64"`; `nil` for plain UTF-8 text.
        public var encoding: String?
        public var comment: String?

        public init(
            size: Int, compression: Int? = nil, mimeType: String, text: String? = nil, encoding: String? = nil,
            comment: String? = nil
        ) {
            self.size = size
            self.compression = compression
            self.mimeType = mimeType
            self.text = text
            self.encoding = encoding
            self.comment = comment
        }

        /// The decoded body as content: plain ``text`` when `mimeType` is textual, declares no
        /// charset other than UTF-8 or ASCII, and the bytes are valid UTF-8; base64 otherwise, so the
        /// bytes can always be recovered exactly. An empty body has no text.
        public init(body: Data, mimeType: String) {
            self.init(size: body.count, mimeType: mimeType)
            guard !body.isEmpty else { return }
            if let text = MediaType(mimeType).text(of: body) {
                self.text = text
            } else {
                self.text = body.base64EncodedString()
                self.encoding = "base64"
            }
        }
    }
}
