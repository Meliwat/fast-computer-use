import XCTest
@testable import VoiceCore
final class BrowserCommandTests: XCTestCase {
    func testGenericCommands() throws {
        let cases: [(String, BrowserCommand)] = [
            ("fill Destination with Oslo", BrowserCommand(op:"fill",target:"Destination",value:"Oslo")),
            ("choose Canada from the Region dropdown", BrowserCommand(op:"select",target:"Region",value:"Canada")),
            ("check Email updates", BrowserCommand(op:"check",target:"Email updates",checked:true)),
            ("uncheck Email updates", BrowserCommand(op:"check",target:"Email updates",checked:false)),
            ("search this site for wooden toys", BrowserCommand(op:"search",value:"wooden toys")),
            ("scroll down", BrowserCommand(op:"scroll",value:"down")),
            ("next tab", BrowserCommand(op:"nextTab"))
        ]
        for (text, expected) in cases {
            let commands=Parser.parse(text)
            XCTAssertEqual(commands.count,1,text)
            XCTAssertEqual(try BrowserCommand.decode(XCTUnwrap(commands.first).value),expected,text)
        }
    }
    func testLiteralPayloadAndExistingTitle() {
        XCTAssertEqual(Parser.parse("set the title to hello"),[Command(.titleNote,"hello")])
        XCTAssertEqual(Parser.parse("fill Message with don't open Notes and click Send"),[BrowserCommand(op:"fill",target:"Message",value:"don't open Notes and click Send").command])
        XCTAssertTrue(Parser.hasDictation("fill Message with hello"))
        XCTAssertTrue(Parser.hasDictation("search this site for toys"))
        XCTAssertEqual(Parser.parse("don't check Email updates"),[])
    }
}
