/// Namespace for the [HTTP Archive (HAR) 1.2](http://www.softwareishard.com/blog/har-12-spec/) types.
///
/// Build an entry per HTTP exchange, collect the entries in a log, and serialize the archive to JSON.
public enum HAR {
    /// The HAR format version this package writes (`log.version`).
    public static let formatVersion = "1.2"
}
