import XCTest
@testable import VoiceCore
final class NavigationEvidenceTests:XCTestCase {
    func testExactDestinationRequired() {
        XCTAssertTrue(NavigationEvidence.matches(expected:"https://example.test/events/",observed:"https://example.test/events/"))
        XCTAssertFalse(NavigationEvidence.matches(expected:"https://example.test/events/",observed:"https://example.test/downloads/"))
        XCTAssertFalse(NavigationEvidence.matches(expected:"https://example.test/events/",observed:nil))
        XCTAssertFalse(NavigationEvidence.matches(expected:"javascript:void(0)",observed:"javascript:void(0)"))
        XCTAssertFalse(NavigationEvidence.matches(expected:"https://example.test/#one",observed:"https://example.test/#two"))
    }
}
