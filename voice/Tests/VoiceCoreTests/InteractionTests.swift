import XCTest
@testable import VoiceCore
final class InteractionTests: XCTestCase {
    func testLiteralDictation() {
        XCTAssertEqual(Parser.parse("type don't open Notes and send it"), [Command(.typeText,"don't open Notes and send it")])
        XCTAssertEqual(Parser.parse("type Hello. Open Codex then send it."), [Command(.typeText,"Hello. Open Codex then send it.")])
        XCTAssertEqual(Parser.parse("please type this: Hello there!"), [Command(.typeText,"Hello there!")])
        XCTAssertTrue(Parser.hasDictation("open Codex then type some words"))
        XCTAssertTrue(Parser.hasDictation("type"))
        XCTAssertFalse(Parser.hasDictation("open Notes"))
    }
    func testCompoundStopsSplittingAtDictation() {
        XCTAssertEqual(Parser.parse("open Codex, then start a new chat and type help me build a weather app"),
                       [Command(.openApp,"com.openai.codex"),Command(.newChat,"com.openai.codex"),Command(.typeText,"help me build a weather app")])
    }
    func testExplicitClickAndSend() {
        XCTAssertEqual(Parser.parse("click the Settings button"),[Command(.clickControl,"Settings")])
        XCTAssertEqual(Parser.parse("send it"),[Command(.sendDraft)])
        XCTAssertEqual(Parser.parse("submit the prompt"),[Command(.sendDraft)])
        XCTAssertEqual(Parser.parse("don't send it"),[])
        XCTAssertEqual(Parser.parse("type send it"),[Command(.typeText,"send it")])
    }
    func testUnicodeInsertionPreservesSelectionAndSurroundings() {
        XCTAssertEqual(InteractionRules.inserting("World",into:"Hello friend!",selection:NSRange(location:6,length:6)),"Hello World!")
        XCTAssertEqual(InteractionRules.inserting("!",into:"Hi 👋",selection:NSRange(location:5,length:0)),"Hi 👋!")
        XCTAssertNil(InteractionRules.inserting("x",into:"Hi",selection:NSRange(location:3,length:0)))
        XCTAssertNil(InteractionRules.inserting("x",into:"Hi",selection:NSRange(location:1,length:Int.max)))
    }
    func testExactUniqueEnabledControlMatching() {
        let labels = [["Send", "Send message"], ["Send later"], ["Send"]]
        XCTAssertEqual(InteractionRules.matchingIndices(labels:labels,enabled:[true,true,false],wanted:InteractionRules.sendLabels),[0])
        XCTAssertEqual(InteractionRules.matchingIndices(labels:labels,enabled:[true,true,true],wanted:InteractionRules.sendLabels),[0,2])
        XCTAssertEqual(InteractionRules.matchingIndices(labels:labels,enabled:[false,true,false],wanted:InteractionRules.sendLabels),[])
    }
    func testContextTracksManualAndCommandedAppChanges() {
        var context = AppContext()
        context.activated("com.openai.codex")
        context.observeForeground("dev.localvoice.prototype")
        XCTAssertEqual(context.app,"com.openai.codex")
        context.observeForeground("com.apple.TextEdit")
        XCTAssertEqual(context.app,"com.apple.TextEdit")
        context.observeForeground(nil)
        XCTAssertEqual(context.app,"com.apple.TextEdit")
    }
}
