import HARKit
import Testing

@Suite("Format version")
struct FormatVersionTests {
    @Test func writesHAR12() {
        #expect(HAR.formatVersion == "1.2")
    }
}
