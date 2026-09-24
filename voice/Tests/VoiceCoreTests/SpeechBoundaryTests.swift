import XCTest
@testable import VoiceCore
final class SpeechBoundaryTests: XCTestCase {
    func testPauseFinishesWithoutAppleFinal() {
        var boundary = SpeechBoundary(); var scheduler = Scheduler()
        boundary.update("create a new note", now: 1)
        XCTAssertFalse(boundary.shouldFinish(now: 1.5, lastVoiceAt: 1))
        XCTAssertTrue(boundary.shouldFinish(now: 1.9, lastVoiceAt: 1))
        XCTAssertEqual(scheduler.update("create a new note", final: true, now: 1.9), [Command(.createNote)])
    }
    func testContinuingSpeechAndRevisionsDelayBoundary() {
        var b = SpeechBoundary(); b.update("search for Norbert", now: 1)
        XCTAssertFalse(b.shouldFinish(now: 2, lastVoiceAt: 1.8))
        b.update("search for Norbert Wiener", now: 2)
        XCTAssertFalse(b.shouldFinish(now: 2.3, lastVoiceAt: 1.4))
        XCTAssertTrue(b.shouldFinish(now: 2.7, lastVoiceAt: 1.8))
    }
    func testSilenceWithoutTextDoesNothing() {
        XCTAssertFalse(SpeechBoundary().shouldFinish(now: 20, lastVoiceAt: 0))
    }
    func testPauseDoesNotRepeatEarlyOpen() {
        var s = Scheduler()
        _ = s.update("open Notes", final: false, now: 0)
        XCTAssertEqual(s.update("open Notes", final: false, now: 0.5), [Command(.openApp,"com.apple.Notes")])
        XCTAssertEqual(s.update("open Notes and create a new note", final: true, now: 2), [Command(.createNote)])
    }
}
