import XCTest
@testable import VoiceCore

final class NativeMenuTests:XCTestCase {
    func testSpokenMenuCaptionsKeepLiteralNamesAndRemoveOnlyTrailingEllipsis() {
        XCTAssertEqual(NativeMenuLabels.aliases("Save as…",opensMenu:false),["Save as…","Save as","Save as menu item"])
        XCTAssertEqual(NativeMenuLabels.aliases("Export...",opensMenu:true),["Export...","Export","Export menu"])
        XCTAssertEqual(NativeMenuLabels.aliases("A…B",opensMenu:false),["A…B","A…B menu item"])
        XCTAssertEqual(NativeMenuLabels.aliases(" File ",opensMenu:true),["File","File menu"])
        XCTAssertTrue(NativeMenuLabels.aliases("  ",opensMenu:true).isEmpty)
    }
    func testNativeMenuCommandsDoNotBecomeAppLaunches() {
        for prefix in ["open the","show","expand"] {
            XCTAssertEqual(Parser.parse(prefix+" File menu"),[Command(.clickControl,"File menu")])
        }
        for verb in ["close","dismiss","cancel"] {
            XCTAssertEqual(Parser.parse(verb+" the menu"),[Command(.dismissMenu)])
            XCTAssertTrue(Parser.parse(verb+" the menu",browserContext:true).isEmpty)
        }
        XCTAssertTrue(Parser.parse("open File menu",browserContext:true).isEmpty)
        XCTAssertEqual(Parser.parse("open Notes"),[Command(.openApp,"com.apple.Notes")])
        XCTAssertTrue(Parser.parse("Do not open File menu").isEmpty)
        XCTAssertTrue(Parser.parse("Do not close menu").isEmpty)
    }
    func testMenuSequencesAndLiteralTextStaySeparate() {
        XCTAssertEqual(Parser.parse("open File menu then click Save as"),[Command(.clickControl,"File menu"),Command(.clickControl,"Save as")])
        XCTAssertEqual(Parser.parse("close menu then focus Subject"),[Command(.dismissMenu),Command(.focusControl,"Subject")])
        XCTAssertEqual(Parser.parse("type close menu then click Save"),[Command(.typeText,"close menu then click Save")])
        XCTAssertTrue(Parser.parse("open File menu then unsupported nonsense").isEmpty)
    }
}
