# swift-har

Swift models and builders for exporting HTTP traffic as HTTP Archive (HAR) 1.2 JSON. Terms follow the [HAR 1.2 specification](http://www.softwareishard.com/blog/har-12-spec/); the Swift type is in parentheses.

## Documents

**Specification**:
HAR 1.2 as published by Jan Odvarko (mirrored at [ahmadnassri/har-spec](https://github.com/ahmadnassri/har-spec/blob/master/versions/1.2.md)). Version 1.3 is a proposal and is not implemented.
_Avoid_: standard, RFC (HAR has none)

**Archive** (`HAR.Archive`):
A whole HAR file: a JSON object whose only key is `log`. What gets written to disk.
_Avoid_: HAR document, dump

**Log** (`HAR.Log`):
The root object of the exported data: format version, Creator, optional Browser and Pages, and the Entries.
_Avoid_: session, capture

**Creator** (`HAR.Creator`):
The name and version of the application that exported the Log, for example the app embedding this package. The `browser` field has the same shape and reuses the type.

**Page** (`HAR.Page`):
A web page that groups Entries through `pageref`. Optional: tools that cannot group requests leave Pages out.

## Traffic

**Entry** (`HAR.Entry`):
One HTTP exchange: when it started, its Request, its Response, Cache information and Timings. An Entry always has a Response (see ADR 0001).
_Avoid_: transaction, call, record

**Request** (`HAR.Request`) / **Response** (`HAR.Response`):
The HTTP request sent and the response received, with ordered Headers, Cookies and sizes.

**Header** (`HAR.Header`):
One header line as a name/value pair. Order and repetitions are kept; names are compared case-insensitively when the library looks one up.

**Cookie** (`HAR.Cookie`):
A cookie sent in a `Cookie` request header or set by a `Set-Cookie` response header.

**Query parameter** (`HAR.QueryParameter`):
One `name=value` pair of the request URL's query, percent-decoded.
_Avoid_: query item (Foundation's type), query string (the whole `?…` part)

**Post data** (`HAR.PostData`):
The request body: either `text` or form `params` (`HAR.PostParameter`), never both.
_Avoid_: request body (the bytes), payload (that is `PostData.Payload`, the text-or-params choice)

**Content** (`HAR.Content`):
The response body after HTTP decoding: its size, MIME type and, when representable, its text (plain or base64 with `encoding`).
_Avoid_: body (the bytes)

**Body size** / **Headers size**:
Bytes of the body or header block as transferred. `-1` when not known, for example because the body was decompressed before the caller saw it.

**Cache** (`HAR.Cache`):
What the client cache held before and after the request. A state that is not known is left out; a known absence is `null`.

**Timings** (`HAR.Timings`):
Durations in milliseconds of the phases of an Entry (`blocked`, `dns`, `connect`, `ssl`, `send`, `wait`, `receive`). `send`, `wait` and `receive` are required and non-negative; the others are omitted when not measured and `-1` when they do not apply. The Entry's `time` is their sum (excluding `-1` and `ssl`, which is part of `connect`).
_Avoid_: metrics (that is `URLSessionTaskMetrics`), latency

## Conventions

**Not available**:
The specification's `-1` for a number that could not be obtained, or an omitted optional field. Never a guess.
_Avoid_: default, zero

**Custom field**:
A field whose name starts with `_`, allowed anywhere by the specification. This package writes none and ignores them when decoding.
_Avoid_: extension, vendor field
