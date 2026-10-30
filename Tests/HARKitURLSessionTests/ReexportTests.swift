import HARKitURLSession
import Testing

@Suite("HARKitURLSession")
struct ReexportTests {
    @Test func reexportsHARKit() {
        #expect(HAR.formatVersion == "1.2")
    }
}
