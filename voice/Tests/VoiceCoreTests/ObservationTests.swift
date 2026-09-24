import XCTest
@testable import VoiceCore
final class ObservationTests: XCTestCase {
    func testAcknowledgementIsNotVerification() throws {
        let data=Data(#"{"ok":true,"message":"Click requested"}"#.utf8)
        let reply=try JSONDecoder().decode(BrowserActionResult.self,from:data)
        XCTAssertTrue(reply.summary.contains("not verified"))
    }
    func testVerifiedAndFailedResultsPreserveEvidenceMeaning() throws {
        let verified=try JSONDecoder().decode(BrowserActionResult.self,from:Data(#"{"ok":true,"outcome":"verified","message":"Scroll movement verified"}"#.utf8))
        XCTAssertEqual(verified.summary,"Scroll movement verified")
        let failed=try JSONDecoder().decode(BrowserActionResult.self,from:Data(#"{"ok":false,"outcome":"failed","error":"Field reverted"}"#.utf8))
        XCTAssertEqual(failed.summary,"Field reverted")
    }
    func testVisualDifferenceDoesNotInventComparableFrames() {
        XCTAssertNil(VisualFingerprint(samples:[]).changedFraction(from:VisualFingerprint(samples:[])))
        XCTAssertNil(VisualFingerprint(samples:[0]).changedFraction(from:VisualFingerprint(samples:[0,1])))
        XCTAssertEqual(VisualFingerprint(samples:[0,0,30,40]).changedFraction(from:VisualFingerprint(samples:[0,10,0,0])),0.5)
    }
}
