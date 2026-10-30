/// Namespace for the [HTTP Archive (HAR) 1.2](http://www.softwareishard.com/blog/har-12-spec/) types.
///
/// Build an ``HAR/Entry`` per HTTP exchange, collect them in a ``HAR/Log``, and serialize the
/// ``HAR/Archive`` to JSON.
public enum HAR {
    /// The HAR format version this package writes (`log.version`).
    public static let formatVersion = "1.2"
}
