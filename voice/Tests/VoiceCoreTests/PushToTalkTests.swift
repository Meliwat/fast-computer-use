import XCTest
@testable import VoiceCore
final class PushToTalkTests: XCTestCase {
    func testHoldReleaseAndRepeat() {
        var key = PushToTalk()
        XCTAssertEqual(key.update(option:true, otherModifier:false), .begin)
        XCTAssertNil(key.update(option:true, otherModifier:false))
        XCTAssertEqual(key.update(option:false, otherModifier:false), .finish)
        XCTAssertNil(key.update(option:false, otherModifier:false))
        XCTAssertEqual(key.update(option:true, otherModifier:false), .begin)
    }
    func testShortcutCancelsUntilReleased() {
        var key = PushToTalk()
        XCTAssertEqual(key.update(option:true, otherModifier:false), .begin)
        XCTAssertEqual(key.update(option:true, otherModifier:true), .cancel)
        XCTAssertNil(key.update(option:true, otherModifier:false))
        XCTAssertNil(key.update(option:false, otherModifier:false))
        XCTAssertEqual(key.update(option:true, otherModifier:false), .begin)
    }
    func testExistingChordNeverStartsCapture() {
        var key = PushToTalk()
        XCTAssertNil(key.update(option:true, otherModifier:true))
        XCTAssertNil(key.update(option:true, otherModifier:false))
        XCTAssertNil(key.update(option:false, otherModifier:false))
    }
}
