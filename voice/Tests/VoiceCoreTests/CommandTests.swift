import XCTest
@testable import VoiceCore
final class CommandTests: XCTestCase {
    func testDemoCommands() {
        XCTAssertEqual(Parser.parse(". Create a new note."), [Command(.createNote)])
        XCTAssertEqual(Parser.parse("Can you open the Notes app for me"), [Command(.openApp,"com.apple.Notes")])
        XCTAssertEqual(Parser.parse("create a new note and make the title say hello"), [Command(.createNote),Command(.titleNote,"hello")])
        XCTAssertEqual(Parser.parse("Google search Norbert Wiener"), [Command(.searchWeb,"Norbert Wiener")])
        XCTAssertEqual(Parser.parse("open X.com"), [Command(.openURL,"https://x.com")])
        XCTAssertEqual(Parser.parse("open Photo Booth and take a picture of me"), [Command(.openApp,"com.apple.PhotoBooth"),Command(.takePhoto)])
    }
    func testNegativeAndData() {
        XCTAssertEqual(Parser.parse("don't open Notes"), [])
        XCTAssertEqual(Parser.parse("I opened Notes yesterday"), [])
        XCTAssertEqual(Parser.parse("search for war and peace"), [Command(.searchWeb,"war and peace")])
        XCTAssertEqual(Parser.parse("open Notes actually Safari"), [])
    }
    func testRevisionsAndRepetition() {
        var s = Scheduler()
        XCTAssertEqual(s.update("open Notes",final:false,now:0),[])
        XCTAssertEqual(s.update("open Notes and",final:false,now:0.5),[Command(.openApp,"com.apple.Notes")])
        XCTAssertEqual(s.update("open Notes",final:false,now:1),[])
        XCTAssertEqual(s.update("open Notes and create a new note",final:true,now:2),[Command(.createNote)])
        XCTAssertEqual(s.update("open Notes",final:true,now:3),[Command(.openApp,"com.apple.Notes")])
    }
    func testMutationWaits() {
        var s = Scheduler()
        XCTAssertEqual(s.update("take a picture",final:false,now:0),[])
        XCTAssertEqual(s.update("take a picture",final:false,now:10),[])
        XCTAssertEqual(s.update("take a picture",final:true,now:11),[Command(.takePhoto)])
    }
}
